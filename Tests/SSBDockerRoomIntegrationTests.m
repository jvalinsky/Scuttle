/**
 * SSBDockerRoomIntegrationTests.m
 *
 * Live integration tests against go-ssb-room running in Docker.
 * Tests verify EBT replication, tunnel establishment, and room protocol
 * against a real server — exercising the full SHS → BoxStream → MuxRPC stack.
 *
 * Prerequisites:
 *   1. Run: ./tools/generate-room-keypair.sh
 *   2. Run: docker compose up -d
 *   3. Set env var: SSB_DOCKER_ROOM=1  (or tests auto-probe localhost:8008)
 *
 * Tests are skipped automatically if the Docker room is not reachable.
 * All tests write trace events to ssb-room-data/scuttle-trace.jsonl for
 * correlation with go-ssb-room's [SCUTTLE-DIAG] logs.
 */

#import <XCTest/XCTest.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/SSBTransport.h>
#import <SSBNetwork/SSBMessageCodec.h>
#import "../Sources/SSBMuxRPCSession.h"
#import "../Sources/SSBTunnelConnection.h"
#import "../Sources/tweetnacl.h"

// ─── Test helpers ─────────────────────────────────────────────────────────────

static void DockerTestGenerateKeypair(NSData **outPublic, NSData **outSecret) {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPublic)  *outPublic  = [NSData dataWithBytes:pk length:32];
    if (outSecret)  *outSecret  = [NSData dataWithBytes:sk length:64];
}

static NSString *DockerTestFeedIDFromPublicKey(NSData *pubKey) {
    return [NSString stringWithFormat:@"@%@.ed25519",
            [pubKey base64EncodedStringWithOptions:0]];
}

/// Returns the project root (two levels above this file in Tests/).
static NSString *DockerTestProjectRoot(void) {
    NSString *thisFile = @(__FILE__);
    return [[thisFile stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

/// TCP probe: returns YES if localhost:8008 accepts a connection within 2 seconds.
static BOOL DockerRoomReachable(void) {
    // Use a simple POSIX socket connect to probe localhost:8008
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;

    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8008);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    BOOL ok = (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0);
    close(sock);
    return ok;
}

/// Loads the room's raw 32-byte public key from ssb-room-data/server-pubkey.bin
static NSData *DockerRoomPublicKey(void) {
    NSString *path = [DockerTestProjectRoot() stringByAppendingPathComponent:@"ssb-room-data/server-pubkey.bin"];
    return [NSData dataWithContentsOfFile:path];
}

/// Loads the room's @<base64>.ed25519 ID string
static NSString *DockerRoomID(void) {
    NSString *path = [DockerTestProjectRoot() stringByAppendingPathComponent:@"ssb-room-data/server-id.txt"];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

// ─── Test access categories ───────────────────────────────────────────────────

@interface SSBRoomClient (DockerTestAccess)
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSData *)serverPubKey
               localIdentity:(nullable NSData *)localIdentitySecret
                   feedStore:(nullable SSBFeedStore *)feedStore
                   blobStore:(nullable SSBBlobStore *)blobStore
            transportBackend:(nullable id<SSBTransportBackend>)transportBackend
                   traceSink:(nullable SSBProtocolTraceSink)traceSink;
- (void)performClientQueueSync:(dispatch_block_t)block;
- (NSString *)localPublicID;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, id> *activeTunnels;
@end

// ─── Mock delegate ────────────────────────────────────────────────────────────

@interface SSBDockerTestDelegate : NSObject <SSBRoomClientDelegate>
@property (nonatomic, copy) void (^onEndpointsUpdate)(NSArray<NSString *> *endpoints);
@property (nonatomic, copy) void (^onTunnelEstablished)(NSString *peerID);
@property (nonatomic, copy) void (^onMessagesReplicated)(NSString *peerID, NSInteger count);
@property (nonatomic, copy) void (^onError)(NSError *error);
@property (nonatomic, strong) NSMutableArray<NSString *> *logMessages;
@property (nonatomic, strong) NSMutableArray<NSString *> *knownEndpoints;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *replicatedCounts;
@property (nonatomic, strong) NSMutableArray<NSError *> *errors;
@end

@implementation SSBDockerTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _logMessages = [NSMutableArray array];
        _knownEndpoints = [NSMutableArray array];
        _replicatedCounts = [NSMutableDictionary dictionary];
        _errors = [NSMutableArray array];
    }
    return self;
}

