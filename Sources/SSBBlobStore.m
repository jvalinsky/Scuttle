#import "SSBBlobStore.h"
#import "SSBMuxRPCSession.h"
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

static os_log_t blob_store_log;

@interface SSBBlobStore ()
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SSBBlobFetchCompletion> *> *pendingFetches;
@end

@implementation SSBBlobStore

+ (void)initialize {
    if (self == [SSBBlobStore class]) {
        blob_store_log = os_log_create("com.scuttlebutt.app", "BlobStore");
    }
}

+ (instancetype)sharedStore {
    static SSBBlobStore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SSBBlobStore alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        _basePath = [appSupport stringByAppendingPathComponent:@"ScuttleKit/blobs"];
        _ioQueue = dispatch_queue_create("com.scuttlebutt.blobstore", DISPATCH_QUEUE_SERIAL);
        _pendingFetches = [NSMutableDictionary dictionary];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:_basePath]) {
            [fm createDirectoryAtPath:_basePath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return self;
}

- (NSString *)blobsDirectory {
    return self.basePath;
}

- (NSString *)filenameForBlobID:(NSString *)blobID {
    NSString *name = blobID;
    if ([name hasPrefix:@"&"]) name = [name substringFromIndex:1];
    name = [name stringByReplacingOccurrencesOfString:@".sha256" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    name = [name stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    name = [name stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return [name stringByAppendingString:@".blob"];
}

- (nullable NSString *)localPathForBlobID:(NSString *)blobID {
    NSString *filename = [self filenameForBlobID:blobID];
    NSString *path = [self.basePath stringByAppendingPathComponent:filename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    return nil;
}

- (BOOL)hasBlob:(NSString *)blobID {
    return [self localPathForBlobID:blobID] != nil;
}

- (nullable NSString *)addBlobWithData:(NSData *)data {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *blobID = [NSString stringWithFormat:@"&%@.sha256", [hashData base64EncodedStringWithOptions:0]];
    
    NSString *path = [self storeBlob:data forBlobID:blobID];
    return path ? blobID : nil;
}

- (nullable NSString *)storeBlob:(NSData *)data forBlobID:(NSString *)blobID {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *computedHash = [NSString stringWithFormat:@"&%@.sha256", [hashData base64EncodedStringWithOptions:0]];
    
    if (![computedHash isEqualToString:blobID]) {
        os_log_error(blob_store_log, "Hash mismatch for %{public}@: computed %{public}@", blobID, computedHash);
        return nil;
    }
    
    NSString *filename = [self filenameForBlobID:blobID];
    NSString *path = [self.basePath stringByAppendingPathComponent:filename];
    [data writeToFile:path atomically:YES];
    os_log_info(blob_store_log, "Stored blob %{public}@ (%lu bytes)", blobID, (unsigned long)data.length);
    return path;
}

- (void)fetchBlob:(NSString *)blobID session:(SSBMuxRPCSession *)session completion:(SSBBlobFetchCompletion)completion {
    NSString *existing = [self localPathForBlobID:blobID];
    if (existing) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(existing, nil);
        });
        return;
    }
    
    @synchronized (self.pendingFetches) {
        NSMutableArray *pending = self.pendingFetches[blobID];
        if (pending) {
            [pending addObject:[completion copy]];
            return;
        }
        self.pendingFetches[blobID] = [NSMutableArray arrayWithObject:[completion copy]];
    }
    
    __block NSMutableData *accumulated = [NSMutableData data];
    __weak typeof(self) weakSelf = self;
    
    [session sendRequest:@[@"blobs", @"get"] args:@[blobID] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            os_log_error(blob_store_log, "Fetch error for %{public}@: %{public}@", blobID, error.localizedDescription);
            [weakSelf completePendingFetches:blobID path:nil error:error];
            return;
        }
        
        if (response) {
            if ([response isKindOfClass:[NSData class]]) {
                [accumulated appendData:(NSData *)response];
            } else if ([response isKindOfClass:[NSString class]]) {
                NSData *chunk = [(NSString *)response dataUsingEncoding:NSUTF8StringEncoding];
                if (chunk) [accumulated appendData:chunk];
            }
        } else {
            dispatch_async(weakSelf.ioQueue, ^{
                NSString *path = [weakSelf storeBlob:accumulated forBlobID:blobID];
                NSError *storeError = nil;
                if (!path) {
                    storeError = [NSError errorWithDomain:@"SSBBlobStore" code:1
                                                userInfo:@{NSLocalizedDescriptionKey: @"Hash verification failed"}];
                }
                [weakSelf completePendingFetches:blobID path:path error:storeError];
            });
        }
    }];
}

- (void)completePendingFetches:(NSString *)blobID path:(nullable NSString *)path error:(nullable NSError *)error {
    NSArray<SSBBlobFetchCompletion> *completions;
    @synchronized (self.pendingFetches) {
        completions = [self.pendingFetches[blobID] copy];
        [self.pendingFetches removeObjectForKey:blobID];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SSBBlobFetchCompletion block in completions) {
            block(path, error);
        }
    });
}

- (NSUInteger)totalStorageSize {
    __block NSUInteger total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        NSString *path = [self.basePath stringByAppendingPathComponent:file];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        total += [attrs[NSFileSize] unsignedIntegerValue];
    }
    return total;
}

- (void)wipeBlobs {
    dispatch_sync(self.ioQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:self.basePath error:nil];
        [fm createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];
    });
    os_log_info(blob_store_log, "Wiped all blobs");
}

@end
