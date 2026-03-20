#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBTransport.h>
#import "../Sources/SSBTunnelConnection.h"
#import "../Sources/SSBMuxRPCSession.h"
#import "../Sources/tweetnacl.h"
#import "../App/Logic/SRNotificationNames.h"

typedef void (^SSBRoomClientTraceSink)(NSDictionary<NSString *, id> *event);

static void SSBRoomGenerateKeypair(NSData **outPublic, NSData **outSecret) {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_ed25519_keypair(pk, sk);

    if (outPublic) {
        *outPublic = [NSData dataWithBytes:pk length:sizeof(pk)];
    }
    if (outSecret) {
        *outSecret = [NSData dataWithBytes:sk length:sizeof(sk)];
    }
}

@interface SSBRoomClient (TestAccess)
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSData *)serverPubKey
               localIdentity:(nullable NSData *)localIdentitySecret
                   feedStore:(nullable SSBFeedStore *)feedStore
                   blobStore:(nullable SSBBlobStore *)blobStore
            transportBackend:(nullable id<SSBTransportBackend>)transportBackend
                   traceSink:(nullable SSBRoomClientTraceSink)traceSink;
- (void)handleAttendantsResponse:(id)response;
- (NSArray<NSString *> *)preferredEndpointDiscoveryMethod;
- (BOOL)shouldResubscribeForPreferredEndpointDiscoveryMethod;
- (void)performInitialSetup;
- (void)probeRoomAttendantsSnapshotWithReason:(NSString *)reason;
- (void)syncLocalFeed;
- (BOOL)shouldRedeemInviteAfterSetup;
- (BOOL)shouldAttemptRoomHistorySync;
- (nullable NSDate *)nextTunnelRetryDateForPeer:(NSString *)peerID;
- (void)setNextTunnelRetryDate:(nullable NSDate *)retryDate forPeer:(NSString *)peerID;
- (void)performClientQueueSync:(dispatch_block_t)block;
- (void)handleRemoteClockUpdate:(NSDictionary *)update fromPeer:(NSString *)peerID;
- (void)reportSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author;
- (void)reportTunnelReadyForPeer:(NSString *)peerID;
- (NSArray<NSString *> *)filteredAttendantPeerIDs:(NSArray<NSString *> *)peerIDs;
- (NSString *)localPublicID;
@property (nonatomic, strong) SSBMuxRPCSession *rpcSession;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SSBTunnelConnection *> *activeTunnels;
@end

@interface MockTransportConnection : NSObject <SSBTransportConnection>
@property (nonatomic, assign) SSBTransportConnectionState state;
@property (nonatomic, strong, nullable) SSBTransportEndpoint *endpoint;
@property (nonatomic, assign) NSUInteger sendCount;
@property (nonatomic, strong) NSMutableArray<NSData *> *sentPayloads;
@property (nonatomic, copy, nullable) SSBTransportConnectionStateHandler stateHandler;
@end

@implementation MockTransportConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = SSBTransportConnectionStatePreparing;
        _sentPayloads = [NSMutableArray array];
    }
    return self;
}

- (void)setStateChangedHandler:(SSBTransportConnectionStateHandler)handler {
    self.stateHandler = handler;
}

- (void)start {
}

- (void)cancel {
    self.state = SSBTransportConnectionStateCancelled;
}

- (void)receiveMessageWithCompletion:(SSBTransportConnectionReceiveHandler)completion {
    if (completion) {
        completion(nil, nil, YES, nil);
    }
}

- (void)receiveMinimumLength:(uint32_t)minimumLength
               maximumLength:(uint32_t)maximumLength
                  completion:(SSBTransportConnectionReceiveHandler)completion {
    if (completion) {
        completion(nil, nil, YES, nil);
    }
}

- (void)sendData:(NSData *)data
      isComplete:(BOOL)isComplete
      completion:(SSBTransportConnectionSendHandler)completion {
    self.sendCount += 1;
    [self.sentPayloads addObject:data ?: [NSData data]];
    if (completion) {
        completion(nil);
    }
}

@end

