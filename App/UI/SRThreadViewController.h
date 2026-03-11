#import <Cocoa/Cocoa.h>
#import <SSBNetwork/SSBFeedStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SRThreadViewController;

@protocol SRThreadViewControllerDelegate <NSObject>
@optional
- (void)threadViewControllerDidRequestBack:(SRThreadViewController *)vc;
- (void)threadViewController:(SRThreadViewController *)vc didLikeMessage:(SSBMessage *)message;
- (void)threadViewController:(SRThreadViewController *)vc didReplyToMessage:(SSBMessage *)message;
@end

@interface SRThreadViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>

@property (nonatomic, weak, nullable) id<SRThreadViewControllerDelegate> delegate;
@property (nonatomic, strong) SSBMessage *rootMessage;

- (instancetype)initWithRootMessage:(SSBMessage *)message;

@end

NS_ASSUME_NONNULL_END
