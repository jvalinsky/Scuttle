#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRPreferencesWindowController : NSWindowController <NSWindowDelegate>

+ (instancetype)sharedPreferencesWindowController;

@end

NS_ASSUME_NONNULL_END
