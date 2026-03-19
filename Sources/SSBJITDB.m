#import "SSBJITDB.h"
#import "SSBBIPF.h"
#import "SSBLogCompat.h"

static NSString * const kIndexMetaFilename = @"index.meta";

@interface SSBJITDB () {
    SSBLog *_log;
    NSMutableDictionary<NSString *, SSBBitset *> *_bitsetIndexes;
    NSMutableDictionary<NSString *, SSBPrefixIndex *> *_prefixIndexes;
    NSString *_directory;
    /// How many records have been indexed so far. dbQueue only.
    uint64_t _indexedRecordCount;
    /// Dirty flag: YES when indexes have been updated but not yet saved to disk.
    BOOL _dirty;
    /// Coalescing timer that fires saveIndexes 250 ms after the last append.
    dispatch_source_t _saveTimer;
}
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t dbQueue;
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

        // Run index loading on dbQueue so that all subsequent index access
        // (including reindexing) is on the same serial queue that owns the indexes.
        dispatch_sync(_dbQueue, ^{
            [self loadIndexes];
        });
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
    dispatch_assert_queue(self.dbQueue);
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
    dispatch_assert_queue(self.dbQueue);
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

#pragma mark - Index save scheduling (C1)

/// Schedule a coalesced index save 250 ms from now. Must be called from dbQueue.
- (void)scheduleIndexSave {
    if (_saveTimer) {
        dispatch_source_cancel(_saveTimer);
        _saveTimer = nil;
    }
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.dbQueue);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                              DISPATCH_TIME_FOREVER,
                              10 * NSEC_PER_MSEC);
    __weak typeof(self) wself = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself saveIndexes];
        dispatch_source_cancel(sself->_saveTimer);
        sself->_saveTimer = nil;
    });
    dispatch_resume(timer);
    _saveTimer = timer;
    _dirty = YES;
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
                // C1: coalesce — schedule a save instead of writing on every append.
                [self scheduleIndexSave];
                completion(recordIndex, nil);
            });
        }];
    });
}

- (void)appendMessages:(NSArray<NSDictionary *> *)messages completion:(void(^)(NSError *))completion {
    if (messages.count == 0) {
        if (completion) completion(nil);
        return;
    }
    dispatch_async(self.dbQueue, ^{
        [self _batchAppend:messages index:0 firstError:nil completion:completion];
    });
}

/// Recursive helper that chains log appends one at a time, accumulating the first error.
/// Saves indexes once after all messages have been processed. Must be called from dbQueue.
- (void)_batchAppend:(NSArray<NSDictionary *> *)messages
               index:(NSUInteger)index
          firstError:(NSError *)firstError
          completion:(void(^)(NSError *))completion {
    if (index >= messages.count) {
        // All messages processed — save indexes a single time for the whole batch.
        [self saveIndexes];
        if (completion) {
            NSError *err = firstError;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(err); });
        }
        return;
    }

    NSDictionary *message = messages[index];
    NSData *bipf = [SSBBIPF encode:message];
    if (!bipf) {
        NSError *encodeError = firstError ?: [NSError errorWithDomain:@"JITDB" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode message to BIPF"}];
        [self _batchAppend:messages index:index + 1 firstError:encodeError completion:completion];
        return;
    }

    uint32_t length = (uint32_t)bipf.length;
    NSMutableData *recordData = [NSMutableData dataWithCapacity:sizeof(uint32_t) + length];
    [recordData appendBytes:&length length:sizeof(uint32_t)];
    [recordData appendData:bipf];

    [self->_log appendRecord:recordData completion:^(uint64_t recordIndex, NSError *error) {
        dispatch_async(self.dbQueue, ^{
            NSError *nextError = firstError;
            if (!error) {
                [self updateIndexesForMessage:message atSequence:recordIndex];
                self->_indexedRecordCount = recordIndex + 1;
            } else if (!nextError) {
                nextError = error;
            }
            [self _batchAppend:messages index:index + 1 firstError:nextError completion:completion];
        });
    }];
}

- (SSBBitset *)query:(NSDictionary *)query {
    __block SSBBitset *result = nil;

    dispatch_sync(self.dbQueue, ^{
        NSMutableDictionary *unindexedConstraints = [query mutableCopy];
        uint64_t recordCount = self->_log.recordCount;
        uint64_t capacity = recordCount > 0 ? recordCount : 1000000;

        // --- Indexed constraints (intersection-first, B1 fix) ---
        // Apply the type bitset index first — it produces a small candidate set directly
        // without scanning any records. The author prefix filter then runs on this smaller
        // set (O(k) instead of O(n)), avoiding a full universe scan.

        NSString *type = query[@"type"];
        if (type && ![type isEqual:[NSNull null]]) {
            NSString *indexKey = [NSString stringWithFormat:@"type:%@", type];
            SSBBitset *typeSet = self->_bitsetIndexes[indexKey];
            if (typeSet) {
                result = [typeSet copy];
                [unindexedConstraints removeObjectForKey:@"type"];
            }
        }

        NSString *author = query[@"author"];
        if (author) {
            SSBPrefixIndex *pIndex = [self prefixIndexForField:@"author" capacity:capacity];
            if (!result) {
                // No type constraint — start with universe so the author filter can prune it.
                result = [[SSBBitset alloc] initWithCapacity:capacity];
                [result not];
            }
            [pIndex filterBitset:result withValue:author];
            [unindexedConstraints removeObjectForKey:@"author"];
        }

        // No indexed constraint matched → full scan over all records.
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
    // Cancel any pending coalesced save and flush synchronously before closing.
    dispatch_sync(self.dbQueue, ^{
        if (self->_saveTimer) {
            dispatch_source_cancel(self->_saveTimer);
            self->_saveTimer = nil;
        }
        if (self->_dirty) {
            [self saveIndexes];
            self->_dirty = NO;
        }
    });
    [_log close];
}

#pragma mark - Index helpers (dbQueue only)

- (SSBBitset *)bitsetIndexForKey:(NSString *)key capacity:(uint64_t)cap {
    dispatch_assert_queue(self.dbQueue);
    SSBBitset *idx = _bitsetIndexes[key];
    if (!idx) {
        idx = [[SSBBitset alloc] initWithCapacity:cap];
        _bitsetIndexes[key] = idx;
    }
    return idx;
}

- (SSBPrefixIndex *)prefixIndexForField:(NSString *)field capacity:(uint64_t)cap {
    dispatch_assert_queue(self.dbQueue);
    SSBPrefixIndex *idx = _prefixIndexes[field];
    if (!idx) {
        idx = [[SSBPrefixIndex alloc] initWithCapacity:cap];
        _prefixIndexes[field] = idx;
    }
    return idx;
}

@end
