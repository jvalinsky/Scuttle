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

@end
