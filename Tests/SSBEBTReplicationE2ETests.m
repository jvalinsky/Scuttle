#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBMessageCodec.h>
#import <SSBNetwork/SSBTransport.h>
#import "../Sources/SSBTunnelConnection.h"
#import "../Sources/SSBMuxRPCSession.h"
#import "../Sources/tweetnacl.h"

#pragma mark - Test Keypair Helper

static void EBTTestGenerateKeypair(NSData **outPublic, NSData **outSecret) {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_ed25519_keypair(pk, sk);

    if (outPublic) *outPublic = [NSData dataWithBytes:pk length:sizeof(pk)];
    if (outSecret) *outSecret = [NSData dataWithBytes:sk length:sizeof(sk)];
}

static NSString *EBTTestPeerIDFromPublicKey(NSData *publicKey) {
    return [NSString stringWithFormat:@"@%@.ed25519", [publicKey base64EncodedStringWithOptions:0]];
}

#pragma mark - Test Access Categories

@interface SSBRoomClient (EBTTestAccess)
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSData *)serverPubKey
               localIdentity:(nullable NSData *)localIdentitySecret
                   feedStore:(nullable SSBFeedStore *)feedStore
                   blobStore:(nullable SSBBlobStore *)blobStore
            transportBackend:(nullable id<SSBTransportBackend>)transportBackend
                   traceSink:(nullable void (^)(NSDictionary<NSString *, id> *event))traceSink;
- (void)handleRemoteClockUpdate:(NSDictionary *)update fromPeer:(NSString *)peerID;
- (void)handleBilateralEBT:(NSDictionary *)req requestID:(int32_t)reqID session:(SSBMuxRPCSession *)session;
- (void)startEBTReplicationWithSession:(SSBMuxRPCSession *)session;
- (void)handleEBTMessage:(id)message requestID:(int32_t)reqID flags:(uint8_t)flags session:(SSBMuxRPCSession *)session;
- (void)performClientQueueSync:(dispatch_block_t)block;
- (NSString *)localPublicID;
@property (nonatomic, strong) SSBMuxRPCSession *rpcSession;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, SSBTunnelConnection *> *activeTunnels;
@property (nonatomic, strong) NSMapTable<SSBMuxRPCSession *, NSNumber *> *ebtRequestIDsBySession;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *peerEBTState;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *remoteClock;
@end

@interface SSBTunnelConnection (EBTTestAccess)
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingIncomingRequests;
@end

#pragma mark - Test Suite

@interface SSBEBTReplicationE2ETests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation SSBEBTReplicationE2ETests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (SSBRoomClient *)createClientWithIdentity:(NSData *)secret feedStore:(SSBFeedStore *)store {
    NSData *serverPubKey = [NSMutableData dataWithLength:32];
    return [[SSBRoomClient alloc] initWithHost:@"test.room"
                                          port:8008
                                  serverPubKey:serverPubKey
                                 localIdentity:secret
                                     feedStore:store
                                     blobStore:nil
                              transportBackend:[SSBTransport defaultBackend]
                                     traceSink:nil];
}

