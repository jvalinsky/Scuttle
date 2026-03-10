#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRProfileHeaderView : NSView

@property (nonatomic, strong, readonly) NSView *avatarView;
@property (nonatomic, strong, readonly) NSTextField *nameLabel;
@property (nonatomic, strong, readonly) NSTextField *pubkeyLabel;
@property (nonatomic, strong, readonly) NSButton *actionButton;

- (void)updateWithIdentity:(NSString *)pubkey name:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
