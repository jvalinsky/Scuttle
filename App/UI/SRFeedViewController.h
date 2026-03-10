#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBRoomClient;
@class SSBMessage;

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

@interface SRFeedViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>

@property (nonatomic, weak) id<SRFeedViewControllerDelegate> delegate;
@property (nonatomic, assign) SRFeedType feedType;
@property (nonatomic, copy, nullable) NSString *filterAuthor;
@property (nonatomic, copy, nullable) NSString *filterChannel;
@property (nonatomic, copy, nullable) NSString *filterSearch;

- (void)refreshFeed;
- (void)loadFeedForAuthor:(NSString *)author client:(SSBRoomClient *)client;
- (void)loadFeedForChannel:(NSString *)channel;
- (void)loadFeedWithSearch:(NSString *)searchText;

@end

NS_ASSUME_NONNULL_END