#import "SSBBlobSyncer.h"
#import "SSBLogger.h"
#import "SSBBlobStore.h"
#import "SSBMuxRPCSession.h"

@interface SSBBlobSyncer ()
@property (nonatomic, strong) SSBBlobStore *blobStore;
@end

@implementation SSBBlobSyncer

- (instancetype)initWithBlobStore:(SSBBlobStore *)blobStore {
    self = [super init];
    if (self) {
        _blobStore = blobStore;
    }
    return self;
}

- (void)fetchBlob:(NSString *)blobID
          session:(SSBMuxRPCSession *)session
       completion:(void (^)(NSString * _Nullable path, NSError * _Nullable error))completion {
    
    SSBLogInfo(SSBLogCategorySync, @"Fetching blob: %@", blobID);
    [self.blobStore fetchBlob:blobID session:session completion:completion];
}

- (void)handleBlobRequest:(NSDictionary *)request
                requestID:(int32_t)reqID
                  session:(SSBMuxRPCSession *)session {
    
    NSArray *name = request[@"name"];
    if (![name isKindOfClass:[NSArray class]] || name.count < 2) return;
    
    NSString *method = name[1];
    if ([method isEqualToString:@"get"]) {
        NSString *blobID = [request[@"args"] firstObject];
        if (blobID) {
            NSData *data = [NSData dataWithContentsOfFile:[self.blobStore localPathForBlobID:blobID]];
            if (data) {
                [session sendData:data forRequest:reqID isEnd:YES];
            } else {
                [session sendData:@{@"name": @"Error", @"message": @"could not get blob"} forRequest:reqID isEnd:YES];
            }
        }
    } else if ([method isEqualToString:@"has"]) {
        NSString *blobID = [request[@"args"] firstObject];
        BOOL has = [self.blobStore hasBlob:blobID];
        [session sendData:@(has) forRequest:reqID isEnd:YES];
    }
}

@end
