#import <XCTest/XCTest.h>
#import "../../App/Logic/SRDeviceManager.h"

@interface SRDeviceManagerTests : XCTestCase
@property (nonatomic, copy) NSString *originalDeviceFeedID;
@end

@implementation SRDeviceManagerTests

- (void)setUp {
    [super setUp];
    self.originalDeviceFeedID = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.scuttlebutt.deviceFeedID"];
}

- (void)tearDown {
    if (self.originalDeviceFeedID) {
        [[NSUserDefaults standardUserDefaults] setObject:self.originalDeviceFeedID forKey:@"com.scuttlebutt.deviceFeedID"];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.scuttlebutt.deviceFeedID"];
    }
    [super tearDown];
}

- (void)testSingleton {
    XCTAssertEqual([SRDeviceManager sharedManager], [SRDeviceManager sharedManager]);
}

- (void)testDeregisterDeviceRemovesFromUserDefaultsForLocalDevice {
    [[NSUserDefaults standardUserDefaults] setObject:@"test-feed-id" forKey:@"com.scuttlebutt.deviceFeedID"];
    
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    [manager deregisterDeviceWithFeedID:@"test-feed-id"];
    
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    XCTAssertNil(current, @"Deregistering the local device should clear its UserDefaults key");
}

- (void)testDeregisterDeviceIgnoresUserDefaultsForRemoteDevice {
    [[NSUserDefaults standardUserDefaults] setObject:@"local-device-id" forKey:@"com.scuttlebutt.deviceFeedID"];
    
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    [manager deregisterDeviceWithFeedID:@"some-other-device-id"];
    
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    XCTAssertEqualObjects(current, @"local-device-id", @"Deregistering a remote device should not clear local UserDefaults");
}

- (void)testRegisteredDeviceFeedIDsReturnsGracefullyWhenMissingRoots {
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    NSArray *feeds = [manager registeredDeviceFeedIDs];
    // In an isolated test environment without a loaded SSBMetafeed seed/DB, it returns an empty array.
    XCTAssertTrue([feeds isKindOfClass:[NSArray class]]);
}

@end
