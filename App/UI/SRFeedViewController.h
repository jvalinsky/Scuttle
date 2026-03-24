#import "SRPlatformUI.h"
#import "SRFeedItem.h"
#import <SSBNetwork/SSBFeedStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBRoomClient;
@class SRFeedViewController;

@protocol SRFeedViewControllerDelegate <NSObject>
@optional
- (void)feedViewController:(SRFeedViewController *)vc didLikeMessage:(SSBMessage *)message;
- (void)feedViewController:(SRFeedViewController *)vc didReplyToMessage:(SSBMessage *)message;
- (void)feedViewController:(SRFeedViewController *)vc didSelectMessageThread:(SSBMessage *)message;
@end

typedef NS_ENUM(NSInteger, SRFeedType) {
    SRFeedTypeTimeline,
    SRFeedTypeGlobal
};

@interface SRFeedViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, SRFeedItemOwner>

@property (nonatomic, weak) id<SRFeedViewControllerDelegate> delegate;
@property (nonatomic, assign) SRFeedType feedType;
@property (nonatomic, copy, nullable) NSString *filterAuthor;
@property (nonatomic, copy, nullable) NSString *filterChannel;
@property (nonatomic, copy, nullable) NSString *filterSearch;
@property (nonatomic, weak, nullable) SSBRoomClient *currentClient;
@property (nonatomic, strong, readonly) NSProgressIndicator *progressIndicator;

@property (nonatomic, assign) BOOL hidesBackButton;

- (void)setMessages:(NSArray<SSBMessage *> *)messages;
- (void)loadFeedForAuthor:(NSString *)author client:(SSBRoomClient *)client;
- (void)loadFeedForChannel:(NSString *)channel;
- (void)loadFeedWithSearch:(NSString *)searchText;

@end

NS_ASSUME_NONNULL_END
