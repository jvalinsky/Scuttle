#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRMainSplitViewController : NSSplitViewController

- (void)showChannelBrowser;
- (void)showPreferences;

@end

NS_ASSUME_NONNULL_END