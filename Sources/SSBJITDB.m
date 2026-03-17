#import "SSBJITDB.h"
#import "SSBBIPF.h"
#import <os/log.h>

static NSString * const kIndexMetaFilename = @"index.meta";

@interface SSBJITDB () {
    SSBLog *_log;
    NSMutableDictionary<NSString *, SSBBitset *> *_bitsetIndexes;
    NSMutableDictionary<NSString *, SSBPrefixIndex *> *_prefixIndexes;
    NSString *_directory;
    /// How many records have been indexed so far. dbQueue only.
    uint64_t _indexedRecordCount;
}
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@end

@implementation SSBJITDB

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _directory = directory;
        _dbQueue = dispatch_queue_create("com.scuttlebutt.jitdb", DISPATCH_QUEUE_SERIAL);

        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        NSString *logPath = [directory stringByAppendingPathComponent:@"log.bin"];
        _log = [[SSBLog alloc] initWithPath:logPath];
        if (!_log) return nil;

        _bitsetIndexes = [NSMutableDictionary dictionary];
        _prefixIndexes = [NSMutableDictionary dictionary];

        [self loadIndexes];
    }
    return self;
}

#pragma mark - Index lifecycle

- (void)loadIndexes {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:_directory error:nil];
    for (NSString *file in files) {
        NSString *path = [_directory stringByAppendingPathComponent:file];
        if ([file hasSuffix:@".bitset"]) {
            NSString *key = [file stringByDeletingPathExtension];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data) _bitsetIndexes[key] = [[SSBBitset alloc] initWithData:data];
        } else if ([file hasSuffix:@".prefix"]) {
            NSString *field = [file stringByDeletingPathExtension];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data) _prefixIndexes[field] = [[SSBPrefixIndex alloc] initWithData:data];
        }
    }

    // Load the indexed-record-count stored alongside the indexes.
    NSString *metaPath = [_directory stringByAppendingPathComponent:kIndexMetaFilename];
    NSData *metaData = [NSData dataWithContentsOfFile:metaPath];
    if (metaData && metaData.length >= sizeof(uint64_t)) {
        [metaData getBytes:&_indexedRecordCount length:sizeof(uint64_t)];
    }

    // If new records were appended since the last index save, reindex them now.
    uint64_t logRecordCount = _log.recordCount;
    if (_indexedRecordCount < logRecordCount) {
        os_log_info(OS_LOG_DEFAULT,
            "SSBJITDB: Index out of date (indexed=%llu log=%llu). Reindexing.",
            _indexedRecordCount, logRecordCount);
        [self reindexFromRecord:_indexedRecordCount];
    }
}

- (void)reindexFromRecord:(uint64_t)startRecord {
    [_log enumerateRecordsUsingBlock:^BOOL(NSData *data, uint64_t recordIndex) {
        if (recordIndex < startRecord) return YES; // skip already-indexed records
        NSUInteger consumed = 0;
        NSDictionary *msg = [SSBBIPF decode:data consumed:&consumed];
        if (msg) [self updateIndexesForMessage:msg atSequence:recordIndex];
        return YES;
    }];
    _indexedRecordCount = _log.recordCount;
    [self saveIndexes];
}

- (void)updateIndexesForMessage:(NSDictionary *)message atSequence:(uint64_t)seq {
    // Must be called from dbQueue (or during init before dbQueue is shared).
    NSString *author = message[@"author"];
    if (author) {
        [[self prefixIndexForField:@"author" capacity:1000000] addValue:author atSequence:seq];
    }
    NSString *type = message[@"content"][@"type"];
    if (type) {
        NSString *indexKey = [NSString stringWithFormat:@"type:%@", type];
        [[self bitsetIndexForKey:indexKey capacity:1000000] setBitAtIndex:seq];
    }
}

- (void)saveIndexes {
    // Must be called from dbQueue (or during init/close before dbQueue is shared).
    [_bitsetIndexes enumerateKeysAndObjectsUsingBlock:^(NSString *key, SSBBitset *obj, BOOL *stop) {
        NSString *path = [self->_directory stringByAppendingPathComponent:
                          [key stringByAppendingPathExtension:@"bitset"]];
        [obj.data writeToFile:path atomically:YES];
    }];
    [_prefixIndexes enumerateKeysAndObjectsUsingBlock:^(NSString *field, SSBPrefixIndex *obj, BOOL *stop) {
        NSString *path = [self->_directory stringByAppendingPathComponent:
                          [field stringByAppendingPathExtension:@"prefix"]];
        [obj.data writeToFile:path atomically:YES];
    }];
    // Persist the indexed record count so startup can detect gaps.
    NSString *metaPath = [_directory stringByAppendingPathComponent:kIndexMetaFilename];
    NSData *metaData = [NSData dataWithBytes:&_indexedRecordCount length:sizeof(uint64_t)];
    [metaData writeToFile:metaPath atomically:YES];
}

#pragma mark - Public API

