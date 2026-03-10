#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SRPeerListViewController;

@protocol SRPeerListDelegate <NSObject>
@optional
- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID;
- (void)peerListViewController:(SRPeerListViewController *)vc didRequestFollow:(NSString *)peerID;
- (void)peerListViewController:(SRPeerListViewController *)vc didRequestUnfollow:(NSString *)peerID;
@end

@interface SRPeerListViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, weak) id<SRPeerListDelegate> delegate;
- (void)updatePeers:(NSArray<NSString *> *)peers;

@end

NS_ASSUME_NONNULL_END