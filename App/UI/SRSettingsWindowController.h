#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRSettingsWindowController : NSWindowController
+ (instancetype)sharedSettingsWindowController;
- (void)showSettings;
@end

NS_ASSUME_NONNULL_END
