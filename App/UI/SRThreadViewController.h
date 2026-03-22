#import "SRPlatformUI.h"
#import "SRFeedItem.h"
#import <SSBNetwork/SSBFeedStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SRThreadViewController;
@class SSBRoomClient;

@protocol SRThreadViewControllerDelegate <NSObject>
@optional
- (void)threadViewControllerDidRequestBack:(SRThreadViewController *)vc;
- (void)threadViewController:(SRThreadViewController *)vc didLikeMessage:(SSBMessage *)message;
- (void)threadViewController:(SRThreadViewController *)vc didReplyToMessage:(SSBMessage *)message;
@end

@interface SRThreadViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, SRFeedItemOwner>

@property (nonatomic, weak, nullable) id<SRThreadViewControllerDelegate> delegate;
@property (nonatomic, strong) SSBMessage *rootMessage;
@property (nonatomic, weak, nullable) SSBRoomClient *client;

- (instancetype)initWithRootMessage:(SSBMessage *)message client:(nullable SSBRoomClient *)client;

@end

NS_ASSUME_NONNULL_END
