#import <XCTest/XCTest.h>
#import "../Sources/SSBTunnelConnection.h"
#import "../Sources/SSBMuxRPCSession.h"
#import "../Sources/tweetnacl.h"

// Private property access for testing
@interface SSBTunnelConnection (TestAccess)
@property (nonatomic, strong) NSMutableArray<NSData *> *incomingBuffer;
@property (nonatomic, strong) NSMutableArray *pendingMessages;
@property (nonatomic, strong) id listener;
@property (nonatomic, strong) id clientConnection;
@property (nonatomic, strong) id serverConnection;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isHandshakeComplete;
@end

@interface SSBTunnelConnectionTests : XCTestCase
@property (nonatomic, strong) SSBMuxRPCSession *roomSession;
@property (nonatomic, strong) SSBTunnelConnection *tunnel;
@end

@implementation SSBTunnelConnectionTests

- (void)setUp {
    [super setUp];
    self.roomSession = [[SSBMuxRPCSession alloc] init];
    
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    NSData *localSK = [NSData dataWithBytes:sk length:64];
    NSData *remotePK = [NSData dataWithBytes:pk length:32];
    
    self.tunnel = [[SSBTunnelConnection alloc] initWithPeerId:@"@testpeer"
                                                peerPublicKey:remotePK
                                                localIdentity:localSK
                                                  roomSession:self.roomSession
                                                  tunnelReqID:42
                                                     isServer:NO];
}

- (void)tearDown {
    [self.tunnel stop];
    [super tearDown];
}

- (void)testInitializationProperties {
    XCTAssertNotNil(self.tunnel);
    XCTAssertEqualObjects(self.tunnel.peerId, @"@testpeer");
    XCTAssertEqual(self.tunnel.tunnelReqID, 42);
    XCTAssertFalse(self.tunnel.isServer);
    XCTAssertFalse(self.tunnel.isConnected);
    XCTAssertNotNil(self.tunnel.rpcSession);
    XCTAssertNotNil(self.tunnel.incomingBuffer);
    XCTAssertNotNil(self.tunnel.pendingMessages);
}

- (void)testReceiveDataBuffersWhenServerConnectionNotReady {
    NSData *testData = [@"early data" dataUsingEncoding:NSUTF8StringEncoding];
    
    // Server connection is nil initially
    XCTAssertNil(self.tunnel.serverConnection);
    
    [self.tunnel receiveTunnelData:testData];
    
    // It dispatches to an internal queue, wait for it or block
    XCTestExpectation *expectation = [self expectationWithDescription:@"Queue flush"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.1];
        [expectation fulfill];
    });
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    XCTAssertEqual(self.tunnel.incomingBuffer.count, 1);
    XCTAssertEqualObjects(self.tunnel.incomingBuffer.firstObject, testData);
}

- (void)testSendMessageBuffersWhenHandshakeNotComplete {
    XCTAssertFalse(self.tunnel.isHandshakeComplete);
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:0 requestNumber:1 body:[NSData data]];
    self.tunnel.rpcSession.sendMessageBlock(msg);
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Queue flush"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.1];
        [expectation fulfill];
    });
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    XCTAssertEqual(self.tunnel.pendingMessages.count, 1);
    XCTAssertEqualObjects(self.tunnel.pendingMessages.firstObject, msg);
}

- (void)testStartAndStopTransitions {
    [self.tunnel start];

    XCTAssertNotNil(self.tunnel.listener);

    [self.tunnel stop];

    XCTAssertFalse(self.tunnel.isConnected);
    XCTAssertNil(self.tunnel.clientConnection);
    XCTAssertNil(self.tunnel.serverConnection);
    XCTAssertNil(self.tunnel.listener);
}

- (void)testServerRoleInitialization {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    NSData *localSK = [NSData dataWithBytes:sk length:64];
    NSData *remotePK = [NSData dataWithBytes:pk length:32];
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];

    SSBTunnelConnection *serverTunnel = [[SSBTunnelConnection alloc]
        initWithPeerId:@"@server"
         peerPublicKey:remotePK
         localIdentity:localSK
           roomSession:session
           tunnelReqID:99
              isServer:YES];

    XCTAssertNotNil(serverTunnel);
    XCTAssertTrue(serverTunnel.isServer);
    XCTAssertEqual(serverTunnel.tunnelReqID, 99);
    XCTAssertEqualObjects(serverTunnel.peerId, @"@server");
    XCTAssertFalse(serverTunnel.isConnected);
    XCTAssertNotNil(serverTunnel.rpcSession);
    [serverTunnel stop];
}

- (void)testMultipleDataChunksBufferedInOrder {
    NSData *chunk1 = [@"first" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *chunk2 = [@"second" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *chunk3 = [@"third" dataUsingEncoding:NSUTF8StringEncoding];

    [self.tunnel receiveTunnelData:chunk1];
    [self.tunnel receiveTunnelData:chunk2];
    [self.tunnel receiveTunnelData:chunk3];

    XCTestExpectation *exp = [self expectationWithDescription:@"Queue flush"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.15];
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(self.tunnel.incomingBuffer.count, 3);
    XCTAssertEqualObjects(self.tunnel.incomingBuffer[0], chunk1);
    XCTAssertEqualObjects(self.tunnel.incomingBuffer[1], chunk2);
    XCTAssertEqualObjects(self.tunnel.incomingBuffer[2], chunk3);
}

- (void)testMultiplePendingMessagesBufferedInOrder {
    XCTAssertFalse(self.tunnel.isHandshakeComplete);

    SSBMuxRPCMessage *msg1 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:1 body:[@"a" dataUsingEncoding:NSUTF8StringEncoding]];
    SSBMuxRPCMessage *msg2 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:2 body:[@"b" dataUsingEncoding:NSUTF8StringEncoding]];
    SSBMuxRPCMessage *msg3 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:3 body:[@"c" dataUsingEncoding:NSUTF8StringEncoding]];

    self.tunnel.rpcSession.sendMessageBlock(msg1);
    self.tunnel.rpcSession.sendMessageBlock(msg2);
    self.tunnel.rpcSession.sendMessageBlock(msg3);

    XCTestExpectation *exp = [self expectationWithDescription:@"Queue flush"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.15];
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(self.tunnel.pendingMessages.count, 3);
    XCTAssertEqualObjects(self.tunnel.pendingMessages[0], msg1);
    XCTAssertEqualObjects(self.tunnel.pendingMessages[1], msg2);
    XCTAssertEqualObjects(self.tunnel.pendingMessages[2], msg3);
}

- (void)testStopWithoutStartIsNonCrashing {
    SSBTunnelConnection *fresh = [[SSBTunnelConnection alloc]
        initWithPeerId:@"@peer"
         peerPublicKey:[NSMutableData dataWithLength:32]
         localIdentity:[NSMutableData dataWithLength:64]
           roomSession:self.roomSession
           tunnelReqID:1
              isServer:NO];
    XCTAssertNoThrow([fresh stop]);
}

- (void)testReceiveDataAfterStopIsNonCrashing {
    [self.tunnel start];
    [self.tunnel stop];

    NSData *data = [@"post-stop" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNoThrow([self.tunnel receiveTunnelData:data]);
}

- (void)testConnectionStateReadyCallbackSettable {
    __block BOOL fired = NO;
    self.tunnel.onConnectionStateReady = ^{ fired = YES; };
    XCTAssertNotNil(self.tunnel.onConnectionStateReady);
    XCTAssertFalse(fired); // Won't fire without a completed handshake
}

@end
