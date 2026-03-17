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

- (nullable NSViewController *)topViewController {
    return self.stack.lastObject;
}

- (void)setRootViewController:(NSViewController *)vc {
    NSAssert(self.stack.count == 0, @"-setRootViewController: called with non-empty stack");
    [self.stack addObject:vc];
    [self addChildViewController:vc];
    vc.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vc.view.frame = self.view.bounds;
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
    toVC.view.frame = fromVC ? fromVC.view.frame : self.view.bounds;

    if (fromVC) {
        [self transitionFromViewController:fromVC
                          toViewController:toVC
                                   options:NSViewControllerTransitionCrossfade
                         completionHandler:nil];
    } else {
        [self.view addSubview:toVC.view];
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
    }];
}

@end