- (SSBFeedStore *)createFeedStore:(NSString *)name {
    NSString *dbPath = [self.tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite3", name]];
    return [[SSBFeedStore alloc] initWithPath:dbPath];
}

- (SSBMessage *)createTestMessage:(NSDictionary *)content
                           author:(NSString *)author
                         sequence:(NSInteger)seq
                      previousKey:(NSString *)prevKey
                        secretKey:(NSData *)secretKey {
    NSDictionary *signedValue = [SSBMessageCodec createSignedMessageWithContent:content
                                                                         author:author
                                                                       sequence:seq
                                                                    previousKey:prevKey
                                                                      secretKey:secretKey];
    if (!signedValue) return nil;

    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = [SSBMessageCodec computeMessageKey:signedValue];
    msg.author = author;
    msg.sequence = seq;
    msg.previousKey = prevKey;
    msg.claimedTimestamp = [signedValue[@"timestamp"] longLongValue];
    msg.content = content;
    msg.contentType = content[@"type"];
    msg.valueJSON = [SSBMessageCodec encodeLegacyValue:signedValue includeSignature:YES];
    return msg;
}

- (NSArray<SSBMessage *> *)populateFeedStore:(SSBFeedStore *)store
                                   withCount:(NSInteger)count
                                      author:(NSString *)author
                                   secretKey:(NSData *)secretKey {
    NSMutableArray *messages = [NSMutableArray array];
    NSString *prevKey = nil;

    for (NSInteger i = 1; i <= count; i++) {
        NSDictionary *content = @{@"type": @"post", @"text": [NSString stringWithFormat:@"Message %ld", (long)i]};
        SSBMessage *msg = [self createTestMessage:content author:author sequence:i previousKey:prevKey secretKey:secretKey];
        XCTAssertNotNil(msg, @"Failed to create test message seq=%ld", (long)i);

        NSError *error = nil;
        BOOL ok = [store appendMessage:msg error:&error];
        XCTAssertTrue(ok, @"Failed to append message seq=%ld: %@", (long)i, error);

        prevKey = msg.key;
        [messages addObject:msg];
    }

    return messages;
}

- (void)flushClientQueue:(SSBRoomClient *)client {
    dispatch_sync(client.clientQueue, ^{});
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

#pragma mark - Bug 1: Bilateral EBT response request number sign

- (void)testBilateralEBTResponseUsesNegativeRequestID {
    NSData *pubA = nil, *secA = nil;
    EBTTestGenerateKeypair(&pubA, &secA);

    SSBFeedStore *store = [self createFeedStore:@"bilateral"];
    SSBRoomClient *client = [self createClientWithIdentity:secA feedStore:store];

    // Create a mock session to capture outgoing messages
    SSBMuxRPCSession *mockSession = [[SSBMuxRPCSession alloc] init];
    __block NSMutableArray<SSBMuxRPCMessage *> *sentMessages = [NSMutableArray array];
    mockSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        [sentMessages addObject:message];
    };

    // Simulate peer sending us an ebt.replicate request with positive reqID=42
    NSDictionary *bilateralReq = @{
        @"name": @[@"ebt", @"replicate"],
        @"args": @[@{@"version": @3, @"format": @"classic"}],
        @"type": @"duplex"
    };

    [client handleBilateralEBT:bilateralReq requestID:42 session:mockSession];
    [self flushClientQueue:client];

    // The response clock should be sent with NEGATIVE request number (-42)
    XCTAssertGreaterThan(sentMessages.count, 0, @"Should have sent at least one message (our clock)");

    SSBMuxRPCMessage *clockMsg = sentMessages.firstObject;
    XCTAssertEqual(clockMsg.requestNumber, -42,
                   @"Bilateral EBT response must use negative request number. Got %d", clockMsg.requestNumber);

    // Check peerEBTState stores the negated ID
    __block NSNumber *storedReqID = nil;
    [client performClientQueueSync:^{
        storedReqID = client.peerEBTState[@"test.room"][@"requestID"];
    }];
    XCTAssertEqualObjects(storedReqID, @(-42), @"Stored bilateral request ID should be negated");

    [client disconnect];
    [store wipeDatabase];
}

#pragma mark - Bug 2: Clock values preserve negative semantics

- (void)testClockValuesPreserveNegativeSemantics {
    NSData *pubA = nil, *secA = nil;
    EBTTestGenerateKeypair(&pubA, &secA);

    SSBFeedStore *store = [self createFeedStore:@"clock-neg"];
    SSBRoomClient *client = [self createClientWithIdentity:secA feedStore:store];

    // EBT notes are bit-shifted: note = (seq << 1) | receive_flag
    // receive_flag: 0 = want to receive, 1 = do NOT want to receive
    // Special value -1 means "don't replicate this feed at all"
    NSDictionary *clockUpdate = @{
        @"@feed1.ed25519": @((5 << 1) | 0),  // seq=5, want to receive -> note=10
        @"@feed2.ed25519": @(-1),              // Don't replicate this feed
        @"@feed3.ed25519": @((0 << 1) | 0),  // seq=0, want to receive -> note=0
        @"@feed4.ed25519": @((7 << 1) | 1),  // seq=7, do NOT want to receive -> note=15
    };

    [client handleRemoteClockUpdate:clockUpdate fromPeer:@"@peerX.ed25519"];
    [self flushClientQueue:client];

    // Check that bit-shifted notes are decoded to actual sequence numbers
    __block NSDictionary *remoteClock = nil;
    [client performClientQueueSync:^{
        remoteClock = [client.remoteClock copy];
    }];

    XCTAssertEqualObjects(remoteClock[@"@feed1.ed25519"], @(5), @"Decoded seq from note 10 -> seq 5");
    XCTAssertEqualObjects(remoteClock[@"@feed2.ed25519"], @(-1), @"-1 (don't replicate) preserved");
    XCTAssertEqualObjects(remoteClock[@"@feed3.ed25519"], @(0), @"Decoded seq from note 0 -> seq 0");
    XCTAssertEqualObjects(remoteClock[@"@feed4.ed25519"], @(7), @"Decoded seq from note 15 -> seq 7");

    [client disconnect];
    [store wipeDatabase];
}

#pragma mark - Bug 3: Outbound message sending after clock exchange

- (void)testOutboundMessageSendingAfterClockExchange {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    EBTTestGenerateKeypair(&pubA, &secA);
    EBTTestGenerateKeypair(&pubB, &secB);

    NSString *authorA = EBTTestPeerIDFromPublicKey(pubA);

    SSBFeedStore *storeA = [self createFeedStore:@"outbound-A"];
    SSBRoomClient *clientA = [self createClientWithIdentity:secA feedStore:storeA];

    // Populate client A's feed store with 10 messages
    [self populateFeedStore:storeA withCount:10 author:authorA secretKey:secA];

    // Set up a mock MuxRPC session to capture outgoing messages
    SSBMuxRPCSession *mockSession = [[SSBMuxRPCSession alloc] init];
    __block NSMutableArray<SSBMuxRPCMessage *> *sentMessages = [NSMutableArray array];
    mockSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        [sentMessages addObject:message];
    };

    // Register an EBT request ID so the client knows which stream to send on
    [clientA.ebtRequestIDsBySession setObject:@(7) forKey:mockSession];

    // Simulate receiving a clock from peer B saying they have seq 5 for author A
    NSDictionary *peerBClock = @{
        authorA: @((5 << 1) | 0),  // Bit-shifted note: seq=5, receive=yes; peer needs 6-10
    };

    [clientA handleRemoteClockUpdate:peerBClock fromPeer:EBTTestPeerIDFromPublicKey(pubB)];
    [self flushClientQueue:clientA];

    // Should have sent 5 messages (seq 6-10) on request ID 7
    NSInteger messageSentCount = 0;
    for (SSBMuxRPCMessage *msg in sentMessages) {
        if (msg.requestNumber == 7 && (msg.flags & SSBMuxRPCFlagTypeJSON)) {
            // Parse to verify it's a message envelope
            id parsed = [NSJSONSerialization JSONObjectWithData:msg.body options:0 error:nil];
            if ([parsed isKindOfClass:[NSDictionary class]] && parsed[@"author"] && parsed[@"sequence"]) {
                messageSentCount++;
            }
        }
    }

    XCTAssertEqual(messageSentCount, 5, @"Should send 5 messages (seq 6-10) to peer B");

    [clientA disconnect];
    [storeA wipeDatabase];
}

