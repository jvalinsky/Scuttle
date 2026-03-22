#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRNotificationType) {
    SRNotificationTypeInfo,
    SRNotificationTypeSuccess,
    SRNotificationTypeWarning,
    SRNotificationTypeError
};

@interface SRNotificationBannerView : NSVisualEffectView

+ (void)showInView:(NSView *)view message:(NSString *)message type:(SRNotificationType)type;

@end

NS_ASSUME_NONNULL_END
