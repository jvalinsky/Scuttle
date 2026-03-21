#import <XCTest/XCTest.h>
#import "SSBRoomClient.h"
#import "RoomInviteHandler.h"

// Expose private methods for testing
@interface SSBRoomClient (Testing)
- (nullable NSString *)peerIDFromEndpointItem:(id)item;
- (NSArray<NSString *> *)normalizedPeerIDsFromCollection:(NSArray *)items;
- (NSArray<NSString *> *)filteredAttendantPeerIDs:(NSArray<NSString *> *)peerIDs;
- (NSString *)syncStatusForTunnelError:(NSError *)error;
- (NSTimeInterval)tunnelRetryDelayForStatus:(NSString *)status;
- (BOOL)isAttendantsEventDictionary:(NSDictionary *)dict;
- (nullable id)jsonObjectFromDataIfPossible:(NSData *)data;
- (id)normalizedAttendantsPayloadFromResponse:(id)response;
- (BOOL)manifestDictionary:(NSDictionary *)manifest supportsRPCPath:(NSArray<NSString *> *)path;
- (BOOL)manifestSupportsRPCPath:(NSArray<NSString *> *)path;
- (NSArray<NSString *> *)preferredEndpointDiscoveryMethod;
- (BOOL)isRoomAttendantsMethod:(NSArray<NSString *> *)method;
- (BOOL)isTunnelEndpointsMethod:(NSArray<NSString *> *)method;
- (nullable NSString *)tracePeerID;
@end

@interface SSBRoomClientTests : XCTestCase
@property (nonatomic, strong) SSBRoomClient *client;
@end

@implementation SSBRoomClientTests

- (void)setUp {
    [super setUp];
    NSData *localIdentity = [SSBRoomClient generateLocalIdentity];
    NSData *fakeServerKey = [NSMutableData dataWithLength:32];
    self.client = [[SSBRoomClient alloc] initWithHost:@"example.com"
                                                 port:8008
                                         serverPubKey:fakeServerKey
                                        localIdentity:localIdentity];
}

#pragma mark - Initialization

- (void)testInit_setsHost {
    XCTAssertEqualObjects(self.client.host, @"example.com");
}

- (void)testInit_setsPort {
    XCTAssertEqual(self.client.port, 8008);
}

- (void)testInit_notConnectedInitially {
    XCTAssertFalse(self.client.isConnected);
}

- (void)testInit_pendingMessagesCountIsZero {
    XCTAssertEqual(self.client.pendingMessagesCount, 0);
}

- (void)testInit_peerSyncProgressIsEmpty {
    NSDictionary *progress = self.client.peerSyncProgress;
    XCTAssertNotNil(progress);
    XCTAssertEqual(progress.count, 0U);
}

- (void)testInit_peerSyncStatesIsEmpty {
    NSDictionary *states = self.client.peerSyncStates;
    XCTAssertNotNil(states);
    XCTAssertEqual(states.count, 0U);
}

- (void)testInitWithConfig_setsInviteToken {
    NSData *fakeKey = [NSMutableData dataWithLength:32];
    RoomConfig *config = [[RoomConfig alloc] initWithHost:@"room.example.com" port:8008 pubKey:fakeKey];
    config.inviteToken = @"tok123";
    NSData *localIdentity = [SSBRoomClient generateLocalIdentity];
    SSBRoomClient *client = [[SSBRoomClient alloc] initWithConfig:config localIdentity:localIdentity];
    XCTAssertEqualObjects(client.inviteToken, @"tok123");
    XCTAssertEqualObjects(client.host, @"room.example.com");
}

#pragma mark - generateLocalIdentity

- (void)testGenerateLocalIdentity_returns64Bytes {
    NSData *identity = [SSBRoomClient generateLocalIdentity];
    XCTAssertNotNil(identity);
    XCTAssertEqual(identity.length, 64U);
}

- (void)testGenerateLocalIdentity_producesUniqueValues {
    NSData *id1 = [SSBRoomClient generateLocalIdentity];
    NSData *id2 = [SSBRoomClient generateLocalIdentity];
    XCTAssertNotEqualObjects(id1, id2);
}

#pragma mark - peerIDFromEndpointItem:

- (void)testPeerIDFromEndpointItem_string_returnsString {
    NSString *peerID = [self.client peerIDFromEndpointItem:@"@abc.ed25519"];
    XCTAssertEqualObjects(peerID, @"@abc.ed25519");
}