#pragma mark - Bug 2+3: Negative clock prevents message sending

- (void)testNegativeClockPreventsMessageSending {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    EBTTestGenerateKeypair(&pubA, &secA);
    EBTTestGenerateKeypair(&pubB, &secB);

    NSString *authorA = EBTTestPeerIDFromPublicKey(pubA);

    SSBFeedStore *storeA = [self createFeedStore:@"neg-clock-A"];
    SSBRoomClient *clientA = [self createClientWithIdentity:secA feedStore:storeA];

    // Populate 10 messages
    [self populateFeedStore:storeA withCount:10 author:authorA secretKey:secA];

    SSBMuxRPCSession *mockSession = [[SSBMuxRPCSession alloc] init];
    __block NSMutableArray<SSBMuxRPCMessage *> *sentMessages = [NSMutableArray array];
    mockSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        [sentMessages addObject:message];
    };

    [clientA.ebtRequestIDsBySession setObject:@(9) forKey:mockSession];

    // Peer B sends -1 for our feed (don't want it)
    NSDictionary *peerBClock = @{
        authorA: @(-1),
    };

    [clientA handleRemoteClockUpdate:peerBClock fromPeer:EBTTestPeerIDFromPublicKey(pubB)];
    [self flushClientQueue:clientA];

    // Should NOT have sent any messages — peer doesn't want this feed
    NSInteger messageSentCount = 0;
    for (SSBMuxRPCMessage *msg in sentMessages) {
        if (msg.requestNumber == 9) {
            messageSentCount++;
        }
    }

    XCTAssertEqual(messageSentCount, 0, @"No messages should be sent when peer clock is -1");

    [clientA disconnect];
    [storeA wipeDatabase];
}

#pragma mark - Bug 4: Tunnel buffers early requests

