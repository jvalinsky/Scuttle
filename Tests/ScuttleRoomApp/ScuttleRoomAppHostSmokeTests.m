#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

@interface ScuttleRoomAppHostSmokeTests : XCTestCase
@end

@implementation ScuttleRoomAppHostSmokeTests

- (void)testHostBundleIsAppUnderTest {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    XCTAssertTrue([bundleIdentifier isEqualToString:@"com.scuttlebutt.ScuttleRoomApp"]);
}

- (void)testApplicationInstanceIsAvailable {
    NSApplication *app = NSApp ?: [NSApplication sharedApplication];
    XCTAssertNotNil(app);
}

- (void)testAppDelegateClassIsLinked {
    XCTAssertNotNil(NSClassFromString(@"AppDelegate"));
}

@end
