#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBRoomClient;

@interface SRFeedViewController : NSViewController <NSCollectionViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>

@property (nonatomic, copy, nullable) NSString *filterAuthor;

- (void)refreshFeed;
- (void)loadFeedForAuthor:(NSString *)author client:(SSBRoomClient *)client;

@end

NS_ASSUME_NONNULL_END