@interface SSBTunnelConnection (TestAccess)
@property (nonatomic, strong) id<SSBTransportConnection> serverConnection;
@property (nonatomic, strong) NSMutableArray<NSData *> *incomingBuffer;
@property (nonatomic, strong) dispatch_queue_t tunnelQueue;
@end

@interface RetryAwareRoomClient : SSBRoomClient
@property (nonatomic, assign) NSUInteger connectToPeerCallCount;
@end

@implementation RetryAwareRoomClient

- (void)connectToPeer:(NSString *)targetPeerId {
    self.connectToPeerCallCount += 1;
}

@end

@interface SSBRoomProtocolBugfixTests : XCTestCase
@property (nonatomic, strong) SSBRoomClient *client;
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, strong) SSBBlobStore *blobStore;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *traceEvents;
@end

@implementation SSBRoomProtocolBugfixTests

- (void)setUp {
    [super setUp];

    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    self.feedStore = [[SSBFeedStore alloc] initWithPath:[base stringByAppendingPathComponent:@"feeds.sqlite3"]];
    self.blobStore = [[SSBBlobStore alloc] initWithPath:[base stringByAppendingPathComponent:@"blobs"]];
    self.traceEvents = [NSMutableArray array];

    NSData *serverPubKey = [NSMutableData dataWithLength:32];
    NSData *localIdentity = [NSMutableData dataWithLength:64];

    __weak typeof(self) weakSelf = self;
    self.client = [[SSBRoomClient alloc] initWithHost:@"test.room"
                                                 port:8008
                                         serverPubKey:serverPubKey
                                        localIdentity:localIdentity
                                            feedStore:self.feedStore
                                            blobStore:self.blobStore
                                     transportBackend:[SSBTransport defaultBackend]
                                            traceSink:^(NSDictionary<NSString *,id> *event) {
        [weakSelf.traceEvents addObject:event];
    }];
}

- (void)tearDown {
    [self.client disconnect];
    [self drainMainQueue];
    [self.feedStore wipeDatabase];
    [self.blobStore wipeBlobs];
    self.client = nil;
    self.feedStore = nil;
    self.blobStore = nil;
    self.traceEvents = nil;
    [super tearDown];
}

- (void)testInjectedStoresAndTraceSinkAreUsedForRoomDiagnostics {
    [self.client handleAttendantsResponse:@[@{ @"id": @"@peer.ed25519" }]];
    [self flushClientQueue:self.client];

    XCTAssertEqual(self.client.feedStore, self.feedStore);
    XCTAssertTrue(self.traceEvents.count > 0);
    NSDictionary<NSString *, id> *lastEvent = self.traceEvents.lastObject;
    XCTAssertEqualObjects(lastEvent[@"component"], @"room.client");
    XCTAssertNotNil(lastEvent[@"connectionID"]);
}

- (void)testOutgoingTraceIncludesRPCMetadata {
    MockTransportConnection *connection = [[MockTransportConnection alloc] init];
    [self.client setValue:connection forKey:@"connection"];
    [self.client setValue:@YES forKey:@"isConnected"];

    [self.client fetchRoomMetadataWithCompletion:nil];
    [self flushClientQueue:self.client];

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary<NSString *, id> *event, __unused NSDictionary<NSString *,id> *bindings) {
        return [event[@"framerState"] isEqual:@"muxrpc.send"] &&
               [event[@"rpcName"] isEqual:@"room.metadata"];
    }];
    NSDictionary<NSString *, id> *event = [[self.traceEvents filteredArrayUsingPredicate:predicate] lastObject];

    XCTAssertNotNil(event);
    XCTAssertEqualObjects(event[@"rpcType"], @"async");
    XCTAssertEqualObjects(event[@"rpcPath"], (@[@"room", @"metadata"]));
    XCTAssertEqualObjects(event[@"rpcArgsCount"], @0);
}

