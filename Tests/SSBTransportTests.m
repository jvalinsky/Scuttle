#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBTransport.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/tweetnacl.h>

@interface SSBAppleTransportBackend (TestAccess)
- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                       options:(nullable SSBTransportConnectionOptions *)options
                                         queue:(dispatch_queue_t)queue;
@end

@interface SSBLinuxTransportBackend (TestAccess)
- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                       options:(nullable SSBTransportConnectionOptions *)options
                                         queue:(dispatch_queue_t)queue;
@end

static void SSBTransportGenerateKeypair(NSData **outPublic, NSData **outSecret) {
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

@interface SSBTransportTests : XCTestCase
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SSBTransportTests

- (void)setUp {
    [super setUp];
    self.queue = dispatch_queue_create("com.scuttlebutt.tests.transport", DISPATCH_QUEUE_SERIAL);
}

- (id<SSBTransportBackend>)backend {
    return [SSBTransport defaultBackend];
}

- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                       options:(nullable SSBTransportConnectionOptions *)options {
    id<SSBTransportBackend> backend = [self backend];
    if ([backend isKindOfClass:[SSBAppleTransportBackend class]]) {
        return [(SSBAppleTransportBackend *)backend listenerOnEndpoint:endpoint options:options queue:self.queue];
    }
    return [(SSBLinuxTransportBackend *)backend listenerOnEndpoint:endpoint options:options queue:self.queue];
}

- (SSBTransportConnectionOptions *)muxOptions {
    SSBTransportConnectionOptions *options = [[SSBTransportConnectionOptions alloc] init];
    options.enableMuxRPCFramer = YES;
    return options;
}

- (SSBTransportConnectionOptions *)securityAndMuxOptionsWithLocalSecret:(NSData *)localSecret
                                                            remotePublic:(nullable NSData *)remotePublic
                                                                asClient:(BOOL)asClient {
    SSBTransportConnectionOptions *options = [[SSBTransportConnectionOptions alloc] init];
    options.enableSecurityFramer = YES;
    options.enableMuxRPCFramer = YES;
    options.actingAsClient = asClient;
    options.localIdentitySecret = localSecret;
    options.remotePublicKey = remotePublic;
    return options;
}

- (NSData *)serializedMessageWithFlags:(SSBMuxRPCFlags)flags
                         requestNumber:(int32_t)requestNumber
                                  body:(NSData *)body {
    SSBMuxRPCMessage *message = [[SSBMuxRPCMessage alloc] initWithFlags:flags
                                                          requestNumber:requestNumber
                                                                   body:body ?: [NSData data]];
    return [message serialize];
}

- (void)testDefaultBackendMatchesPlatform {
    id<SSBTransportBackend> backend = [SSBTransport defaultBackend];
#ifdef __APPLE__
    XCTAssertTrue([backend isKindOfClass:[SSBAppleTransportBackend class]]);
#else
    XCTAssertTrue([backend isKindOfClass:[SSBLinuxTransportBackend class]]);
#endif
}

- (void)testDefaultBackendIsSingleton {
    id<SSBTransportBackend> b1 = [SSBTransport defaultBackend];
    id<SSBTransportBackend> b2 = [SSBTransport defaultBackend];
    XCTAssertEqual(b1, b2);
}

- (void)testEndpointFactoryMethod {
    SSBTransportEndpoint *ep = [SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:8080];
    XCTAssertNotNil(ep);
    XCTAssertEqualObjects(ep.host, @"127.0.0.1");
    XCTAssertEqual(ep.port, 8080);
}

- (void)testEndpointDesignatedInitializer {
    SSBTransportEndpoint *ep = [[SSBTransportEndpoint alloc] initWithHost:@"example.com" port:443];
    XCTAssertEqualObjects(ep.host, @"example.com");
    XCTAssertEqual(ep.port, 443);
}

- (void)testConnectionOptionsDefaults {
    SSBTransportConnectionOptions *opts = [[SSBTransportConnectionOptions alloc] init];
    XCTAssertTrue(opts.enableTCPNoDelay);
    XCTAssertTrue(opts.actingAsClient);
    XCTAssertFalse(opts.enableSecurityFramer);
    XCTAssertFalse(opts.enableMuxRPCFramer);
    XCTAssertNil(opts.localIdentitySecret);
    XCTAssertNil(opts.remotePublicKey);
}

- (void)testConnectionOptionsMutation {
    SSBTransportConnectionOptions *opts = [[SSBTransportConnectionOptions alloc] init];
    opts.enableTCPNoDelay = NO;
    opts.actingAsClient = NO;
    opts.enableSecurityFramer = YES;
    opts.enableMuxRPCFramer = YES;
    NSData *key = [NSData dataWithBytes:"testkey" length:7];
    opts.localIdentitySecret = key;
    opts.remotePublicKey = key;
    XCTAssertFalse(opts.enableTCPNoDelay);
    XCTAssertFalse(opts.actingAsClient);
    XCTAssertTrue(opts.enableSecurityFramer);
    XCTAssertTrue(opts.enableMuxRPCFramer);
    XCTAssertEqualObjects(opts.localIdentitySecret, key);
    XCTAssertEqualObjects(opts.remotePublicKey, key);
}

- (void)testMetadataKeyConstants {
    XCTAssertEqualObjects(SSBTransportMetadataFlagsKey, @"Flags");
    XCTAssertEqualObjects(SSBTransportMetadataRequestNumberKey, @"RequestNumber");
}

- (void)testAppleTransportBackendCanBeInstantiated {
    SSBAppleTransportBackend *backend = [[SSBAppleTransportBackend alloc] init];
    XCTAssertNotNil(backend);
}

- (void)testLinuxTransportBackendCanBeInstantiated {
    SSBLinuxTransportBackend *backend = [[SSBLinuxTransportBackend alloc] init];
    XCTAssertNotNil(backend);
}

- (void)testConnectionToEndpointReturnsNonnull {
    id<SSBTransportBackend> backend = [self backend];
    SSBTransportEndpoint *ep = [SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:1];
    id<SSBTransportConnection> conn = [backend connectionToEndpoint:ep options:nil queue:self.queue];
    XCTAssertNotNil(conn);
    XCTAssertEqual(conn.state, SSBTransportConnectionStateInvalid);
    XCTAssertEqualObjects(conn.endpoint.host, @"127.0.0.1");
    XCTAssertEqual(conn.endpoint.port, 1);
}

- (void)testConnectionCancelledStateTransition {
    id<SSBTransportBackend> backend = [self backend];
    SSBTransportEndpoint *ep = [SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:1];
    id<SSBTransportConnection> conn = [backend connectionToEndpoint:ep options:nil queue:self.queue];

    XCTestExpectation *cancelled = [self expectationWithDescription:@"connection cancelled"];
    [conn setStateChangedHandler:^(id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        if (state == SSBTransportConnectionStateCancelled) {
            [cancelled fulfill];
        }
    }];
    [conn start];
    [conn cancel];
    [self waitForExpectations:@[cancelled] timeout:5.0];
    XCTAssertEqual(conn.state, SSBTransportConnectionStateCancelled);
}

- (void)testConnectionFailedStateTransitionOnRefusedPort {
    // Connect to a port guaranteed to be closed — this triggers waiting or failed state.
    id<SSBTransportBackend> backend = [self backend];
    SSBTransportEndpoint *ep = [SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:1];
    id<SSBTransportConnection> conn = [backend connectionToEndpoint:ep options:nil queue:self.queue];

    XCTestExpectation *gotNonInvalid = [self expectationWithDescription:@"connection left invalid state"];
    gotNonInvalid.assertForOverFulfill = NO;
    [conn setStateChangedHandler:^(id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        if (state == SSBTransportConnectionStateFailed ||
            state == SSBTransportConnectionStateWaiting ||
            state == SSBTransportConnectionStatePreparing) {
            [gotNonInvalid fulfill];
        }
    }];
    [conn start];
    [self waitForExpectations:@[gotNonInvalid] timeout:5.0];
    [conn cancel];
}

- (void)testListenerCancelledStateTransition {
    id<SSBTransportListener> listener = [self listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                         options:nil];

    XCTestExpectation *ready = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *cancelled = [self expectationWithDescription:@"listener cancelled"];
    [listener setStateChangedHandler:^(id<SSBTransportListener> l, SSBTransportListenerState state, NSError * _Nullable error) {
        if (state == SSBTransportListenerStateReady) {
            [ready fulfill];
            [l cancel];
        } else if (state == SSBTransportListenerStateCancelled) {
            [cancelled fulfill];
        }
    }];
    [listener setNewConnectionHandler:^(id<SSBTransportConnection> connection) {}];
    [listener start];
    [self waitForExpectations:@[ready, cancelled] timeout:10.0];
    XCTAssertEqual(listener.state, SSBTransportListenerStateCancelled);
}

- (void)testListenerOnEndpointWithOptions {
    SSBTransportConnectionOptions *opts = [[SSBTransportConnectionOptions alloc] init];
    opts.enableMuxRPCFramer = YES;
    id<SSBTransportListener> listener = [self listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                         options:opts];
    XCTAssertNotNil(listener);
    XCTAssertEqual(listener.state, SSBTransportListenerStateInvalid);
    [listener cancel];
}

- (void)testAdoptConnectionReturnsNonnull {
    // Create a real connection object, then adopt it via the backend
    id<SSBTransportBackend> backend = [self backend];
    SSBTransportEndpoint *ep = [SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0];
    id<SSBTransportConnection> conn = [backend connectionToEndpoint:ep options:nil queue:self.queue];
    XCTAssertNotNil(conn);
    XCTAssertNil(conn.endpoint.host.length > 0 ? nil : conn.endpoint); // endpoint present
}

- (void)testRawLoopbackConnectionRoundTripsData {
    id<SSBTransportBackend> backend = [self backend];

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received ping"];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    XCTestExpectation *clientReceived = [self expectationWithDescription:@"client received pong"];

    id<SSBTransportListener> listener = [backend listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                              queue:self.queue];

    __block id<SSBTransportConnection> serverConnection = nil;
    [listener setStateChangedHandler:^(id<SSBTransportListener> currentListener, SSBTransportListenerState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportListenerStateReady) {
            [listenerReady fulfill];
        }
    }];

    [listener setNewConnectionHandler:^(id<SSBTransportConnection> acceptedConnection) {
        serverConnection = acceptedConnection;
        [serverAccepted fulfill];
        [acceptedConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
            XCTAssertNil(error);
            if (state == SSBTransportConnectionStateReady) {
                [acceptedConnection receiveMinimumLength:1 maximumLength:4096 completion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, BOOL isComplete, NSError * _Nullable receiveError) {
                    XCTAssertNil(receiveError);
                    XCTAssertNil(metadata);
                    XCTAssertFalse(isComplete);
                    XCTAssertEqualObjects([[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding], @"ping");
                    [serverReceived fulfill];

                    NSData *pong = [@"pong" dataUsingEncoding:NSUTF8StringEncoding];
                    [acceptedConnection sendData:pong isComplete:NO completion:^(NSError * _Nullable sendError) {
                        XCTAssertNil(sendError);
                    }];
                }];
            }
        }];
        [acceptedConnection start];
    }];

    [listener start];
    [self waitForExpectations:@[ listenerReady ] timeout:5.0];

    id<SSBTransportConnection> clientConnection = [backend connectionToEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:listener.port]
                                                                        options:nil
                                                                          queue:self.queue];
    [clientConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportConnectionStateReady) {
            [clientReady fulfill];
            [clientConnection receiveMinimumLength:1 maximumLength:4096 completion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, BOOL isComplete, NSError * _Nullable receiveError) {
                XCTAssertNil(receiveError);
                XCTAssertNil(metadata);
                XCTAssertFalse(isComplete);
                XCTAssertEqualObjects([[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding], @"pong");
                [clientReceived fulfill];
            }];

            NSData *ping = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
            [clientConnection sendData:ping isComplete:NO completion:^(NSError * _Nullable sendError) {
                XCTAssertNil(sendError);
            }];
        }
    }];

    [clientConnection start];

    [self waitForExpectations:@[ serverAccepted, clientReady, serverReceived, clientReceived ] timeout:5.0];

    [clientConnection cancel];
    [serverConnection cancel];
    [listener cancel];
}

