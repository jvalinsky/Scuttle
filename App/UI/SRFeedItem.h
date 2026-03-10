#import <AppKit/AppKit.h>
#import "../../Sources/SSBNetwork.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRFeedItem : NSCollectionViewItem

@property (nonatomic, strong) NSTextField *authorLabel;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSTextField *cwLabel;
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSButton *showCWButton;
@property (nonatomic, strong) NSButton *replyButton;
@property (nonatomic, strong) NSButton *likeButton;
@property (nonatomic, strong) NSTextField *timestampLabel;
@property (nonatomic, weak) id owner;

@end

NS_ASSUME_NONNULL_END