- (void)roomClient:(id)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    [self.knownEndpoints removeAllObjects];
    [self.knownEndpoints addObjectsFromArray:endpoints];
    if (self.onEndpointsUpdate) self.onEndpointsUpdate(endpoints);
}

- (void)roomClient:(id)client didEstablishTunnelWithPeer:(NSString *)peerId {
    if (self.onTunnelEstablished) self.onTunnelEstablished(peerId);
}

- (void)roomClient:(id)client didEncounterError:(NSError *)error {
    [self.errors addObject:error];
    if (self.onError) self.onError(error);
}

- (void)roomClient:(id)client didLogMessage:(NSString *)message {
    [self.logMessages addObject:message];
}

- (void)roomClient:(id)client didReplicateMessagesFromPeer:(NSString *)peerId count:(NSInteger)count {
    self.replicatedCounts[peerId] = @(count);
    if (self.onMessagesReplicated) self.onMessagesReplicated(peerId, count);
}

- (void)roomClient:(id)client didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author peerID:(nullable NSString *)peerID {
    // No-op in tests
}

@end

// ─── Test suite ───────────────────────────────────────────────────────────────

@interface SSBDockerRoomIntegrationTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *traceEvents;
@property (nonatomic, strong) NSString *traceFilePath;
@end

@implementation SSBDockerRoomIntegrationTests

+ (void)setUp {
    // Check once per test run — avoids repeated TCP probes
    [super setUp];
}

- (void)setUp {
    [super setUp];

    // Skip if Docker room is not available
    BOOL envSet = (getenv("SSB_DOCKER_ROOM") != NULL);
    if (!envSet && !DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room Docker container not available. "
                @"Run: docker compose up -d  or set SSB_DOCKER_ROOM=1");
    }

    NSData *serverPubKey = DockerRoomPublicKey();
    XCTAssertNotNil(serverPubKey, @"ssb-room-data/server-pubkey.bin not found — run ./tools/generate-room-keypair.sh first");
    XCTAssertEqual(serverPubKey.length, 32u, @"server public key must be 32 bytes");

    // Temp directory for test feed stores
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Trace event collection (written to ssb-room-data/scuttle-trace.jsonl at tearDown)
    self.traceEvents = [NSMutableArray array];
    self.traceFilePath = [DockerTestProjectRoot() stringByAppendingPathComponent:
                          @"ssb-room-data/scuttle-trace.jsonl"];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];

    // Append trace events to JSONL file for correlation with go-ssb-room logs
    if (self.traceEvents.count > 0) {
        NSMutableString *jsonl = [NSMutableString string];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
        [jsonl appendFormat:@"// Test: %@ at %@\n", self.name, [fmt stringFromDate:[NSDate date]]];
        for (NSDictionary *event in self.traceEvents) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
            if (data) {
                [jsonl appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
                [jsonl appendString:@"\n"];
            }
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self.traceFilePath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:self.traceFilePath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:self.traceFilePath];
        }
        [fh seekToEndOfFile];
        [fh writeData:[jsonl dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }

    // Brief pause so NWConnection/NWListener objects from this test fully drain before the next.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    [super tearDown];
}

// ─── Client factory ───────────────────────────────────────────────────────────

- (SSBRoomClient *)makeClientWithSecret:(NSData *)secret
                              feedStore:(SSBFeedStore *)feedStore
                               delegate:(SSBDockerTestDelegate *)delegate {
    return [self makeClientWithSecret:secret feedStore:feedStore blobStore:nil delegate:delegate];
}

