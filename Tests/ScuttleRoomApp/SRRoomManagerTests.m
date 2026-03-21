#import <XCTest/XCTest.h>
#import "SRRoomManager.h"

@interface SRRoomManagerTests : XCTestCase
@property (nonatomic, strong) SRRoomManager *manager;
@end

@implementation SRRoomManagerTests

- (void)setUp {
    [super setUp];
    // Use the shared manager — in the test environment, no rooms are saved so init is benign.
    self.manager = [SRRoomManager sharedManager];
}

#pragma mark - Notification constant names

- (void)testDidUpdateRoomsNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerDidUpdateRoomsNotification.length, 0U);
}

- (void)testDidUpdateEndpointsNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerDidUpdateEndpointsNotification.length, 0U);
}

- (void)testConnectionStatusChangedNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerConnectionStatusChangedNotification.length, 0U);
}

- (void)testEndpointsHostKey_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerEndpointsHostKey.length, 0U);
}

- (void)testEndpointsListKey_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerEndpointsListKey.length, 0U);
}

#pragma mark - Singleton

- (void)testSharedManager_returnsSameInstance {
    SRRoomManager *m2 = [SRRoomManager sharedManager];
    XCTAssertEqual(self.manager, m2);
}

#pragma mark - rooms / clients initial state

- (void)testRooms_isArray {
    XCTAssertNotNil(self.manager.rooms);
}

- (void)testClients_isDictionary {
    XCTAssertNotNil(self.manager.clients);
}

- (void)testRoomEndpoints_isDictionary {
    XCTAssertNotNil(self.manager.roomEndpoints);
}

#pragma mark - peerSyncStatesForHost:

- (void)testPeerSyncStatesForHost_unknownHost_returnsEmptyDict {
    NSDictionary *states = [self.manager peerSyncStatesForHost:@"nonexistent.example.com"];
    XCTAssertNotNil(states);
    XCTAssertEqual(states.count, 0U);
}

#pragma mark - peerSyncProgressForHost:

- (void)testPeerSyncProgressForHost_unknownHost_returnsEmptyDict {
    NSDictionary *progress = [self.manager peerSyncProgressForHost:@"nonexistent.example.com"];
    XCTAssertNotNil(progress);
    XCTAssertEqual(progress.count, 0U);
}

#pragma mark - syncStatusForHost:

- (void)testSyncStatusForHost_unknownHost_returnsNil {
    NSString *status = [self.manager syncStatusForHost:@"nonexistent.example.com"];
    XCTAssertNil(status);
}

#pragma mark - syncProgressForHost:

- (void)testSyncProgressForHost_unknownHost_returnsOne {
    float progress = [self.manager syncProgressForHost:@"nonexistent.example.com"];
    XCTAssertEqualWithAccuracy(progress, 1.0f, 0.001f);
}

#pragma mark - clientForHost:

- (void)testClientForHost_unknownHost_returnsNil {
    SSBRoomClient *client = [self.manager clientForHost:@"nonexistent.example.com"];
    XCTAssertNil(client);
}

#pragma mark - anyConnectedClient

- (void)testAnyConnectedClient_doesNotCrash {
    // Just verify the method runs without crashing. In a test environment the result
    // depends on saved rooms in the Keychain, so we only assert a non-crash here.
    XCTAssertNoThrow([self.manager anyConnectedClient]);
}

#pragma mark - displayNameForAuthor:

- (void)testDisplayNameForAuthor_emptyString_returnsEmpty {
    NSString *name = [self.manager displayNameForAuthor:@""];
    XCTAssertEqualObjects(name, @"");
}

- (void)testDisplayNameForAuthor_unknownAuthor_returnsAuthorOrEmpty {
    NSString *author = @"@notinstore.ed25519";
    NSString *name = [self.manager displayNameForAuthor:author];
    XCTAssertNotNil(name);
    // Either the store has a cached name, or it returns the author ID as fallback
    XCTAssertGreaterThan(name.length, 0U);
}

#pragma mark - joinRoomWithInvite - invalid invite

- (void)testJoinRoomWithInvite_invalidCode_callsCompletionWithError {
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [self.manager joinRoomWithInvite:@"not-a-valid-invite" completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
