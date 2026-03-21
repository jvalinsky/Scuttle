#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "SRContentContainerViewController.h"

/// A minimal view controller with a real NSView, usable as push/pop targets in tests.
@interface SRTestChildVC : NSViewController
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) NSInteger viewWillAppearCount;
@property (nonatomic, assign) NSInteger viewWillDisappearCount;
@end

@implementation SRTestChildVC
- (void)loadView { self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)]; }
- (void)viewWillAppear { [super viewWillAppear]; self.viewWillAppearCount++; }
- (void)viewWillDisappear { [super viewWillDisappear]; self.viewWillDisappearCount++; }
@end

@interface SRContentContainerViewControllerTests : XCTestCase
@property (nonatomic, strong) SRContentContainerViewController *container;
@property (nonatomic, strong) NSWindow *window;
@end

@implementation SRContentContainerViewControllerTests

- (void)setUp {
    [super setUp];
    self.container = [[SRContentContainerViewController alloc] init];

    // Host in a real window so view-lifecycle callbacks fire.
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 400)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.contentViewController = self.container;
    [self.window makeKeyAndOrderFront:nil];
}

- (void)tearDown {
    [self.window close];
    [super tearDown];
}

#pragma mark - Initial state

- (void)testTopViewController_initiallyNil {
    // Before setRootViewController:, topViewController should be nil.
    SRContentContainerViewController *empty = [[SRContentContainerViewController alloc] init];
    XCTAssertNil(empty.topViewController);
}

#pragma mark - setRootViewController:

- (void)testSetRootViewController_topViewControllerIsRoot {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    root.identifier = @"root";
    [self.container setRootViewController:root];

    XCTAssertEqual(self.container.topViewController, root);
}

- (void)testSetRootViewController_rootViewAddedToContainerView {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    XCTAssertEqual(root.view.superview, self.container.view,
                   @"Root view must be a direct subview of the container");
}

- (void)testSetRootViewController_rootIsChildVC {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    XCTAssertTrue([self.container.childViewControllers containsObject:root]);
}

#pragma mark - pushViewController:

- (void)testPushViewController_topViewControllerChanges {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];

    XCTAssertEqual(self.container.topViewController, detail);
}

- (void)testPushViewController_detailIsChildVC {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];

    XCTAssertTrue([self.container.childViewControllers containsObject:detail]);
}

- (void)testPushViewController_stackDepthIsTwo {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];

    // root + detail = 2 children
    XCTAssertEqual(self.container.childViewControllers.count, 2);
}

- (void)testDoublePush_replacesFirstDetail {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail1 = [[SRTestChildVC alloc] init];
    detail1.identifier = @"detail1";
    [self.container pushViewController:detail1];

    SRTestChildVC *detail2 = [[SRTestChildVC alloc] init];
    detail2.identifier = @"detail2";
    [self.container pushViewController:detail2];

    // After double-push, stack depth must still be 2 (root + newest detail).
    XCTAssertEqual(self.container.childViewControllers.count, 2);
    XCTAssertEqual(self.container.topViewController, detail2);
    XCTAssertFalse([self.container.childViewControllers containsObject:detail1],
                   @"Replaced detail must be removed from child VCs");
}

- (void)testDoublePush_replacedDetailViewRemovedFromHierarchy {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail1 = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail1];

    SRTestChildVC *detail2 = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail2];

    // Wait for any transition to complete
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    XCTAssertNil(detail1.view.superview,
                 @"Replaced detail's view must be removed from the view hierarchy");
}

#pragma mark - popViewController:

- (void)testPopViewController_revealRoot {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];
    [self.container popViewController];

    // Wait for crossfade completion
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    XCTAssertEqual(self.container.topViewController, root);
}

- (void)testPopViewController_atRoot_isNoOp {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];

    // Pop with no detail — must not crash and must keep root
    XCTAssertNoThrow([self.container popViewController]);
    XCTAssertEqual(self.container.topViewController, root);
}

- (void)testPopViewController_stackDepthReducesToOne {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];
    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];
    [self.container popViewController];

    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    XCTAssertEqual(self.container.childViewControllers.count, 1);
}

- (void)testPopViewController_removesDetailFromChildVCs {
    SRTestChildVC *root = [[SRTestChildVC alloc] init];
    [self.container setRootViewController:root];
    SRTestChildVC *detail = [[SRTestChildVC alloc] init];
    [self.container pushViewController:detail];
    [self.container popViewController];

    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    XCTAssertFalse([self.container.childViewControllers containsObject:detail]);
}

@end