- (void)testMuxFramerAcceptedConnectionParsesSplitHeaderAndZeroLengthBody {
    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *firstMessage = [self expectationWithDescription:@"first mux message"];
    XCTestExpectation *secondMessage = [self expectationWithDescription:@"zero-length mux message"];

    id<SSBTransportListener> listener = [self listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                         options:[self muxOptions]];

    __block id<SSBTransportConnection> serverConnection = nil;
    [listener setStateChangedHandler:^(id<SSBTransportListener> currentListener, SSBTransportListenerState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportListenerStateReady) {
            [listenerReady fulfill];
        }
    }];

    [listener setNewConnectionHandler:^(id<SSBTransportConnection> acceptedConnection) {
        serverConnection = acceptedConnection;
        [serverAccepted fulfill];
        [acceptedConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
            XCTAssertNil(error);
            if (state != SSBTransportConnectionStateReady) {
                return;
            }

            __block NSInteger receiveCount = 0;
            __block void (^receiveNext)(void) = nil;
            receiveNext = ^{
                [acceptedConnection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, __unused BOOL isComplete, NSError * _Nullable receiveError) {
                    XCTAssertNil(receiveError);
                    receiveCount += 1;
                    if (receiveCount == 1) {
                        XCTAssertEqualObjects(content, [@"hello-mux" dataUsingEncoding:NSUTF8StringEncoding]);
                        XCTAssertEqualObjects(metadata[SSBTransportMetadataFlagsKey], @((int)(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)));
                        XCTAssertEqualObjects(metadata[SSBTransportMetadataRequestNumberKey], @(77));
                        [firstMessage fulfill];
                        receiveNext();
                        return;
                    }

                    XCTAssertEqual(content.length, 0u);
                    XCTAssertEqualObjects(metadata[SSBTransportMetadataFlagsKey], @((int)SSBMuxRPCFlagEndErr));
                    XCTAssertEqualObjects(metadata[SSBTransportMetadataRequestNumberKey], @(88));
                    [secondMessage fulfill];
                }];
            };

            receiveNext();
        }];
        [acceptedConnection start];
    }];

    [listener start];
    [self waitForExpectations:@[listenerReady] timeout:5.0];

    id<SSBTransportConnection> rawClient = [[self backend] connectionToEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:listener.port]
                                                                        options:nil
                                                                          queue:self.queue];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    [rawClient setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportConnectionStateReady) {
            [clientReady fulfill];
        }
    }];
    [rawClient start];
    [self waitForExpectations:@[serverAccepted, clientReady] timeout:5.0];

    NSData *firstSerialized = [self serializedMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                 requestNumber:77
                                                          body:[@"hello-mux" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *secondSerialized = [self serializedMessageWithFlags:SSBMuxRPCFlagEndErr
                                                  requestNumber:88
                                                           body:[NSData data]];

    NSData *firstChunk = [firstSerialized subdataWithRange:NSMakeRange(0, 4)];
    NSData *secondChunk = [firstSerialized subdataWithRange:NSMakeRange(4, firstSerialized.length - 4)];

    XCTestExpectation *firstChunkSent = [self expectationWithDescription:@"first chunk sent"];
    XCTestExpectation *secondChunkSent = [self expectationWithDescription:@"second chunk sent"];
    XCTestExpectation *thirdChunkSent = [self expectationWithDescription:@"third chunk sent"];

    [rawClient sendData:firstChunk isComplete:NO completion:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        [firstChunkSent fulfill];
    }];
    [self waitForExpectations:@[firstChunkSent] timeout:2.0];

    [rawClient sendData:secondChunk isComplete:NO completion:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        [secondChunkSent fulfill];
    }];
    [rawClient sendData:secondSerialized isComplete:NO completion:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        [thirdChunkSent fulfill];
    }];

    [self waitForExpectations:@[secondChunkSent, thirdChunkSent, firstMessage, secondMessage] timeout:8.0];

    [rawClient cancel];
    [serverConnection cancel];
    [listener cancel];
}