- (void)testHandleAttendantsResponseSupportsLegacyArraysAndStructuredEvents {
    [self.client handleAttendantsResponse:@[
        @"@peer1.ed25519",
        @"@peer2.ed25519",
        @"@peer1.ed25519"
    ]];

    NSArray<NSString *> *legacyAttendants = [self.client valueForKey:@"attendantsList"];
    XCTAssertEqualObjects(legacyAttendants, (@[@"@peer1.ed25519", @"@peer2.ed25519"]));

    [self.client handleAttendantsResponse:@{
        @"type": @"joined",
        @"id": @"@peer3.ed25519"
    }];
    [self.client handleAttendantsResponse:@{
        @"type": @"left",
        @"id": @"@peer1.ed25519"
    }];

    NSArray<NSString *> *currentAttendants = [self.client valueForKey:@"attendantsList"];
    XCTAssertEqualObjects(currentAttendants, (@[@"@peer2.ed25519", @"@peer3.ed25519"]));
}

- (void)testPreferredEndpointDiscoveryMethodUsesRoomAttendantsFromManifest {
    [self.client setValue:nil forKey:@"roomFeatures"];
    [self.client setValue:@{
        @"tunnel": @{@"endpoints": @"source"},
        @"room": @{@"attendants": @"source"}
    } forKey:@"serverManifest"];

    XCTAssertEqualObjects([self.client preferredEndpointDiscoveryMethod], (@[@"room", @"attendants"]));
}

- (void)testShouldResubscribeWhenManifestUnlocksRoomAttendantsAfterFallback {
    [self.client setValue:@[@"tunnel", @"endpoints"] forKey:@"endpointDiscoveryMethodInUse"];
    [self.client setValue:nil forKey:@"roomFeatures"];
    [self.client setValue:@{
        @"tunnel": @{@"endpoints": @"source"},
        @"room": @{@"attendants": @"source"}
    } forKey:@"serverManifest"];

    XCTAssertTrue([self.client shouldResubscribeForPreferredEndpointDiscoveryMethod]);
}

- (void)testPerformInitialSetupRequestsManifestWhoamiAndMetadata {
    NSMutableArray<NSDictionary<NSString *, id> *> *requests = [NSMutableArray array];
    XCTestExpectation *allRequestsSent = [self expectationWithDescription:@"initial setup requests sent"];
    allRequestsSent.expectedFulfillmentCount = 3;

    self.client.rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        if ([body isKindOfClass:[NSDictionary class]]) {
            [requests addObject:@{
                @"name": body[@"name"] ?: @[],
                @"type": body[@"type"] ?: @"",
                @"requestNumber": @(message.requestNumber)
            }];
            [allRequestsSent fulfill];
        }
    };

    [self.client setValue:@YES forKey:@"isConnected"];
    [self.client performInitialSetup];
    [self waitForExpectations:@[allRequestsSent] timeout:2.0];

    NSArray *names = [requests valueForKey:@"name"];
    NSArray<NSString *> *roomMetadataPath = @[@"room", @"metadata"];
    XCTAssertTrue([names containsObject:@[@"manifest"]]);
    XCTAssertTrue([names containsObject:@[@"whoami"]]);
    XCTAssertTrue([names containsObject:roomMetadataPath]);
}

- (void)testPerformInitialSetupFollowsManifestDrivenDiscoveryAndHistorySync {
    XCTestExpectation *announceSent = [self expectationWithDescription:@"announce sent"];
    XCTestExpectation *attendantsSent = [self expectationWithDescription:@"attendants sent"];
    XCTestExpectation *historySent = [self expectationWithDescription:@"history sent"];

    NSMutableDictionary<NSArray<NSString *> *, NSNumber *> *requestIDsByName = [NSMutableDictionary dictionary];

    __block BOOL announceFulfilled = NO;
    __block BOOL attendantsFulfilled = NO;
    __block BOOL historyFulfilled = NO;
    self.client.rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        if (![body isKindOfClass:[NSDictionary class]]) {
            return;
        }

        NSArray<NSString *> *name = body[@"name"];
        requestIDsByName[name] = @(message.requestNumber);

        if ([name isEqual:@[@"tunnel", @"announce"]] && !announceFulfilled) {
            announceFulfilled = YES;
            [announceSent fulfill];
        } else if ([name isEqual:@[@"room", @"attendants"]] && !attendantsFulfilled) {
            attendantsFulfilled = YES;
            XCTAssertEqualObjects(body[@"type"], @"source");
            [attendantsSent fulfill];
        } else if ([name isEqual:@[@"createHistoryStream"]] && !historyFulfilled) {
            historyFulfilled = YES;
            [historySent fulfill];
        }
    };

    [self.client setValue:@YES forKey:@"isConnected"];
    [self.client performInitialSetup];

    [self injectResponse:@{
        @"room": @{@"attendants": @"source"},
        @"createHistoryStream": @"source"
    } forRequestNumber:requestIDsByName[@[@"manifest"]].intValue flags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)];

    [self injectResponse:@{
        @"features": @[@"room2", @"tunnel"],
        @"membership": @YES
    } forRequestNumber:requestIDsByName[@[@"room", @"metadata"]].intValue flags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)];
    [self injectResponse:@YES
         forRequestNumber:requestIDsByName[@[@"tunnel", @"announce"]].intValue
                    flags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)];

    [self waitForExpectations:@[announceSent, attendantsSent, historySent] timeout:2.0];
    XCTAssertEqualObjects([self.client valueForKey:@"roomFeatures"], (@[@"room2", @"tunnel"]));
    XCTAssertTrue([self.client shouldAttemptRoomHistorySync]);
}

