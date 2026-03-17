#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRMainSplitViewController : NSSplitViewController <NSToolbarDelegate>

- (void)showChannelBrowser;
- (void)showPreferences;

- (void)showGitActivity;
- (void)showGitMyRepos;
- (void)showGitFollowing;

@end

NS_ASSUME_NONNULL_END