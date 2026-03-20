#import "SRContentContainerViewController.h"

@interface SRContentContainerViewController ()
/// stack[0] is always the root; stack[1] (when present) is the detail.
@property (nonatomic, strong) NSMutableArray<NSViewController *> *stack;
@end

@implementation SRContentContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.stack = [NSMutableArray array];
}

- (NSRect)contentFrameForCurrentBounds {
    NSRect frame = self.view.bounds;
    NSEdgeInsets insets = self.view.safeAreaInsets;
    frame.origin.x += insets.left;
    frame.origin.y += insets.bottom;
    frame.size.width -= (insets.left + insets.right);
    frame.size.height -= (insets.top + insets.bottom);
    return NSIntegralRect(frame);
}

- (void)layoutStackViews {
    NSRect frame = [self contentFrameForCurrentBounds];
    for (NSViewController *vc in self.stack) {
        vc.view.frame = frame;
    }
}

- (void)viewDidLayout {
    [super viewDidLayout];
    [self layoutStackViews];
}

- (nullable NSViewController *)topViewController {
    return self.stack.lastObject;
}

- (void)setRootViewController:(NSViewController *)vc {
    NSAssert(self.stack.count == 0, @"-setRootViewController: called with non-empty stack");
    [self.stack addObject:vc];
    [self addChildViewController:vc];
    vc.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vc.view.frame = [self contentFrameForCurrentBounds];
    [self.view addSubview:vc.view];
}

- (void)pushViewController:(NSViewController *)toVC {
    // If a detail is already showing, remove it immediately (no animation) so
    // the new push crossfades from the root rather than stacking on top.
    if (self.stack.count > 1) {
        NSViewController *existing = self.stack.lastObject;
        [self.stack removeLastObject];
        [existing.view removeFromSuperview];
        [existing removeFromParentViewController];
    }

    NSViewController *fromVC = self.stack.lastObject;
    [self.stack addObject:toVC];
    [self addChildViewController:toVC];
    toVC.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    toVC.view.frame = fromVC ? fromVC.view.frame : [self contentFrameForCurrentBounds];

    if (fromVC) {
        [self transitionFromViewController:fromVC
                          toViewController:toVC
                                   options:NSViewControllerTransitionCrossfade
                         completionHandler:^{
            [self layoutStackViews];
        }];
    } else {
        [self.view addSubview:toVC.view];
        [self layoutStackViews];
    }
}

- (void)popViewController {
    if (self.stack.count < 2) return;

    NSViewController *fromVC = self.stack.lastObject;
    NSViewController *toVC = self.stack[self.stack.count - 2];
    [self.stack removeLastObject];

    [self transitionFromViewController:fromVC
                      toViewController:toVC
                               options:NSViewControllerTransitionCrossfade
                     completionHandler:^{
        [fromVC removeFromParentViewController];
        [self layoutStackViews];
    }];
}

@end