- (void)testProbeRoomAttendantsSnapshotUsesSourceRequest {
    XCTestExpectation *requestSent = [self expectationWithDescription:@"room.attendants request sent"];

    __block NSArray *capturedName = nil;
    __block NSString *capturedType = nil;
    __block BOOL fulfilled = NO;
    self.client.rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        capturedName = body[@"name"];
        capturedType = body[@"type"];
        if (!fulfilled) {
            fulfilled = YES;
            [requestSent fulfill];
        }
    };

    [self.client setValue:@YES forKey:@"isConnected"];
    [self.client probeRoomAttendantsSnapshotWithReason:@"test"];
    [self waitForExpectations:@[requestSent] timeout:2.0];

    XCTAssertEqualObjects(capturedName, (@[@"room", @"attendants"]));
    XCTAssertEqualObjects(capturedType, @"source");
}

- (void)testSyncLocalFeedSkipsUnsupportedHistoryRequest {
    __block BOOL sentCreateHistoryStream = NO;
    self.client.rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        if ([body[@"name"] isEqual:@[@"createHistoryStream"]]) {
            sentCreateHistoryStream = YES;
        }
    };

    [self.client setValue:@{} forKey:@"serverManifest"];
    [self.client setValue:@YES forKey:@"isConnected"];
    [self.client syncLocalFeed];
    [self flushClientQueue:self.client];
    [self drainMainQueue];

    XCTAssertFalse(sentCreateHistoryStream);
    XCTAssertFalse([[self.client valueForKey:@"isSyncingLocalFeed"] boolValue]);
}

- (void)testRemoteClockUpdatesPeerSpecificSyncState {
    NSString *peerID = [self feedIDForByte:0x31];
    NSString *author = [self feedIDForByte:0x32];
    NSMutableDictionary *peerState = [@{
        @"requestID": @1,
        @"clock": [NSMutableDictionary dictionary]
    } mutableCopy];
    [self.client setValue:[@{ peerID: peerState } mutableCopy] forKey:@"peerEBTState"];

    [self.client handleRemoteClockUpdate:@{ author: @5 } fromPeer:peerID];
    [self flushClientQueue:self.client];

    XCTAssertEqualObjects(self.client.peerSyncStates[author], @"Receiving: 0/5");
    XCTAssertEqualWithAccuracy(self.client.peerSyncProgress[author].floatValue, 0.0f, 0.001f);
}

- (void)testTunnelReadyStatusOverridesHandshakingWithoutGlobalNotification {
    NSString *peerID = [self feedIDForByte:0x38];

    __block NSInteger notificationCount = 0;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:SRRoomSyncStatusChangedNotification
                                                                 object:nil
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(__unused NSNotification *note) {
        notificationCount += 1;
    }];

    [self.client reportSyncStatus:@"Handshaking..." progress:0.1f author:peerID];
    [self flushClientQueue:self.client];
    XCTAssertEqualObjects(self.client.peerSyncStates[peerID], @"Handshaking...");

    [self.client reportTunnelReadyForPeer:peerID];
    [self flushClientQueue:self.client];
    [self drainMainQueue];
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    XCTAssertEqualObjects(self.client.peerSyncStates[peerID], @"Connected");
    XCTAssertEqualWithAccuracy(self.client.peerSyncProgress[peerID].floatValue, 0.2f, 0.001f);
    XCTAssertEqual(notificationCount, 0);
}