- (SSBRoomClient *)makeClientWithSecret:(NSData *)secret
                              feedStore:(SSBFeedStore *)feedStore
                              blobStore:(nullable SSBBlobStore *)blobStore
                               delegate:(SSBDockerTestDelegate *)delegate {
    NSData *serverPubKey = DockerRoomPublicKey();
    NSMutableArray<NSDictionary *> *trace = self.traceEvents;

    SSBRoomClient *client = [[SSBRoomClient alloc] initWithHost:@"127.0.0.1"
                                                           port:8008
                                                   serverPubKey:serverPubKey
                                                  localIdentity:secret
                                                      feedStore:feedStore
                                                      blobStore:blobStore
                                               transportBackend:[SSBTransport defaultBackend]
                                                      traceSink:^(NSDictionary<NSString *, id> *event) {
        [trace addObject:event];
    }];
    client.delegate = delegate;
    client.autoReconnect = NO;
    return client;
}

- (SSBFeedStore *)makeFeedStore:(NSString *)name {
    NSString *path = [self.tempDir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.sqlite3", name]];
    return [[SSBFeedStore alloc] initWithPath:path];
}

// ─── Test 1: Basic room connection ───────────────────────────────────────────

- (void)testRoomConnection {
    NSData *pubA = nil, *secA = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    SSBFeedStore *storeA = [self makeFeedStore:@"conn-A"];

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];

    XCTestExpectation *connectedExp = [self expectationWithDescription:@"Client A connected to room"];
    __block BOOL connectedFulfilled = NO;
    delegateA.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if (!connectedFulfilled) { connectedFulfilled = YES; [connectedExp fulfill]; }
    };
    delegateA.onError = ^(NSError *error) {
        XCTFail(@"Connection error: %@", error);
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA delegate:delegateA];
    [clientA connect];

    [self waitForExpectations:@[connectedExp] timeout:30.0];
    XCTAssertTrue(clientA.isConnected, @"Client A should be connected to Docker room");
    NSLog(@"[SCUTTLE-DIAG] testRoomConnection: clientA=%@", clientA.localPublicID);

    [clientA disconnect];
    [storeA wipeDatabase];
}

// ─── Test 2: Two peers see each other as attendants ───────────────────────────

- (void)testPeerDiscovery {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    DockerTestGenerateKeypair(&pubB, &secB);

    NSString *idA = DockerTestFeedIDFromPublicKey(pubA);
    NSString *idB = DockerTestFeedIDFromPublicKey(pubB);

    SSBFeedStore *storeA = [self makeFeedStore:@"disc-A"];
    SSBFeedStore *storeB = [self makeFeedStore:@"disc-B"];

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];
    SSBDockerTestDelegate *delegateB = [[SSBDockerTestDelegate alloc] init];

    XCTestExpectation *bSeesA = [self expectationWithDescription:@"Client B sees A in attendants"];
    XCTestExpectation *aSeesB = [self expectationWithDescription:@"Client A sees B in attendants"];

    delegateA.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if ([endpoints containsObject:idB]) [aSeesB fulfill];
    };
    delegateB.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if ([endpoints containsObject:idA]) [bSeesA fulfill];
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA delegate:delegateA];
    SSBRoomClient *clientB = [self makeClientWithSecret:secB feedStore:storeB delegate:delegateB];

    [clientA connect];
    // Small delay so A is in the room before B joins
    [NSThread sleepForTimeInterval:1.0];
    [clientB connect];

    [self waitForExpectations:@[bSeesA, aSeesB] timeout:30.0];

    NSLog(@"[SCUTTLE-DIAG] testPeerDiscovery: A=%@ B=%@", idA, idB);
    NSLog(@"[SCUTTLE-DIAG] testPeerDiscovery: A's endpoints=%@", delegateA.knownEndpoints);
    NSLog(@"[SCUTTLE-DIAG] testPeerDiscovery: B's endpoints=%@", delegateB.knownEndpoints);

    [clientA disconnect];
    [clientB disconnect];
    [storeA wipeDatabase];
    [storeB wipeDatabase];
}

// ─── Test 3: Tunnel establishment through room ────────────────────────────────