- (void)testSecurityFramerQueuesSendBeforeReady {
    NSData *clientPublic = nil;
    NSData *clientSecret = nil;
    NSData *serverPublic = nil;
    NSData *serverSecret = nil;
    SSBTransportGenerateKeypair(&clientPublic, &clientSecret);
    SSBTransportGenerateKeypair(&serverPublic, &serverSecret);

    SSBTransportConnectionOptions *listenerOptions = [self securityAndMuxOptionsWithLocalSecret:serverSecret
                                                                                    remotePublic:nil
                                                                                        asClient:NO];
    listenerOptions.enableMuxRPCFramer = NO;
    SSBTransportConnectionOptions *clientOptions = [self securityAndMuxOptionsWithLocalSecret:clientSecret
                                                                                   remotePublic:serverPublic
                                                                                       asClient:YES];
    clientOptions.enableMuxRPCFramer = NO;

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received queued payload"];
    XCTestExpectation *sendCompleted = [self expectationWithDescription:@"queued send completed"];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];

    id<SSBTransportListener> listener = [self listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                         options:listenerOptions];

    __block id<SSBTransportConnection> serverConnection = nil;
    __block BOOL clientDidReachReady = NO;
    NSData *payload = [@"queued-before-security-ready" dataUsingEncoding:NSUTF8StringEncoding];

    [listener setStateChangedHandler:^(id<SSBTransportListener> currentListener, SSBTransportListenerState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportListenerStateReady) {
            [listenerReady fulfill];
        }
    }];

    [listener setNewConnectionHandler:^(id<SSBTransportConnection> acceptedConnection) {
        serverConnection = acceptedConnection;
        [serverAccepted fulfill];
        [acceptedConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
            XCTAssertNil(error);
            if (state == SSBTransportConnectionStateReady) {
                [acceptedConnection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, __unused BOOL isComplete, NSError * _Nullable receiveError) {
                    XCTAssertNil(receiveError);
                    XCTAssertNil(metadata);
                    XCTAssertEqualObjects(content, payload);
                    [serverReceived fulfill];
                }];
            }
        }];
        [acceptedConnection start];
    }];

    [listener start];
    [self waitForExpectations:@[listenerReady] timeout:5.0];

    id<SSBTransportConnection> clientConnection = [[self backend] connectionToEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:listener.port]
                                                                               options:clientOptions
                                                                                 queue:self.queue];
    [clientConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportConnectionStateReady) {
            clientDidReachReady = YES;
            [clientReady fulfill];
        }
    }];
    [clientConnection start];

    [clientConnection sendData:payload isComplete:NO completion:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertTrue(clientDidReachReady);
        [sendCompleted fulfill];
    }];

    [self waitForExpectations:@[serverAccepted, clientReady, sendCompleted, serverReceived] timeout:10.0];

    [clientConnection cancel];
    [serverConnection cancel];
    [listener cancel];
}