- (void)testTunnelConnectionBuffersIncomingDataUntilAcceptedSocketIsReady {
    NSData *peerPublicKey = [NSMutableData dataWithLength:32];
    NSData *localIdentity = [NSMutableData dataWithLength:64];
    SSBTunnelConnection *tunnel = [[SSBTunnelConnection alloc] initWithPeerId:[self feedIDForByte:0x39]
                                                                peerPublicKey:peerPublicKey
                                                                localIdentity:localIdentity
                                                                  roomSession:[[SSBMuxRPCSession alloc] init]
                                                                  tunnelReqID:7
                                                                     isServer:NO];

    MockTransportConnection *connection = [[MockTransportConnection alloc] init];
    tunnel.serverConnection = connection;

    NSData *payload = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    [tunnel receiveTunnelData:payload];
    dispatch_sync(tunnel.tunnelQueue, ^{});

    XCTAssertEqual(connection.sendCount, 0u);
    XCTAssertEqual(tunnel.incomingBuffer.count, 1u);

    connection.state = SSBTransportConnectionStateReady;
    [tunnel receiveTunnelData:tunnel.incomingBuffer.firstObject];
    [tunnel.incomingBuffer removeAllObjects];
    dispatch_sync(tunnel.tunnelQueue, ^{});

    XCTAssertEqual(connection.sendCount, 1u);
    XCTAssertEqualObjects(connection.sentPayloads.firstObject, payload);
}

- (void)testReplicateFromPeerSkipsImmediateRetryAfterTerminalFailure {
    RetryAwareRoomClient *client = [[RetryAwareRoomClient alloc] initWithHost:@"test.room"
                                                                         port:8008
                                                                 serverPubKey:[NSMutableData dataWithLength:32]
                                                                localIdentity:[NSMutableData dataWithLength:64]
                                                                    feedStore:self.feedStore
                                                                    blobStore:self.blobStore
                                                             transportBackend:[SSBTransport defaultBackend]
                                                                    traceSink:nil];
    NSString *peerID = [self feedIDForByte:0x3A];

    [client reportSyncStatus:@"Stranger" progress:1.0f author:peerID];
    [self flushClientQueue:client];
    [client setNextTunnelRetryDate:[NSDate dateWithTimeIntervalSinceNow:60.0] forPeer:peerID];
    [self flushClientQueue:client];

    [client replicateFromPeer:peerID viaRoom:client.host];

    XCTAssertEqual(client.connectToPeerCallCount, 0u);
    XCTAssertEqualObjects(client.peerSyncStates[peerID], @"Stranger");
}

- (void)testTunnelConnectIncludesOriginPeerID {
    NSString *targetPeerID = [self feedIDForByte:0x36];
    NSString *expectedOrigin = [self.client localPublicID];
    XCTestExpectation *requestSent = [self expectationWithDescription:@"tunnel.connect request sent"];

    __block NSString *capturedOrigin = nil;
    __block NSString *capturedTarget = nil;
    self.client.rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        NSDictionary *body = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        if (![body[@"name"] isEqual:@[@"tunnel", @"connect"]]) {
            return;
        }

        NSDictionary *args = [body[@"args"] firstObject];
        capturedOrigin = args[@"origin"];
        capturedTarget = args[@"target"];
        [requestSent fulfill];
    };

    [self.client setValue:@YES forKey:@"isConnected"];
    [self.client connectToPeer:targetPeerID];
    [self waitForExpectations:@[requestSent] timeout:2.0];

    XCTAssertEqualObjects(capturedTarget, targetPeerID);
    XCTAssertEqualObjects(capturedOrigin, expectedOrigin);
}