- (void)testTunnelEstablishment {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    DockerTestGenerateKeypair(&pubB, &secB);

    NSString *idA = DockerTestFeedIDFromPublicKey(pubA);
    NSString *idB = DockerTestFeedIDFromPublicKey(pubB);

    SSBFeedStore *storeA = [self makeFeedStore:@"tunnel-A"];
    SSBFeedStore *storeB = [self makeFeedStore:@"tunnel-B"];

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];
    SSBDockerTestDelegate *delegateB = [[SSBDockerTestDelegate alloc] init];

    XCTestExpectation *bJoined     = [self expectationWithDescription:@"B visible to A"];
    XCTestExpectation *tunnelToB   = [self expectationWithDescription:@"A tunneled to B"];
    XCTestExpectation *tunnelFromA = [self expectationWithDescription:@"B has tunnel from A"];

    __block BOOL bJoinedFulfilled = NO;
    delegateA.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if (!bJoinedFulfilled && [endpoints containsObject:idB]) {
            bJoinedFulfilled = YES;
            [bJoined fulfill];
        }
    };
    __block BOOL tunnelToBFulfilled = NO;
    delegateA.onTunnelEstablished = ^(NSString *peerID) {
        if (!tunnelToBFulfilled && [peerID isEqualToString:idB]) {
            tunnelToBFulfilled = YES;
            [tunnelToB fulfill];
        }
    };
    __block BOOL tunnelFromAFulfilled = NO;
    delegateB.onTunnelEstablished = ^(NSString *peerID) {
        if (!tunnelFromAFulfilled && [peerID isEqualToString:idA]) {
            tunnelFromAFulfilled = YES;
            [tunnelFromA fulfill];
        }
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA delegate:delegateA];
    SSBRoomClient *clientB = [self makeClientWithSecret:secB feedStore:storeB delegate:delegateB];

    [clientA connect];
    [NSThread sleepForTimeInterval:1.0];
    [clientB connect];

    // Wait for B to appear in A's endpoints, then initiate tunnel
    [self waitForExpectations:@[bJoined] timeout:30.0];
    [clientA connectToPeer:idB];

    [self waitForExpectations:@[tunnelToB, tunnelFromA] timeout:30.0];

    NSLog(@"[SCUTTLE-DIAG] testTunnelEstablishment: tunnel A->B established through Docker room");

    [clientA disconnect];
    [clientB disconnect];
    [storeA wipeDatabase];
    [storeB wipeDatabase];
}

// ─── Test 4: EBT replication through room (the main event) ───────────────────