- (void)testTunnelBuffersEarlyRequests {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    EBTTestGenerateKeypair(&pubA, &secA);
    EBTTestGenerateKeypair(&pubB, &secB);

    SSBMuxRPCSession *roomSession = [[SSBMuxRPCSession alloc] init];

    SSBTunnelConnection *tunnel = [[SSBTunnelConnection alloc] initWithPeerId:EBTTestPeerIDFromPublicKey(pubB)
                                                                peerPublicKey:pubB
                                                                localIdentity:secA
                                                                  roomSession:roomSession
                                                                  tunnelReqID:99
                                                                     isServer:NO];

    // Before starting or installing a real handler, simulate incoming requests
    // The default receiveRequestBlock should buffer them
    NSDictionary *testPayload = @{
        @"name": @[@"ebt", @"replicate"],
        @"args": @[@{@"version": @3, @"format": @"classic"}],
        @"type": @"duplex"
    };

    // Directly invoke the receiveRequestBlock to simulate an incoming request
    tunnel.rpcSession.receiveRequestBlock(testPayload, 55, SSBMuxRPCFlagStream | SSBMuxRPCFlagTypeJSON);

    // Verify the request was buffered
    XCTAssertEqual(tunnel.pendingIncomingRequests.count, 1, @"Request should be buffered");

    // Now install a real handler and replay
    __block id receivedPayload = nil;
    __block int32_t receivedReqID = 0;
    XCTestExpectation *replayed = [self expectationWithDescription:@"request replayed"];

    tunnel.rpcSession.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
        receivedPayload = payload;
        receivedReqID = requestID;
        [replayed fulfill];
    };

    [tunnel replayPendingIncomingRequests];

    [self waitForExpectations:@[replayed] timeout:2.0];

    XCTAssertEqualObjects(receivedPayload[@"name"], (@[@"ebt", @"replicate"]), @"Replayed payload should match");
    XCTAssertEqual(receivedReqID, 55, @"Replayed request ID should match");
    XCTAssertEqual(tunnel.pendingIncomingRequests.count, 0, @"Buffer should be cleared after replay");

    [tunnel stop];
}

#pragma mark - Full sync cycle between two peers

- (void)testFullSyncCycleBetweenTwoPeers {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    EBTTestGenerateKeypair(&pubA, &secA);
    EBTTestGenerateKeypair(&pubB, &secB);

    NSString *authorA = EBTTestPeerIDFromPublicKey(pubA);
    NSString *authorB = EBTTestPeerIDFromPublicKey(pubB);

    // Create feed stores with different data
    SSBFeedStore *storeA = [self createFeedStore:@"full-sync-A"];
    SSBFeedStore *storeB = [self createFeedStore:@"full-sync-B"];

    // Client A has 5 messages on its own feed
    [self populateFeedStore:storeA withCount:5 author:authorA secretKey:secA];
    // Client B has 3 messages on its own feed
    [self populateFeedStore:storeB withCount:3 author:authorB secretKey:secB];

    // Create two room clients
    SSBRoomClient *clientA = [self createClientWithIdentity:secA feedStore:storeA];
    SSBRoomClient *clientB = [self createClientWithIdentity:secB feedStore:storeB];

    // Wire two MuxRPC sessions together (simulating tunneled connection)
    SSBMuxRPCSession *sessionA = [[SSBMuxRPCSession alloc] init];
    SSBMuxRPCSession *sessionB = [[SSBMuxRPCSession alloc] init];

    sessionA.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        // Deliver to B
        [sessionB handleIncomingMessage:message];
    };
    sessionB.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        // Deliver to A
        [sessionA handleIncomingMessage:message];
    };

    // Register these sessions with respective clients' EBT tracking
    // Client A initiates EBT on sessionA
    clientA.rpcSession = sessionA;
    clientB.rpcSession = sessionB;

    // Set up session B to forward requests to client B's EBT handler
    sessionB.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
        [clientB handleEBTMessage:payload requestID:requestID flags:flags session:sessionB];
    };

    // Client A starts EBT replication
    [clientA startEBTReplicationWithSession:sessionA];
    [self flushClientQueue:clientA];
    [self flushClientQueue:clientB];

    // Allow time for bidirectional message exchange
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    [self flushClientQueue:clientA];
    [self flushClientQueue:clientB];

    // Verify: Client B should now have Client A's messages
    NSArray *bHasFromA = [storeB messagesForAuthor:authorA fromSequence:1 limit:100];
    XCTAssertEqual(bHasFromA.count, 5,
                   @"Client B should have all 5 of Client A's messages after sync (got %lu)",
                   (unsigned long)bHasFromA.count);

    // Verify: Client A should now have Client B's messages
    NSArray *aHasFromB = [storeA messagesForAuthor:authorB fromSequence:1 limit:100];
    XCTAssertEqual(aHasFromB.count, 3,
                   @"Client A should have all 3 of Client B's messages after sync (got %lu)",
                   (unsigned long)aHasFromB.count);

    [clientA disconnect];
    [clientB disconnect];
    [storeA wipeDatabase];
    [storeB wipeDatabase];
}

@end
