#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRErrorBannerView : NSView

@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *closeButton;

- (void)showMessage:(NSString *)message;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