- (void)testPeerIDFromEndpointItem_emptyString_returnsNil {
    NSString *peerID = [self.client peerIDFromEndpointItem:@""];
    XCTAssertNil(peerID);
}

- (void)testPeerIDFromEndpointItem_nil_returnsNil {
    NSString *peerID = [self.client peerIDFromEndpointItem:nil];
    XCTAssertNil(peerID);
}

- (void)testPeerIDFromEndpointItem_arrayWithString_returnsFirst {
    NSString *peerID = [self.client peerIDFromEndpointItem:@[@"@peer1.ed25519", @"@peer2.ed25519"]];
    XCTAssertEqualObjects(peerID, @"@peer1.ed25519");
}

- (void)testPeerIDFromEndpointItem_arrayWithEmptyStrings_returnsNil {
    NSString *peerID = [self.client peerIDFromEndpointItem:@[@"", @""]];
    XCTAssertNil(peerID);
}

- (void)testPeerIDFromEndpointItem_dictWithId_returnsId {
    NSString *peerID = [self.client peerIDFromEndpointItem:@{@"id": @"@peer.ed25519"}];
    XCTAssertEqualObjects(peerID, @"@peer.ed25519");
}

- (void)testPeerIDFromEndpointItem_dictWithKey_returnsKey {
    NSString *peerID = [self.client peerIDFromEndpointItem:@{@"key": @"@peer.ed25519"}];
    XCTAssertEqualObjects(peerID, @"@peer.ed25519");
}

- (void)testPeerIDFromEndpointItem_dictWithFeed_returnsFeed {
    NSString *peerID = [self.client peerIDFromEndpointItem:@{@"feed": @"@peer.ed25519"}];
    XCTAssertEqualObjects(peerID, @"@peer.ed25519");
}

- (void)testPeerIDFromEndpointItem_dictWithNestedPeer_returnsPeerID {
    NSDictionary *item = @{@"peer": @"@nested.ed25519"};
    NSString *peerID = [self.client peerIDFromEndpointItem:item];
    XCTAssertEqualObjects(peerID, @"@nested.ed25519");
}

- (void)testPeerIDFromEndpointItem_dictWithNestedValue_returnsValueID {
    NSDictionary *item = @{@"value": @{@"id": @"@invalue.ed25519"}};
    NSString *peerID = [self.client peerIDFromEndpointItem:item];
    XCTAssertEqualObjects(peerID, @"@invalue.ed25519");
}

- (void)testPeerIDFromEndpointItem_nonStringNonArrayNonDict_returnsNil {
    NSString *peerID = [self.client peerIDFromEndpointItem:@42];
    XCTAssertNil(peerID);
}

#pragma mark - normalizedPeerIDsFromCollection:

- (void)testNormalizedPeerIDs_deduplicates {
    NSArray *items = @[@"@peer1.ed25519", @"@peer2.ed25519", @"@peer1.ed25519"];
    NSArray *result = [self.client normalizedPeerIDsFromCollection:items];
    XCTAssertEqual(result.count, 2U);
    XCTAssertTrue([result containsObject:@"@peer1.ed25519"]);
    XCTAssertTrue([result containsObject:@"@peer2.ed25519"]);
}

- (void)testNormalizedPeerIDs_emptyCollection_returnsEmpty {
    NSArray *result = [self.client normalizedPeerIDsFromCollection:@[]];
    XCTAssertEqual(result.count, 0U);
}

- (void)testNormalizedPeerIDs_skipsEmptyStrings {
    NSArray *result = [self.client normalizedPeerIDsFromCollection:@[@"", @"@peer.ed25519"]];
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqualObjects(result.firstObject, @"@peer.ed25519");
}

#pragma mark - filteredAttendantPeerIDs:

- (void)testFilteredAttendants_removesEmptyStrings {
    NSArray *result = [self.client filteredAttendantPeerIDs:@[@"", @"@peer.ed25519"]];
    XCTAssertEqual(result.count, 1U);
}

- (void)testFilteredAttendants_deduplicates {
    NSArray *result = [self.client filteredAttendantPeerIDs:@[@"@peer.ed25519", @"@peer.ed25519"]];
    XCTAssertEqual(result.count, 1U);
}

#pragma mark - syncStatusForTunnelError:

- (void)testSyncStatus_selfError_returnsThisDevice {
    NSError *err = [NSError errorWithDomain:@"Test" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"Can't connect to self"}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"This Device");
}

- (void)testSyncStatus_strangerError_returnsStranger {
    NSError *err = [NSError errorWithDomain:@"Test" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"Peer is a stranger"}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"Stranger");
}

- (void)testSyncStatus_connectionError_returnsDisconnected {
    NSError *err = [NSError errorWithDomain:@"Test" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"Connection refused"}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"Disconnected");
}

- (void)testSyncStatus_sessionTerminated_returnsDisconnected {
    NSError *err = [NSError errorWithDomain:@"Test" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"Session terminated unexpectedly"}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"Disconnected");
}

- (void)testSyncStatus_unknownError_returnsUnavailable {
    NSError *err = [NSError errorWithDomain:@"Test" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"Something else happened"}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"Unavailable");
}

- (void)testSyncStatus_noLocalizedDescription_returnsUnavailable {
    NSError *err = [NSError errorWithDomain:@"Test" code:1 userInfo:@{}];
    NSString *status = [self.client syncStatusForTunnelError:err];
    XCTAssertEqualObjects(status, @"Unavailable");
}

#pragma mark - tunnelRetryDelayForStatus:

- (void)testRetryDelay_stranger_is60 {
    XCTAssertEqualWithAccuracy([self.client tunnelRetryDelayForStatus:@"Stranger"], 60.0, 0.01);
}

- (void)testRetryDelay_thisDevice_is300 {
    XCTAssertEqualWithAccuracy([self.client tunnelRetryDelayForStatus:@"This Device"], 300.0, 0.01);
}

- (void)testRetryDelay_disconnected_is5 {
    XCTAssertEqualWithAccuracy([self.client tunnelRetryDelayForStatus:@"Disconnected"], 5.0, 0.01);
}

- (void)testRetryDelay_unknown_is15 {
    XCTAssertEqualWithAccuracy([self.client tunnelRetryDelayForStatus:@"Unavailable"], 15.0, 0.01);
}

#pragma mark - isAttendantsEventDictionary:

- (void)testIsAttendantsEvent_withType_returnsYES {
    XCTAssertTrue([self.client isAttendantsEventDictionary:@{@"type": @"state"}]);
}

- (void)testIsAttendantsEvent_withIds_returnsYES {
    XCTAssertTrue([self.client isAttendantsEventDictionary:@{@"ids": @[]}]);
}

- (void)testIsAttendantsEvent_withPeers_returnsYES {
    XCTAssertTrue([self.client isAttendantsEventDictionary:@{@"peers": @[]}]);
}

- (void)testIsAttendantsEvent_empty_returnsNO {
    XCTAssertFalse([self.client isAttendantsEventDictionary:@{}]);
}

- (void)testIsAttendantsEvent_unrelatedKey_returnsNO {
    XCTAssertFalse([self.client isAttendantsEventDictionary:@{@"unrelated": @"value"}]);
}

#pragma mark - jsonObjectFromDataIfPossible:

- (void)testJsonObjectFromData_validJSON_returnsParsed {
    NSData *data = [@"{\"key\":\"value\"}" dataUsingEncoding:NSUTF8StringEncoding];
    id result = [self.client jsonObjectFromDataIfPossible:data];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"key"], @"value");
}

- (void)testJsonObjectFromData_emptyData_returnsNil {
    id result = [self.client jsonObjectFromDataIfPossible:[NSData data]];
    XCTAssertNil(result);
}

- (void)testJsonObjectFromData_invalidJSON_returnsNil {
    NSData *data = [@"not json" dataUsingEncoding:NSUTF8StringEncoding];
    id result = [self.client jsonObjectFromDataIfPossible:data];
    XCTAssertNil(result);
}

#pragma mark - normalizedAttendantsPayloadFromResponse:

- (void)testNormalizedPayload_directDict_returnsDict {
    NSDictionary *input = @{@"type": @"state", @"ids": @[@"@peer.ed25519"]};
    id result = [self.client normalizedAttendantsPayloadFromResponse:input];
    XCTAssertEqualObjects(result, input);
}

- (void)testNormalizedPayload_wrappedInValue_unwraps {
    NSDictionary *inner = @{@"type": @"state", @"ids": @[@"@peer.ed25519"]};
    NSDictionary *wrapped = @{@"value": inner};
    id result = [self.client normalizedAttendantsPayloadFromResponse:wrapped];
    XCTAssertEqualObjects(result, inner);
}

