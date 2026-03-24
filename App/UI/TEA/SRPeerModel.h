#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRPeerSyncState) {
    SRPeerSyncStateDisconnected = 0,
    SRPeerSyncStateConnecting,
    SRPeerSyncStateSyncing,
    SRPeerSyncStateReady,
    SRPeerSyncStateError
};

@interface SRPeerModel : NSObject <NSCopying>

@property (nonatomic, readonly) NSString *peerID;
@property (nonatomic, readonly, nullable) NSString *displayName;
@property (nonatomic, readonly) SRPeerSyncState syncState;
@property (nonatomic, readonly) float syncProgress;
@property (nonatomic, readonly) NSInteger messageCount;
@property (nonatomic, readonly) BOOL isLocal;

- (instancetype)initWithPeerID:(NSString *)peerID;

- (instancetype)copyWithSyncState:(SRPeerSyncState)state;
- (instancetype)copyWithSyncProgress:(float)progress;
- (instancetype)copyWithMessageCount:(NSInteger)count;
- (instancetype)copyWithDisplayName:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
