#import <XCTest/XCTest.h>
#import "SRPlatformNotifications.h"

@interface SRPlatformNotificationsTests : XCTestCase
@end

@implementation SRPlatformNotificationsTests

- (void)testSharedNotifications_returnsNonNil {
    SRPlatformNotifications *shared = [SRPlatformNotifications sharedNotifications];
    XCTAssertNotNil(shared);
}

- (void)testSharedNotifications_returnsSameInstance {
    SRPlatformNotifications *a = [SRPlatformNotifications sharedNotifications];
    SRPlatformNotifications *b = [SRPlatformNotifications sharedNotifications];
    XCTAssertEqual(a, b);
}

- (void)testConfigure_doesNotCrash {
    XCTAssertNoThrow([[SRPlatformNotifications sharedNotifications] configure]);
}

- (void)testPostMessageFromAuthor_doesNotCrash {
    SRPlatformNotifications *notifs = [SRPlatformNotifications sharedNotifications];
    XCTAssertNoThrow([notifs postMessageFromAuthor:@"@alice.ed25519" text:@"Hello!"]);
}

- (void)testPostMessageFromAuthor_emptyText_doesNotCrash {
    SRPlatformNotifications *notifs = [SRPlatformNotifications sharedNotifications];
    XCTAssertNoThrow([notifs postMessageFromAuthor:@"@bob.ed25519" text:@""]);
}

- (void)testPostMessageFromAuthor_longText_doesNotCrash {
    SRPlatformNotifications *notifs = [SRPlatformNotifications sharedNotifications];
    NSString *longText = [@"" stringByPaddingToLength:1000 withString:@"X" startingAtIndex:0];
    XCTAssertNoThrow([notifs postMessageFromAuthor:@"@charlie.ed25519" text:longText]);
}

@end