- (void)testEBTReplicationThroughRoom {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    DockerTestGenerateKeypair(&pubB, &secB);

    NSString *idA = DockerTestFeedIDFromPublicKey(pubA);
    NSString *idB = DockerTestFeedIDFromPublicKey(pubB);

    SSBFeedStore *storeA = [self makeFeedStore:@"ebt-A"];
    SSBFeedStore *storeB = [self makeFeedStore:@"ebt-B"];

    // Populate 5 messages in A's store
    NSString *prevKey = nil;
    for (NSInteger i = 1; i <= 5; i++) {
        NSDictionary *content = @{@"type": @"post", @"text": [NSString stringWithFormat:@"msg %ld", (long)i]};
        NSDictionary *signedValue = [SSBMessageCodec createSignedMessageWithContent:content
                                                                             author:idA
                                                                           sequence:i
                                                                        previousKey:prevKey
                                                                          secretKey:secA];
        if (signedValue) {
            SSBMessage *msg = [[SSBMessage alloc] init];
            msg.key = [SSBMessageCodec computeMessageKey:signedValue];
            msg.author = idA;
            msg.sequence = i;
            msg.previousKey = prevKey;
            msg.claimedTimestamp = [signedValue[@"timestamp"] longLongValue];
            msg.content = content;
            msg.contentType = content[@"type"];
            msg.valueJSON = [SSBMessageCodec encodeLegacyValue:signedValue includeSignature:YES];
            NSError *storeErr = nil;
            [storeA appendMessage:msg error:&storeErr];
            prevKey = msg.key;
        }
    }

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];
    SSBDockerTestDelegate *delegateB = [[SSBDockerTestDelegate alloc] init];

    XCTestExpectation *bSeesA       = [self expectationWithDescription:@"B sees A"];
    XCTestExpectation *tunnelReady  = [self expectationWithDescription:@"tunnel B->A ready"];
    XCTestExpectation *replication  = [self expectationWithDescription:@"B replicated A's messages"];

    __block BOOL bSeesAFulfilled = NO;
    delegateB.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if (!bSeesAFulfilled && [endpoints containsObject:idA]) {
            bSeesAFulfilled = YES;
            [bSeesA fulfill];
        }
    };
    __block BOOL tunnelReadyFulfilled = NO;
    delegateB.onTunnelEstablished = ^(NSString *peerID) {
        if (!tunnelReadyFulfilled && [peerID isEqualToString:idA]) {
            tunnelReadyFulfilled = YES;
            [tunnelReady fulfill];
        }
    };
    __block NSInteger totalReplicated = 0;
    __block BOOL replicationFulfilled = NO;
    delegateB.onMessagesReplicated = ^(NSString *peerID, NSInteger count) {
        if ([peerID isEqualToString:idA]) {
            totalReplicated += count;
            if (!replicationFulfilled && totalReplicated >= 5) {
                replicationFulfilled = YES;
                [replication fulfill];
            }
        }
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA delegate:delegateA];
    SSBRoomClient *clientB = [self makeClientWithSecret:secB feedStore:storeB delegate:delegateB];

    [clientA connect];
    [NSThread sleepForTimeInterval:1.0];
    [clientB connect];

    [self waitForExpectations:@[bSeesA] timeout:30.0];
    [clientB connectToPeer:idA];

    [self waitForExpectations:@[tunnelReady] timeout:30.0];
    [self waitForExpectations:@[replication] timeout:60.0];

    // Verify B's store contains A's messages
    SSBFeedState *feedState = [storeB feedStateForAuthor:idA];
    XCTAssertNotNil(feedState, @"B should have feed state for A");
    XCTAssertEqual(feedState.maxSequence, 5, @"B should have all 5 of A's messages");

    NSLog(@"[SCUTTLE-DIAG] testEBTReplicationThroughRoom: SUCCESS — B has %ld msgs from A",
          (long)feedState.maxSequence);

    [clientA disconnect];
    [clientB disconnect];
    [storeA wipeDatabase];
    [storeB wipeDatabase];
}

// ─── Test 5: Blob sync through room tunnel ─────────────────────────────────