- (void)testNormalizedPayload_jsonData_parsesAndReturns {
    NSData *jsonData = [@"{\"type\":\"state\",\"ids\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    id result = [self.client normalizedAttendantsPayloadFromResponse:jsonData];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects([result objectForKey:@"type"], @"state");
}

- (void)testNormalizedPayload_eventFieldPromotedToType {
    NSDictionary *input = @{@"event": @"joined", @"id": @"@peer.ed25519"};
    id result = [self.client normalizedAttendantsPayloadFromResponse:input];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects([result objectForKey:@"type"], @"joined");
}

#pragma mark - manifestDictionary:supportsRPCPath:

- (void)testManifestDict_supportsPresentPath_returnsYES {
    NSDictionary *manifest = @{@"tunnel": @{@"endpoints": @"source"}};
    BOOL result = [self.client manifestDictionary:manifest supportsRPCPath:@[@"tunnel", @"endpoints"]];
    XCTAssertTrue(result);
}

- (void)testManifestDict_missingPath_returnsNO {
    NSDictionary *manifest = @{@"tunnel": @{@"ping": @"async"}};
    BOOL result = [self.client manifestDictionary:manifest supportsRPCPath:@[@"tunnel", @"endpoints"]];
    XCTAssertFalse(result);
}

- (void)testManifestDict_dottedPath_returnsYES {
    NSDictionary *manifest = @{@"tunnel.endpoints": @"source"};
    BOOL result = [self.client manifestDictionary:manifest supportsRPCPath:@[@"tunnel", @"endpoints"]];
    XCTAssertTrue(result);
}

- (void)testManifestDict_emptyManifest_returnsNO {
    BOOL result = [self.client manifestDictionary:@{} supportsRPCPath:@[@"tunnel", @"endpoints"]];
    XCTAssertFalse(result);
}

#pragma mark - manifestSupportsRPCPath:

- (void)testManifestSupports_noManifest_returnsNO {
    // serverManifest is nil by default
    BOOL result = [self.client manifestSupportsRPCPath:@[@"tunnel", @"endpoints"]];
    XCTAssertFalse(result);
}

#pragma mark - isRoomAttendantsMethod: / isTunnelEndpointsMethod:

- (void)testIsRoomAttendantsMethod_correct_returnsYES {
    NSArray *method = @[@"room", @"attendants"];
    XCTAssertTrue([self.client isRoomAttendantsMethod:method]);
}

- (void)testIsRoomAttendantsMethod_wrong_returnsNO {
    NSArray *method = @[@"tunnel", @"endpoints"];
    XCTAssertFalse([self.client isRoomAttendantsMethod:method]);
}

- (void)testIsTunnelEndpointsMethod_correct_returnsYES {
    NSArray *method = @[@"tunnel", @"endpoints"];
    XCTAssertTrue([self.client isTunnelEndpointsMethod:method]);
}

- (void)testIsTunnelEndpointsMethod_wrong_returnsNO {
    NSArray *method = @[@"room", @"attendants"];
    XCTAssertFalse([self.client isTunnelEndpointsMethod:method]);
}

#pragma mark - preferredEndpointDiscoveryMethod

- (void)testPreferredDiscovery_noFeatures_returnsTunnelEndpoints {
    NSArray *result = [self.client preferredEndpointDiscoveryMethod];
    NSArray *expected = @[@"tunnel", @"endpoints"];
    XCTAssertEqualObjects(result, expected);
}

#pragma mark - tracePeerID

- (void)testTracePeerID_validServerKey_returnsFormattedID {
    NSString *traceID = [self.client tracePeerID];
    // Should start with @ since serverPubKey is 32 bytes
    XCTAssertTrue([traceID hasPrefix:@"@"]);
    XCTAssertTrue([traceID hasSuffix:@".ed25519"]);
}

#pragma mark - sendRPCRequest when not connected

- (void)testSendRPCRequest_notConnected_callsCompletionWithError {
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [self.client sendRPCRequest:@[@"tunnel", @"ping"] args:@[] type:@"async" completion:^(id response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testSendRPCRequest_notConnected_returnsMinusOne {
    int32_t result = [self.client sendRPCRequest:@[@"tunnel", @"ping"] args:@[] type:@"async" completion:nil];
    XCTAssertEqual(result, -1);
}

@end
