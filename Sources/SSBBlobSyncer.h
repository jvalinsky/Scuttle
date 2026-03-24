#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBMuxRPCSession;
@class SSBBlobStore;

@interface SSBBlobSyncer : NSObject

- (instancetype)initWithBlobStore:(SSBBlobStore *)blobStore;

- (void)fetchBlob:(NSString *)blobID
          session:(SSBMuxRPCSession *)session
       completion:(void (^)(NSString * _Nullable path, NSError * _Nullable error))completion;

- (void)handleBlobRequest:(NSDictionary *)request
                requestID:(int32_t)reqID
                  session:(SSBMuxRPCSession *)session;

@end

NS_ASSUME_NONNULL_END
