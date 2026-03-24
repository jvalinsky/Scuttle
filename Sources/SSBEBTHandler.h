#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBMuxRPCSession;
@class SSBFeedStore;
@class SSBEBTHandler;

@protocol SSBEBTHandlerDelegate <NSObject>
- (void)ebtHandler:(SSBEBTHandler *)handler didReplicateMessage:(NSDictionary *)message author:(NSString *)author;
- (void)ebtHandler:(SSBEBTHandler *)handler didUpdateSyncProgress:(float)progress author:(NSString *)author status:(NSString *)status;
@end

@interface SSBEBTHandler : NSObject

@property (nonatomic, weak, nullable) id<SSBEBTHandlerDelegate> delegate;

- (instancetype)initWithFeedStore:(SSBFeedStore *)feedStore
                      clientQueue:(dispatch_queue_t)clientQueue;

- (void)startReplicationWithSession:(SSBMuxRPCSession *)session peerID:(NSString *)peerID;

- (void)handleMessage:(id)message
            requestID:(int32_t)reqID
                flags:(uint8_t)flags
              session:(SSBMuxRPCSession *)session
               peerID:(NSString *)peerID;

- (NSDictionary<NSString *, NSNumber *> *)currentClockForPeer:(NSString *)peerID;

@end

NS_ASSUME_NONNULL_END