- (void)testTunneledConnectionDeliversInnerMuxRPCRequestToPeerSession {
    NSData *peerPublicA = nil;
    NSData *peerSecretA = nil;
    NSData *peerPublicB = nil;
    NSData *peerSecretB = nil;
    SSBRoomGenerateKeypair(&peerPublicA, &peerSecretA);
    SSBRoomGenerateKeypair(&peerPublicB, &peerSecretB);

    SSBMuxRPCSession *roomSessionA = [[SSBMuxRPCSession alloc] init];
    SSBMuxRPCSession *roomSessionB = [[SSBMuxRPCSession alloc] init];

    __block SSBTunnelConnection *tunnelA = [[SSBTunnelConnection alloc] initWithPeerId:[self peerIDFromPublicKey:peerPublicB]
                                                                          peerPublicKey:peerPublicB
                                                                          localIdentity:peerSecretA
                                                                            roomSession:roomSessionA
                                                                            tunnelReqID:17
                                                                               isServer:NO];
    __block SSBTunnelConnection *tunnelB = [[SSBTunnelConnection alloc] initWithPeerId:[self peerIDFromPublicKey:peerPublicA]
                                                                          peerPublicKey:peerPublicA
                                                                          localIdentity:peerSecretB
                                                                            roomSession:roomSessionB
                                                                            tunnelReqID:17
                                                                               isServer:YES];

    roomSessionA.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        if (message.body.length > 0) {
            [tunnelB receiveTunnelData:message.body];
        }
    };
    roomSessionB.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        if (message.body.length > 0) {
            [tunnelA receiveTunnelData:message.body];
        }
    };

    XCTestExpectation *tunnelAReady = [self expectationWithDescription:@"tunnel A ready"];
    XCTestExpectation *tunnelBReady = [self expectationWithDescription:@"tunnel B ready"];
    tunnelA.onConnectionStateReady = ^{ [tunnelAReady fulfill]; };
    tunnelB.onConnectionStateReady = ^{ [tunnelBReady fulfill]; };

    [tunnelA start];
    [tunnelB start];

    [self waitForExpectations:@[tunnelAReady, tunnelBReady] timeout:10.0];

    XCTestExpectation *requestDelivered = [self expectationWithDescription:@"inner muxrpc request delivered"];
    tunnelB.rpcSession.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
        NSDictionary *dict = payload;
        XCTAssertEqualObjects(dict[@"name"], (@[@"echo"]));
        XCTAssertEqualObjects([dict[@"args"] firstObject][@"value"], @"hello");
        XCTAssertEqual(flags & SSBMuxRPCFlagStream, 0);
        XCTAssertGreaterThan(requestID, 0);
        [requestDelivered fulfill];
    };

    [tunnelA.rpcSession sendRequest:@[@"echo"]
                                args:@[@{ @"value": @"hello" }]
                                type:@"async"
                          completion:nil];

    [self waitForExpectations:@[requestDelivered] timeout:5.0];
    [tunnelA stop];
    [tunnelB stop];
}

- (void)injectResponse:(id)response
      forRequestNumber:(int32_t)requestNumber
                 flags:(SSBMuxRPCFlags)flags {
    NSData *body = nil;
    if ([response isKindOfClass:[NSString class]]) {
        body = [(NSString *)response dataUsingEncoding:NSUTF8StringEncoding];
    } else if (response) {
        body = [NSJSONSerialization dataWithJSONObject:response
                                               options:NSJSONWritingFragmentsAllowed
                                                 error:nil];
    } else {
        body = [NSData data];
    }
    SSBMuxRPCMessage *message = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:-requestNumber body:body];
    [self.client.rpcSession handleIncomingMessage:message];
}

- (NSString *)peerIDFromPublicKey:(NSData *)publicKey {
    return [NSString stringWithFormat:@"@%@.ed25519", [publicKey base64EncodedStringWithOptions:0]];
}

- (NSString *)feedIDForByte:(uint8_t)value {
    NSMutableData *data = [NSMutableData dataWithLength:32];
    memset(data.mutableBytes, value, data.length);
    return [self peerIDFromPublicKey:data];
}

- (void)flushClientQueue:(SSBRoomClient *)client {
    dispatch_sync(client.clientQueue, ^{});
    [self drainMainQueue];
}

- (void)drainMainQueue {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

@end