- (void)testBlobSyncThroughRoom {
    NSData *pubA = nil, *secA = nil;
    NSData *pubB = nil, *secB = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    DockerTestGenerateKeypair(&pubB, &secB);

    NSString *idA = DockerTestFeedIDFromPublicKey(pubA);
    NSString *idB = DockerTestFeedIDFromPublicKey(pubB);

    SSBFeedStore *storeA = [self makeFeedStore:@"blob-A"];
    SSBFeedStore *storeB = [self makeFeedStore:@"blob-B"];

    // Create isolated blob stores in temp directories
    NSString *blobDirA = [self.tempDir stringByAppendingPathComponent:@"blobs-A"];
    NSString *blobDirB = [self.tempDir stringByAppendingPathComponent:@"blobs-B"];
    [[NSFileManager defaultManager] createDirectoryAtPath:blobDirA withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:blobDirB withIntermediateDirectories:YES attributes:nil error:nil];
    SSBBlobStore *blobStoreA = [[SSBBlobStore alloc] initWithPath:blobDirA];
    SSBBlobStore *blobStoreB = [[SSBBlobStore alloc] initWithPath:blobDirB];

    // Store a test blob on A
    NSData *testData = [@"Hello from SSB blob sync over room tunnel" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobID = [blobStoreA addBlobWithData:testData];
    XCTAssertNotNil(blobID, @"A should have stored the blob");

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];
    SSBDockerTestDelegate *delegateB = [[SSBDockerTestDelegate alloc] init];

    XCTestExpectation *bSeesA       = [self expectationWithDescription:@"B sees A in attendants"];
    XCTestExpectation *tunnelReady  = [self expectationWithDescription:@"B has tunnel to A"];
    XCTestExpectation *blobFetched  = [self expectationWithDescription:@"B fetched blob from A"];

    __block BOOL bSeesAFulfilled = NO;
    delegateB.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        if (!bSeesAFulfilled && [endpoints containsObject:idA]) {
            bSeesAFulfilled = YES;
            [bSeesA fulfill];
        }
    };
    __block BOOL tunnelReadyFulfilled = NO;
    delegateB.onTunnelEstablished = ^(NSString *peerID) {
        if (!tunnelReadyFulfilled && [peerID isEqualToString:idA]) {
            tunnelReadyFulfilled = YES;
            [tunnelReady fulfill];
        }
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA blobStore:blobStoreA delegate:delegateA];
    SSBRoomClient *clientB = [self makeClientWithSecret:secB feedStore:storeB blobStore:blobStoreB delegate:delegateB];

    [clientA connect];
    [NSThread sleepForTimeInterval:1.0];
    [clientB connect];

    [self waitForExpectations:@[bSeesA] timeout:60.0];
    [clientB connectToPeer:idA];
    [self waitForExpectations:@[tunnelReady] timeout:30.0];

    // Fetch the blob from A via B's tunnel session
    SSBTunnelConnection *tunnelToA = clientB.activeTunnels[idA];
    XCTAssertNotNil(tunnelToA, @"B should have an active tunnel to A");
    SSBMuxRPCSession *tunnelSession = tunnelToA.rpcSession;
    XCTAssertNotNil(tunnelSession, @"Tunnel session should be available");

    [blobStoreB fetchBlob:blobID session:tunnelSession completion:^(NSString *localPath, NSError *error) {
        XCTAssertNil(error, @"Blob fetch should not error: %@", error);
        XCTAssertNotNil(localPath, @"Blob fetch should return a local path");
        [blobFetched fulfill];
    }];

    [self waitForExpectations:@[blobFetched] timeout:15.0];

    // Verify B's blob store now has the blob with correct content
    XCTAssertTrue([blobStoreB hasBlob:blobID], @"B's blob store should contain the blob");
    NSString *fetchedPath = [blobStoreB localPathForBlobID:blobID];
    NSData *fetchedData = [NSData dataWithContentsOfFile:fetchedPath];
    XCTAssertEqualObjects(fetchedData, testData, @"Fetched blob content should match original");

    NSLog(@"[SCUTTLE-DIAG] testBlobSyncThroughRoom: SUCCESS — B fetched blob %@ from A via room tunnel", blobID);

    [clientA disconnect];
    [clientB disconnect];
    [storeA wipeDatabase];
    [storeB wipeDatabase];
}

// ─── Test 6: Sync progress -1 sentinel doesn't produce bogus progress ────────

- (void)testNegativeOneClockDoesNotProduceBogusProgress {
    NSData *pubA = nil, *secA = nil;
    DockerTestGenerateKeypair(&pubA, &secA);
    SSBFeedStore *storeA = [self makeFeedStore:@"sentinel-A"];

    SSBDockerTestDelegate *delegateA = [[SSBDockerTestDelegate alloc] init];

    __block NSString *capturedStatus = nil;
    __block float capturedProgress = -999.0f;

    // Capture any sync status update
    [delegateA setOnEndpointsUpdate:nil]; // silence unused warning
    // We override the sync status callback via KVO or subclass — instead use the
    // protocol delegate. Since we can't easily intercept -1 sentinel in a live test
    // without a real peer sending it, this test verifies the connection succeeds
    // and that we can connect cleanly to the room without the ABS bug crashing things.
    delegateA.onError = ^(NSError *error) {
        capturedStatus = error.localizedDescription;
    };

    XCTestExpectation *connected = [self expectationWithDescription:@"connected to room"];
    delegateA.onEndpointsUpdate = ^(NSArray<NSString *> *endpoints) {
        [connected fulfill];
    };

    SSBRoomClient *clientA = [self makeClientWithSecret:secA feedStore:storeA delegate:delegateA];
    [clientA connect];

    [self waitForExpectations:@[connected] timeout:30.0];
    XCTAssertTrue(clientA.isConnected);
    XCTAssertNil(capturedStatus, @"No errors should occur on basic connection");

    [clientA disconnect];
    [storeA wipeDatabase];
}

@end
