#import <AppKit/AppKit.h>
#import "../../Sources/SSBNetwork.h"

NS_ASSUME_NONNULL_BEGIN

@class SSBRoomClient;
@class SRFeedItem;

@protocol SRFeedItemOwner <NSObject>
@optional
- (void)itemDidRequestReply:(SRFeedItem *)item;
- (void)itemDidRequestLike:(SRFeedItem *)item;
@end

@interface SRFeedItem : NSCollectionViewItem

@property (nonatomic, strong) NSTextField *authorLabel;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSTextField *cwLabel;
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSButton *showCWButton;
@property (nonatomic, strong) NSButton *replyButton;
@property (nonatomic, strong) NSButton *likeButton;
@property (nonatomic, strong) NSButton *qrButton;
@property (nonatomic, strong) NSTextField *timestampLabel;
@property (nonatomic, strong) NSImageView *blobImageView;
@property (nonatomic, weak) id<SRFeedItemOwner> owner;
@property (nonatomic, weak, nullable) SSBRoomClient *client;
@property (nonatomic, assign) BOOL isReply;

+ (nullable NSString *)extractBlobIDFromMessage:(SSBMessage *)msg;

@end

NS_ASSUME_NONNULL_END
