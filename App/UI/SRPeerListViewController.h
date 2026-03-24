#import "SRPlatformUI.h"

NS_ASSUME_NONNULL_BEGIN

@class SRPeerListViewController;

@protocol SRPeerListDelegate <NSObject>
@optional
- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID;
- (void)peerListViewController:(SRPeerListViewController *)vc didRequestFollow:(NSString *)peerID;
- (void)peerListViewController:(SRPeerListViewController *)vc didRequestUnfollow:(NSString *)peerID;
- (void)peerListViewController:(SRPeerListViewController *)vc didRequestBlock:(NSString *)peerID blocking:(BOOL)blocking;
@end

@interface SRPeerListViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, weak) id<SRPeerListDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray<NSString *> *peers;
@property (nonatomic, strong, readonly) NSProgressIndicator *progressIndicator;
@property (nonatomic, copy, nullable) NSString *roomHost;
- (void)updatePeers:(NSArray<NSString *> *)peers;
- (void)updateSyncStatus:(NSDictionary<NSString *, NSString *> *)statuses progress:(NSDictionary<NSString *, NSNumber *> *)progress;

@end

NS_ASSUME_NONNULL_END
