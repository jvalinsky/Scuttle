#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Main window controller: sidebar navigation + content, modern macOS UI.
@interface SRMainSplitViewController : NSSplitViewController <NSToolbarDelegate>

/// Call to update the sidebar selection and show the given destination.
- (void)selectDestination:(NSString *)identifier;

/// Replaces the content area with the specified view controller for the selected destination.
- (void)showContentViewController:(NSViewController *)vc animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
