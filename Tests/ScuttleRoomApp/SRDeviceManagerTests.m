#import <XCTest/XCTest.h>
#import "../../App/Logic/SRDeviceManager.h"

#import "../../App/Logic/SRRoomManager.h"
#import "../../Sources/SSBSecretStore.h"

@interface SRDeviceManagerTests : XCTestCase
@property (nonatomic, copy) NSString *originalDeviceFeedID;
@end

@interface SRRoomManager (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBRoomClient *> *internalClients;
@end

@interface MockRoomClient : SSBRoomClient
@property (nonatomic, assign) BOOL publishCalled;
@property (nonatomic, strong) NSDictionary *lastPublishedContent;
@end

@implementation MockRoomClient
- (SSBMessage *)publishLocalMessageWithContent:(NSDictionary *)content error:(NSError **)error {
    self.publishCalled = YES;
    self.lastPublishedContent = content;
    // Return dummy message for success
    return [[SSBMessage alloc] init];
}
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

- (void)testRegisterThisDeviceIfNeeded_alreadyRegistered_returnsEarly {
    // Stage 1: Mark as registered
    [[NSUserDefaults standardUserDefaults] setObject:@"test-feed-id" forKey:@"com.scuttlebutt.deviceFeedID"];
    
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    // This should just exit immediately without looking at metafeed seed
    [manager registerThisDeviceIfNeeded];
    
    // Core verify is that it completes without causing errors on missing seed
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    XCTAssertEqualObjects(current, @"test-feed-id");
}

- (void)testRegisterThisDeviceIfNeeded_noMetafeed_returnsEarly {
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    // In isolated test without SSBLoadMetafeedSeed, it returns early
    [manager registerThisDeviceIfNeeded];
    
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    XCTAssertNil(current, @"Should not register without metafeed seed");
}

- (void)testRegisterThisDeviceIfNeeded_noConnectedClient_returnsEarly {
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    
    // Clear rooms or any client mocks
    [[SRRoomManager sharedManager].internalClients removeAllObjects];

    // Trigger registration - should exit because no of client
    [manager registerThisDeviceIfNeeded];
    
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"com.scuttlebutt.deviceFeedID"];
    XCTAssertNil(current, @"Should not register without connected client");
}

- (void)testRegisterThisDeviceIfNeeded_success_publishesMessage {
    SRDeviceManager *manager = [[SRDeviceManager alloc] init];
    
    // Stage 1: Setup seeds so early exits are bypassed
    NSData *seed = [NSMutableData dataWithLength:32];
    SSBSaveMetafeedSeed(seed);
    SSBSaveMetafeedRootID(@"test-root-id");
    
    // Stage 2: Inject Mock Client
    RoomConfig *config = [[RoomConfig alloc] init];
    config.host = @"test-host";
    MockRoomClient *mockClient = [[MockRoomClient alloc] initWithConfig:config localIdentity:seed];
    [SRRoomManager sharedManager].internalClients[@"test-host"] = mockClient;
    
    // Trigger registration
    [manager registerThisDeviceIfNeeded];
    
    // Verify publish called
    XCTAssertTrue(mockClient.publishCalled, @"Should publish derived feed message");
    XCTAssertNotNil(mockClient.lastPublishedContent, @"Should have published content");
    XCTAssertEqualObjects(mockClient.lastPublishedContent[@"type"], @"metafeed");
    
    // Cleanup
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.scuttlebutt.deviceFeedID"];
}

@end