- (void)appendMessage:(NSDictionary *)message completion:(void(^)(uint64_t, NSError *))completion {
    dispatch_async(self.dbQueue, ^{
        NSData *bipf = [SSBBIPF encode:message];
        if (!bipf) {
            completion(0, [NSError errorWithDomain:@"JITDB" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode message to BIPF"}]);
            return;
        }

        uint32_t length = (uint32_t)bipf.length;
        NSMutableData *recordData = [NSMutableData dataWithCapacity:sizeof(uint32_t) + length];
        [recordData appendBytes:&length length:sizeof(uint32_t)];
        [recordData appendData:bipf];

        [self->_log appendRecord:recordData completion:^(uint64_t recordIndex, NSError *error) {
            // appendRecord completion fires on ioQueue; jump back to dbQueue for index work.
            dispatch_async(self.dbQueue, ^{
                if (error) {
                    completion(0, error);
                    return;
                }
                [self updateIndexesForMessage:message atSequence:recordIndex];
                self->_indexedRecordCount = recordIndex + 1;
                [self saveIndexes];
                completion(recordIndex, nil);
            });
        }];
    });
}

- (SSBBitset *)query:(NSDictionary *)query {
    __block SSBBitset *result = nil;

    dispatch_sync(self.dbQueue, ^{
        NSMutableDictionary *unindexedConstraints = [query mutableCopy];
        uint64_t recordCount = self->_log.recordCount;
        uint64_t capacity = recordCount > 0 ? recordCount : 1000000;

        // --- Indexed constraints ---
        // For the prefix (author) index: start with a universe bitset, filter in-place.
        // For bitset (type) indexes: copy or AND into result.
        NSString *author = query[@"author"];
        if (author) {
            SSBPrefixIndex *pIndex = [self prefixIndexForField:@"author" capacity:capacity];
            result = [[SSBBitset alloc] initWithCapacity:capacity];
            [result not]; // universe: all bits set
            [pIndex filterBitset:result withValue:author];
            [unindexedConstraints removeObjectForKey:@"author"];
        }

        NSString *type = query[@"type"];
        if (type && ![type isEqual:[NSNull null]]) {
            NSString *indexKey = [NSString stringWithFormat:@"type:%@", type];
            SSBBitset *typeSet = self->_bitsetIndexes[indexKey];
            if (typeSet) {
                if (result) {
                    [result andWithBitset:typeSet];
                } else {
                    result = [typeSet copy];
                }
                [unindexedConstraints removeObjectForKey:@"type"];
            }
        }

        // If no indexed constraint matched, start with all records (full scan).
        if (!result) {
            result = [[SSBBitset alloc] initWithCapacity:capacity];
            [result not];
        }

        // --- Unindexed constraints: scan only candidate records ---
        if (unindexedConstraints.count > 0) {
            [self->_log enumerateRecordsUsingBlock:^BOOL(NSData *data, uint64_t recordIndex) {
                if (![result isBitSetAtIndex:recordIndex]) return YES; // already excluded

                NSUInteger consumed = 0;
                NSDictionary *msg = [SSBBIPF decode:data consumed:&consumed];
                if (!msg) return YES;

                __block BOOL match = YES;
                [unindexedConstraints enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *innerStop) {
                    id actualVal = msg[key];
                    if (!actualVal && [key isEqualToString:@"type"]) {
                        actualVal = msg[@"content"][@"type"];
                    }
                    if (![actualVal isEqual:val]) {
                        match = NO;
                        *innerStop = YES;
                    }
                }];

                if (!match) [result clearBitAtIndex:recordIndex];
                return YES;
            }];
        }
    });

    return result ?: [[SSBBitset alloc] initWithCapacity:1000000];
}

- (void)fetchMessageAtSequence:(uint64_t)sequence completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    // Bounds check before dispatching the async read.
    uint64_t recordCount = _log.recordCount;
    if (sequence >= recordCount) {
        completion(nil, [NSError errorWithDomain:@"JITDB" code:5
            userInfo:@{NSLocalizedDescriptionKey: @"Sequence out of bounds"}]);
        return;
    }

    [_log readRecordAtIndex:sequence completion:^(NSData *payloadData, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (!payloadData) {
            completion(nil, [NSError errorWithDomain:@"JITDB" code:3
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to read record payload"}]);
            return;
        }
        NSUInteger consumed = 0;
        NSDictionary *msg = [SSBBIPF decode:payloadData consumed:&consumed];
        completion(msg, nil);
    }];
}

- (void)close {
    // Flush indexes before releasing the log.
    dispatch_sync(self.dbQueue, ^{
        [self saveIndexes];
    });
    [_log close];
}

#pragma mark - Index helpers (dbQueue only)

- (SSBBitset *)bitsetIndexForKey:(NSString *)key capacity:(uint64_t)cap {
    SSBBitset *idx = _bitsetIndexes[key];
    if (!idx) {
        idx = [[SSBBitset alloc] initWithCapacity:cap];
        _bitsetIndexes[key] = idx;
    }
    return idx;
}

- (SSBPrefixIndex *)prefixIndexForField:(NSString *)field capacity:(uint64_t)cap {
    SSBPrefixIndex *idx = _prefixIndexes[field];
    if (!idx) {
        idx = [[SSBPrefixIndex alloc] initWithCapacity:cap];
        _prefixIndexes[field] = idx;
    }
    return idx;
}

@end
