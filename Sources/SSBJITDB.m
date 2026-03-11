#import "SSBJITDB.h"
#import "SSBBIPF.h"
#import <os/log.h>

@interface SSBJITDB () {
    SSBLog *_log;
    NSMutableDictionary<NSString *, SSBBitset *> *_bitsetIndexes;
    NSMutableDictionary<NSString *, SSBPrefixIndex *> *_prefixIndexes;
    NSString *_directory;
}
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@end

@implementation SSBJITDB

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _directory = directory;
        _dbQueue = dispatch_queue_create("com.scuttlebutt.jitdb", DISPATCH_QUEUE_SERIAL);
        
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *logPath = [directory stringByAppendingPathComponent:@"log.bin"];
        _log = [[SSBLog alloc] initWithPath:logPath];
        if (!_log) return nil;
        
        _bitsetIndexes = [NSMutableDictionary dictionary];
        _prefixIndexes = [NSMutableDictionary dictionary];
        
        [self loadIndexes];
    }
    return self;
}

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
}

- (void)saveIndexes {
    [_bitsetIndexes enumerateKeysAndObjectsUsingBlock:^(NSString *key, SSBBitset *obj, BOOL *stop) {
        NSString *path = [self->_directory stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"bitset"]];
        [obj.data writeToFile:path atomically:YES];
    }];
    [_prefixIndexes enumerateKeysAndObjectsUsingBlock:^(NSString *field, SSBPrefixIndex *obj, BOOL *stop) {
        NSString *path = [self->_directory stringByAppendingPathComponent:[field stringByAppendingPathExtension:@"prefix"]];
        [obj.data writeToFile:path atomically:YES];
    }];
}

- (void)appendMessage:(NSDictionary *)message completion:(void(^)(uint64_t, NSError *))completion {
    dispatch_async(self.dbQueue, ^{
        NSData *bipf = [SSBBIPF encode:message];
        if (!bipf) {
            completion(0, [NSError errorWithDomain:@"JITDB" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode message to BIPF"}]);
            return;
        }
        
        uint32_t length = (uint32_t)bipf.length;
        NSMutableData *recordData = [NSMutableData dataWithCapacity:sizeof(uint32_t) + length];
        [recordData appendBytes:&length length:sizeof(uint32_t)];
        [recordData appendData:bipf];
        
        [self->_log appendRecord:recordData completion:^(uint64_t offset, NSError *error) {
            if (error) {
                completion(0, error);
                return;
            }
            
            // For now, we manually update common indexes.
            // In JITDB, this would often happen during a lazy scan, but keeping
            // active indexes up-to-date on write is more efficient for fresh data.
            uint64_t seq = offset; // In this simple model, sequence is byte offset or we can use a record index.
            
            // Author Prefix Index
            NSString *author = message[@"author"];
            if (author) {
                [[self prefixIndexForField:@"author" capacity:1000000] addValue:author atSequence:seq];
            }
            
            // Type Bitset Index
            NSString *type = message[@"content"][@"type"];
            if (type) {
                NSString *indexKey = [NSString stringWithFormat:@"type:%@", type];
                [[self bitsetIndexForKey:indexKey capacity:1000000] setBitAtIndex:seq];
            }
            
            completion(seq, nil);
        }];
    });
}

- (SSBBitset *)query:(NSDictionary *)query {
    // This is a simplified query engine for the prototype.
    // It implements a subset of ssb-ql-0 logic.
    
    __block SSBBitset *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [[SSBBitset alloc] initWithCapacity:1000000];
        [result not]; // Start with all bits set (Universal set)
        
        NSString *author = query[@"author"];
        if (author) {
            SSBPrefixIndex *pIndex = [self prefixIndexForField:@"author" capacity:1000000];
            [pIndex filterBitset:result withValue:author];
        }
        
        NSString *type = query[@"type"];
        if (type && ![type isEqual:[NSNull null]]) {
            NSString *indexKey = [NSString stringWithFormat:@"type:%@", type];
            SSBBitset *bIndex = [self bitsetIndexForKey:indexKey capacity:1000000];
            [result andWithBitset:bIndex];
        }
        
        // Note: Real JITDB would check if these indexes exist and trigger a LOG SCAN if not.
    });
    return result;
}

- (void)fetchMessageAtSequence:(uint64_t)sequence completion:(void(^)(NSDictionary *, NSError *))completion {
    [self->_log readRecordAtOffset:sequence length:sizeof(uint32_t) completion:^(NSData *headerData, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (!headerData || headerData.length < sizeof(uint32_t)) {
            completion(nil, [NSError errorWithDomain:@"JITDB" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read record header"}]);
            return;
        }
        
        uint32_t length = 0;
        [headerData getBytes:&length length:sizeof(uint32_t)];
        
        [self->_log readRecordAtOffset:sequence + sizeof(uint32_t) length:length completion:^(NSData *payloadData, NSError *payloadError) {
            if (payloadError) {
                completion(nil, payloadError);
                return;
            }
            if (!payloadData || payloadData.length < length) {
                completion(nil, [NSError errorWithDomain:@"JITDB" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read payload"}]);
                return;
            }
            
            NSUInteger consumed = 0;
            NSDictionary *msg = [SSBBIPF decode:payloadData consumed:&consumed];
            completion(msg, nil);
        }];
    }];
}

#pragma mark - Index Management

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

- (void)close {
    [_log close];
}

@end
