#import "SRPlatformUI.h"

NS_ASSUME_NONNULL_BEGIN

/// A lightweight container that manages a stack of child view controllers.
/// At most one "detail" VC sits on top of the root VC at any time.
/// Proper viewWillAppear / viewWillDisappear lifecycle is delivered by
/// NSViewController's built-in transition mechanism.
@interface SRContentContainerViewController : NSViewController

/// Install the root VC without animation. Must be called before any push.
- (void)setRootViewController:(NSViewController *)vc;

/// Push a detail VC on top of the current top, replacing any existing detail
/// first. Animates with a crossfade.
- (void)pushViewController:(NSViewController *)vc;

/// Pop the top detail VC, revealing the root. No-op when at root.
- (void)popViewController;

/// The VC currently visible at the top of the stack.
@property (nonatomic, readonly, nullable) NSViewController *topViewController;

@end

NS_ASSUME_NONNULL_END