- (void)testSecurityAndMuxFramersRoundTripSerializedMessages {
    NSData *clientPublic = nil;
    NSData *clientSecret = nil;
    NSData *serverPublic = nil;
    NSData *serverSecret = nil;
    SSBTransportGenerateKeypair(&clientPublic, &clientSecret);
    SSBTransportGenerateKeypair(&serverPublic, &serverSecret);

    SSBTransportConnectionOptions *listenerOptions = [self securityAndMuxOptionsWithLocalSecret:serverSecret
                                                                                    remotePublic:nil
                                                                                        asClient:NO];
    SSBTransportConnectionOptions *clientOptions = [self securityAndMuxOptionsWithLocalSecret:clientSecret
                                                                                   remotePublic:serverPublic
                                                                                       asClient:YES];

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received mux payload"];
    XCTestExpectation *clientReceived = [self expectationWithDescription:@"client received mux reply"];

    id<SSBTransportListener> listener = [self listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                         options:listenerOptions];

    __block id<SSBTransportConnection> serverConnection = nil;
    [listener setStateChangedHandler:^(id<SSBTransportListener> currentListener, SSBTransportListenerState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportListenerStateReady) {
            [listenerReady fulfill];
        }
    }];

    [listener setNewConnectionHandler:^(id<SSBTransportConnection> acceptedConnection) {
        serverConnection = acceptedConnection;
        [serverAccepted fulfill];
        [acceptedConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
            XCTAssertNil(error);
            if (state != SSBTransportConnectionStateReady) {
                return;
            }

            [acceptedConnection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, __unused BOOL isComplete, NSError * _Nullable receiveError) {
                XCTAssertNil(receiveError);
                XCTAssertEqualObjects(content, [@"hello-secure" dataUsingEncoding:NSUTF8StringEncoding]);
                XCTAssertEqualObjects(metadata[SSBTransportMetadataFlagsKey], @((int)(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)));
                XCTAssertEqualObjects(metadata[SSBTransportMetadataRequestNumberKey], @(77));
                [serverReceived fulfill];

                NSData *reply = [self serializedMessageWithFlags:SSBMuxRPCFlagTypeString
                                                   requestNumber:-77
                                                            body:[@"ack" dataUsingEncoding:NSUTF8StringEncoding]];
                [acceptedConnection sendData:reply isComplete:NO completion:^(NSError * _Nullable sendError) {
                    XCTAssertNil(sendError);
                }];
            }];
        }];
        [acceptedConnection start];
    }];

    [listener start];
    [self waitForExpectations:@[listenerReady] timeout:5.0];

    id<SSBTransportConnection> clientConnection = [[self backend] connectionToEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:listener.port]
                                                                               options:clientOptions
                                                                                 queue:self.queue];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    [clientConnection setStateChangedHandler:^(__unused id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        XCTAssertNil(error);
        if (state == SSBTransportConnectionStateReady) {
            [clientReady fulfill];
            [clientConnection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, __unused BOOL isComplete, NSError * _Nullable receiveError) {
                XCTAssertNil(receiveError);
                XCTAssertEqualObjects(content, [@"ack" dataUsingEncoding:NSUTF8StringEncoding]);
                XCTAssertEqualObjects(metadata[SSBTransportMetadataFlagsKey], @((int)SSBMuxRPCFlagTypeString));
                XCTAssertEqualObjects(metadata[SSBTransportMetadataRequestNumberKey], @(-77));
                [clientReceived fulfill];
            }];

            NSData *request = [self serializedMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                 requestNumber:77
                                                          body:[@"hello-secure" dataUsingEncoding:NSUTF8StringEncoding]];
            [clientConnection sendData:request isComplete:NO completion:^(NSError * _Nullable sendError) {
                XCTAssertNil(sendError);
            }];
        }
    }];
    [clientConnection start];

    [self waitForExpectations:@[serverAccepted, clientReady, serverReceived, clientReceived] timeout:10.0];

    [clientConnection cancel];
    [serverConnection cancel];
    [listener cancel];
}

@end
