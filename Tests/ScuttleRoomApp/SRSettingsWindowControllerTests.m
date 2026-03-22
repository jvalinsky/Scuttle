#import <XCTest/XCTest.h>
#import "SRSettingsWindowController.h"

@interface SRSettingsWindowControllerTests : XCTestCase
@end

@implementation SRSettingsWindowControllerTests

- (void)testSharedInstanceNonNil {
    SRSettingsWindowController *controller = [SRSettingsWindowController sharedSettingsWindowController];
    XCTAssertNotNil(controller);
}

- (void)testSingletonPattern {
    SRSettingsWindowController *first = [SRSettingsWindowController sharedSettingsWindowController];
    SRSettingsWindowController *second = [SRSettingsWindowController sharedSettingsWindowController];
    XCTAssertEqual(first, second);
}

- (void)testWindowCreated {
    SRSettingsWindowController *controller = [SRSettingsWindowController sharedSettingsWindowController];
    XCTAssertNotNil(controller.window);
}

- (void)testTabCount {
    SRSettingsWindowController *controller = [SRSettingsWindowController sharedSettingsWindowController];
    NSViewController *contentVC = controller.window.contentViewController;
    XCTAssertTrue([contentVC isKindOfClass:[NSTabViewController class]]);
    NSTabViewController *tabVC = (NSTabViewController *)contentVC;
    XCTAssertEqual(tabVC.tabViewItems.count, 4u);
}

@end
