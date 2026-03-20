#import <XCTest/XCTest.h>

#if !__APPLE__

#import <SSBNetwork/SSBNetworkCompat.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/SSBMuxRPCFramer.h>
#import <SSBNetwork/SSBSecurityFramer.h>
#import <SSBNetwork/tweetnacl.h>

@interface SHLoopbackPair : NSObject
@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) nw_connection_t client;
@property (nonatomic, strong) nw_connection_t server;
@property (nonatomic, assign) uint16_t port;
@end

@implementation SHLoopbackPair
@end

static dispatch_data_t SHDispatchDataFromNSData(NSData *data) {
    NSData *resolved = data ?: [NSData data];
    return dispatch_data_create(resolved.bytes,
                                resolved.length,
                                NULL,
                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);
}

static NSData *SHNSDataFromDispatchData(dispatch_data_t content) {
    if (!content) {
        return [NSData data];
    }

    const void *bytes = NULL;
    size_t length = 0;
    dispatch_data_t contiguous = dispatch_data_create_map(content, &bytes, &length);
    (void)contiguous;
    return [NSData dataWithBytes:bytes length:length];
}

static void SHGenerateKeypair(NSData **outPublic, NSData **outSecret) {
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

@interface SSBNetworkShimLinuxTests : XCTestCase
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SSBNetworkShimLinuxTests

- (void)setUp {
    [super setUp];
    self.queue = dispatch_queue_create("com.scuttlebutt.tests.networkshim", DISPATCH_QUEUE_SERIAL);
}

- (nw_parameters_t)defaultTCPParameters {
    return nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, ^(__unused nw_protocol_options_t options) {
    });
}

- (nw_parameters_t)muxParameters {
    nw_parameters_t parameters = [self defaultTCPParameters];
    nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(parameters);
    nw_protocol_stack_prepend_application_protocol(stack, [SSBMuxRPCFramer createOptions]);
    return parameters;
}

- (nw_parameters_t)securityParametersWithLocalSecret:(NSData *)localSecret
                                        remotePublic:(NSData *)remotePublic
                                            asClient:(BOOL)asClient {
    nw_parameters_t parameters = [self defaultTCPParameters];
    nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(parameters);
    nw_protocol_options_t options = [SSBSecurityFramer createOptionsWithLocalSecretKey:localSecret
                                                                         remotePublicKey:remotePublic
                                                                                asClient:asClient];
    nw_protocol_stack_prepend_application_protocol(stack, options);
    return parameters;
}

- (SHLoopbackPair *)establishLoopbackWithListenerParameters:(nw_parameters_t)listenerParameters
                                            clientParameters:(nw_parameters_t)clientParameters
                                                     timeout:(NSTimeInterval)timeout {
    SHLoopbackPair *pair = [[SHLoopbackPair alloc] init];

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReady = [self expectationWithDescription:@"server ready"];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];

    pair.listener = nw_listener_create(listenerParameters ?: [self defaultTCPParameters]);
    nw_listener_set_queue(pair.listener, self.queue);

    nw_listener_set_state_changed_handler(pair.listener, ^(nw_listener_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_listener_state_ready) {
            pair.port = nw_listener_get_port(pair.listener);
            [listenerReady fulfill];
        } else if (state == nw_listener_state_failed) {
            XCTFail(@"Listener failed: %@", error);
        }
    });

    nw_listener_set_new_connection_handler(pair.listener, ^(nw_connection_t connection) {
        pair.server = connection;
        nw_connection_set_queue(connection, self.queue);
        nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
            XCTAssertNil((NSError *)error);
            if (state == nw_connection_state_ready) {
                [serverReady fulfill];
            } else if (state == nw_connection_state_failed) {
                XCTFail(@"Server connection failed: %@", error);
            }
        });
        nw_connection_start(connection);
        [serverAccepted fulfill];
    });

    nw_listener_start(pair.listener);
    [self waitForExpectations:@[listenerReady] timeout:timeout];

    NSString *portString = [NSString stringWithFormat:@"%u", pair.port];
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", portString.UTF8String);
    pair.client = nw_connection_create(endpoint, clientParameters ?: [self defaultTCPParameters]);
    nw_connection_set_queue(pair.client, self.queue);
    nw_connection_set_state_changed_handler(pair.client, ^(nw_connection_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_connection_state_ready) {
            [clientReady fulfill];
        } else if (state == nw_connection_state_failed) {
            XCTFail(@"Client connection failed: %@", error);
        }
    });
    nw_connection_start(pair.client);

    [self waitForExpectations:@[serverAccepted, serverReady, clientReady] timeout:timeout];
    return pair;
}

- (void)tearDownPair:(SHLoopbackPair *)pair {
    if (pair.client) {
        nw_connection_cancel(pair.client);
    }
    if (pair.server) {
        nw_connection_cancel(pair.server);
    }
    if (pair.listener) {
        nw_listener_cancel(pair.listener);
    }
}

- (void)testListenerHonorsLocalEndpointAndProvidesEphemeralPort {
    nw_parameters_t parameters = [self defaultTCPParameters];
    nw_endpoint_t local = nw_endpoint_create_host("127.0.0.1", "0");
    nw_parameters_set_local_endpoint(parameters, local);

    nw_listener_t listener = nw_listener_create(parameters);
    nw_listener_set_queue(listener, self.queue);

    XCTestExpectation *ready = [self expectationWithDescription:@"listener ready"];
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_listener_state_ready) {
            [ready fulfill];
        }
    });

    nw_listener_start(listener);
    [self waitForExpectations:@[ready] timeout:5.0];

    XCTAssertGreaterThan(nw_listener_get_port(listener), 0);
    nw_listener_cancel(listener);
}

- (void)testQueuedDeliveryBeforeReceiveRegistration {
    SHLoopbackPair *pair = [self establishLoopbackWithListenerParameters:nil
                                                         clientParameters:nil
                                                                  timeout:6.0];

    XCTestExpectation *sent = [self expectationWithDescription:@"sent"];
    NSData *payload = [@"queued-before-receive" dataUsingEncoding:NSUTF8StringEncoding];
    nw_connection_send(pair.client,
                       SHDispatchDataFromNSData(payload),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       false,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
        [sent fulfill];
    });
    [self waitForExpectations:@[sent] timeout:2.0];

    XCTestExpectation *delayedReceive = [self expectationWithDescription:@"delayed receive"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), self.queue, ^{
        nw_connection_receive(pair.server, 1, 4096, ^(dispatch_data_t content,
                                                      __unused nw_content_context_t context,
                                                      __unused bool is_complete,
                                                      nw_error_t error) {
            XCTAssertNil((NSError *)error);
            NSData *received = SHNSDataFromDispatchData(content);
            XCTAssertEqualObjects(received, payload);
            [delayedReceive fulfill];
        });
    });

    [self waitForExpectations:@[delayedReceive] timeout:5.0];
    [self tearDownPair:pair];
}

- (void)testReceiveWaitingBeforeDelivery {
    SHLoopbackPair *pair = [self establishLoopbackWithListenerParameters:nil
                                                         clientParameters:nil
                                                                  timeout:6.0];

    XCTestExpectation *received = [self expectationWithDescription:@"received after waiting"];
    NSData *payload = [@"receive-first" dataUsingEncoding:NSUTF8StringEncoding];

    nw_connection_receive(pair.server, 1, 4096, ^(dispatch_data_t content,
                                                  __unused nw_content_context_t context,
                                                  __unused bool is_complete,
                                                  nw_error_t error) {
        XCTAssertNil((NSError *)error);
        NSData *receivedData = SHNSDataFromDispatchData(content);
        XCTAssertEqualObjects(receivedData, payload);
        [received fulfill];
    });

    nw_connection_send(pair.client,
                       SHDispatchDataFromNSData(payload),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       false,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });

    [self waitForExpectations:@[received] timeout:5.0];
    [self tearDownPair:pair];
}

- (void)testStateTransitionsConnectAndCancel {
    nw_listener_t listener = nw_listener_create([self defaultTCPParameters]);
    nw_listener_set_queue(listener, self.queue);

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    __block uint16_t listenerPort = 0;
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_listener_state_ready) {
            listenerPort = nw_listener_get_port(listener);
            [listenerReady fulfill];
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t accepted) {
        nw_connection_set_queue(accepted, self.queue);
        nw_connection_start(accepted);
    });

    nw_listener_start(listener);
    [self waitForExpectations:@[listenerReady] timeout:5.0];

    NSString *portString = [NSString stringWithFormat:@"%u", listenerPort];
    nw_connection_t client = nw_connection_create(nw_endpoint_create_host("127.0.0.1", portString.UTF8String),
                                                  [self defaultTCPParameters]);
    nw_connection_set_queue(client, self.queue);

    NSMutableArray<NSNumber *> *states = [NSMutableArray array];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    XCTestExpectation *clientCancelled = [self expectationWithDescription:@"client cancelled"];
    nw_connection_set_state_changed_handler(client, ^(nw_connection_state_t state, nw_error_t error) {
        if (error) {
            XCTFail(@"Unexpected client error: %@", error);
        }
        [states addObject:@(state)];
        if (state == nw_connection_state_ready) {
            [clientReady fulfill];
        }
        if (state == nw_connection_state_cancelled) {
            [clientCancelled fulfill];
        }
    });

    nw_connection_start(client);
    [self waitForExpectations:@[clientReady] timeout:5.0];

    nw_connection_cancel(client);
    [self waitForExpectations:@[clientCancelled] timeout:5.0];

    NSUInteger preparing = [states indexOfObject:@(nw_connection_state_preparing)];
    NSUInteger waiting = [states indexOfObject:@(nw_connection_state_waiting)];
    NSUInteger ready = [states indexOfObject:@(nw_connection_state_ready)];
    NSUInteger cancelled = [states indexOfObject:@(nw_connection_state_cancelled)];

    XCTAssertNotEqual(preparing, NSNotFound);
    XCTAssertNotEqual(waiting, NSNotFound);
    XCTAssertNotEqual(ready, NSNotFound);
    XCTAssertNotEqual(cancelled, NSNotFound);
    XCTAssertLessThan(preparing, waiting);
    XCTAssertLessThan(waiting, ready);
    XCTAssertLessThan(ready, cancelled);

    nw_listener_cancel(listener);
}

- (void)testMuxFramerParsesMetadataAndZeroLengthBody {
    nw_parameters_t muxListenerParameters = [self muxParameters];
    nw_parameters_t muxClientParameters = [self muxParameters];

    SHLoopbackPair *pair = [self establishLoopbackWithListenerParameters:muxListenerParameters
                                                         clientParameters:muxClientParameters
                                                                  timeout:8.0];

    XCTestExpectation *firstMessage = [self expectationWithDescription:@"first mux message"];
    XCTestExpectation *secondMessage = [self expectationWithDescription:@"zero-length mux message"];

    __block NSInteger receiveCount = 0;
    __block void (^receiveNext)(void);
    receiveNext = ^{
        nw_connection_receive_message(pair.server, ^(dispatch_data_t content,
                                                     nw_content_context_t context,
                                                     __unused bool is_complete,
                                                     nw_error_t error) {
            XCTAssertNil((NSError *)error);

            receiveCount += 1;
            NSData *body = SHNSDataFromDispatchData(content);
            nw_protocol_metadata_t metadata = nw_content_context_copy_protocol_metadata(context, [SSBMuxRPCFramer createDefinition]);
            NSNumber *flags = nw_framer_message_copy_object_value((nw_framer_message_t)metadata, "Flags");
            NSNumber *requestNumber = nw_framer_message_copy_object_value((nw_framer_message_t)metadata, "RequestNumber");

            if (receiveCount == 1) {
                XCTAssertEqualObjects(body, [@"hello-mux" dataUsingEncoding:NSUTF8StringEncoding]);
                XCTAssertEqual(flags.intValue, (int)(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream));
                XCTAssertEqual(requestNumber.intValue, 77);
                [firstMessage fulfill];
                receiveNext();
                return;
            }

            XCTAssertEqual(body.length, (NSUInteger)0);
            XCTAssertEqual(flags.intValue, (int)SSBMuxRPCFlagEndErr);
            XCTAssertEqual(requestNumber.intValue, 88);
            [secondMessage fulfill];
        });
    };

    receiveNext();

    SSBMuxRPCMessage *msg1 = [[SSBMuxRPCMessage alloc] initWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                        requestNumber:77
                                                                 body:[@"hello-mux" dataUsingEncoding:NSUTF8StringEncoding]];
    SSBMuxRPCMessage *msg2 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagEndErr
                                                        requestNumber:88
                                                                 body:[NSData data]];

    nw_connection_send(pair.client,
                       SHDispatchDataFromNSData([msg1 serialize]),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       true,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });

    nw_connection_send(pair.client,
                       SHDispatchDataFromNSData([msg2 serialize]),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       true,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });

    [self waitForExpectations:@[firstMessage, secondMessage] timeout:8.0];
    [self tearDownPair:pair];
}

- (void)testPerConnectionFramerInstanceIsolation {
    nw_listener_t listener = nw_listener_create([self muxParameters]);
    nw_listener_set_queue(listener, self.queue);

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *bothServerMessages = [self expectationWithDescription:@"two isolated messages"];
    bothServerMessages.expectedFulfillmentCount = 2;

    __block uint16_t port = 0;
    __block NSMutableArray *serverConnections = [NSMutableArray array];
    __block NSMutableSet<NSNumber *> *seenReqs = [NSMutableSet set];

    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_listener_state_ready) {
            port = nw_listener_get_port(listener);
            [listenerReady fulfill];
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t accepted) {
        nw_connection_set_queue(accepted, self.queue);
        [serverConnections addObject:accepted];

        nw_connection_set_state_changed_handler(accepted, ^(nw_connection_state_t state, nw_error_t error) {
            XCTAssertNil((NSError *)error);
            if (state == nw_connection_state_ready) {
                nw_connection_receive_message(accepted, ^(dispatch_data_t content,
                                                          nw_content_context_t context,
                                                          __unused bool is_complete,
                                                          nw_error_t receiveError) {
                    XCTAssertNil((NSError *)receiveError);
                    NSData *body = SHNSDataFromDispatchData(content);
                    nw_protocol_metadata_t metadata = nw_content_context_copy_protocol_metadata(context, [SSBMuxRPCFramer createDefinition]);
                    NSNumber *req = nw_framer_message_copy_object_value((nw_framer_message_t)metadata, "RequestNumber");
                    if (req) {
                        [seenReqs addObject:req];
                    }
                    XCTAssertTrue([body isEqualToData:[@"c1" dataUsingEncoding:NSUTF8StringEncoding]] ||
                                  [body isEqualToData:[@"c2" dataUsingEncoding:NSUTF8StringEncoding]]);
                    [bothServerMessages fulfill];
                });
            }
        });

        nw_connection_start(accepted);
    });

    nw_listener_start(listener);
    [self waitForExpectations:@[listenerReady] timeout:6.0];

    NSString *portString = [NSString stringWithFormat:@"%u", port];
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", portString.UTF8String);

    nw_connection_t client1 = nw_connection_create(endpoint, [self muxParameters]);
    nw_connection_t client2 = nw_connection_create(endpoint, [self muxParameters]);
    nw_connection_set_queue(client1, self.queue);
    nw_connection_set_queue(client2, self.queue);

    XCTestExpectation *client1Ready = [self expectationWithDescription:@"client1 ready"];
    XCTestExpectation *client2Ready = [self expectationWithDescription:@"client2 ready"];

    nw_connection_set_state_changed_handler(client1, ^(nw_connection_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_connection_state_ready) {
            [client1Ready fulfill];
        }
    });

    nw_connection_set_state_changed_handler(client2, ^(nw_connection_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_connection_state_ready) {
            [client2Ready fulfill];
        }
    });

    nw_connection_start(client1);
    nw_connection_start(client2);
    [self waitForExpectations:@[client1Ready, client2Ready] timeout:6.0];

    SSBMuxRPCMessage *m1 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeString
                                                      requestNumber:1001
                                                               body:[@"c1" dataUsingEncoding:NSUTF8StringEncoding]];
    SSBMuxRPCMessage *m2 = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON
                                                      requestNumber:2002
                                                               body:[@"c2" dataUsingEncoding:NSUTF8StringEncoding]];

    nw_connection_send(client1, SHDispatchDataFromNSData([m1 serialize]), NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });
    nw_connection_send(client2, SHDispatchDataFromNSData([m2 serialize]), NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });

    [self waitForExpectations:@[bothServerMessages] timeout:8.0];
    XCTAssertEqual(seenReqs.count, (NSUInteger)2);
    XCTAssertTrue([seenReqs containsObject:@(1001)]);
    XCTAssertTrue([seenReqs containsObject:@(2002)]);

    nw_connection_cancel(client1);
    nw_connection_cancel(client2);
    for (nw_connection_t server in serverConnections) {
        nw_connection_cancel(server);
    }
    nw_listener_cancel(listener);
}

- (void)testSecurityFramerHandshakeAndEncryptedRoundTrip {
    NSData *clientPublic = nil;
    NSData *clientSecret = nil;
    NSData *serverPublic = nil;
    NSData *serverSecret = nil;
    SHGenerateKeypair(&clientPublic, &clientSecret);
    SHGenerateKeypair(&serverPublic, &serverSecret);

    nw_parameters_t listenerParameters = [self securityParametersWithLocalSecret:serverSecret
                                                                     remotePublic:nil
                                                                         asClient:NO];
    nw_parameters_t clientParameters = [self securityParametersWithLocalSecret:clientSecret
                                                                   remotePublic:serverPublic
                                                                       asClient:YES];

    SHLoopbackPair *pair = [self establishLoopbackWithListenerParameters:listenerParameters
                                                         clientParameters:clientParameters
                                                                  timeout:10.0];

    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received encrypted payload"];
    XCTestExpectation *clientReceived = [self expectationWithDescription:@"client received encrypted reply"];

    NSData *clientPayload = [@"secret-client-message" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *serverPayload = [@"secret-server-reply" dataUsingEncoding:NSUTF8StringEncoding];

    nw_connection_receive_message(pair.client, ^(dispatch_data_t content,
                                                 __unused nw_content_context_t context,
                                                 __unused bool is_complete,
                                                 nw_error_t error) {
        XCTAssertNil((NSError *)error);
        NSData *received = SHNSDataFromDispatchData(content);
        XCTAssertEqualObjects(received, serverPayload);
        [clientReceived fulfill];
    });

    nw_connection_receive_message(pair.server, ^(dispatch_data_t content,
                                                 __unused nw_content_context_t context,
                                                 __unused bool is_complete,
                                                 nw_error_t error) {
        XCTAssertNil((NSError *)error);
        NSData *received = SHNSDataFromDispatchData(content);
        XCTAssertEqualObjects(received, clientPayload);
        [serverReceived fulfill];

        nw_connection_send(pair.server,
                           SHDispatchDataFromNSData(serverPayload),
                           NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                           true,
                           ^(nw_error_t sendError) {
            XCTAssertNil((NSError *)sendError);
        });
    });

    nw_connection_send(pair.client,
                       SHDispatchDataFromNSData(clientPayload),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       true,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
    });

    [self waitForExpectations:@[serverReceived, clientReceived] timeout:12.0];
    [self tearDownPair:pair];
}

- (void)testSecurityFramerQueuesSendBeforeConnectionReady {
    NSData *clientPublic = nil;
    NSData *clientSecret = nil;
    NSData *serverPublic = nil;
    NSData *serverSecret = nil;
    SHGenerateKeypair(&clientPublic, &clientSecret);
    SHGenerateKeypair(&serverPublic, &serverSecret);

    nw_parameters_t listenerParameters = [self securityParametersWithLocalSecret:serverSecret
                                                                     remotePublic:nil
                                                                         asClient:NO];
    nw_parameters_t clientParameters = [self securityParametersWithLocalSecret:clientSecret
                                                                   remotePublic:serverPublic
                                                                       asClient:YES];

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReady = [self expectationWithDescription:@"server ready"];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    XCTestExpectation *sendCompleted = [self expectationWithDescription:@"queued send completed"];
    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received queued payload"];

    __block uint16_t port = 0;
    __block nw_connection_t serverConnection = nil;
    __block BOOL clientIsReady = NO;

    nw_listener_t listener = nw_listener_create(listenerParameters);
    nw_listener_set_queue(listener, self.queue);
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_listener_state_ready) {
            port = nw_listener_get_port(listener);
            [listenerReady fulfill];
        }
    });

    NSData *payload = [@"queued-before-security-ready" dataUsingEncoding:NSUTF8StringEncoding];

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t accepted) {
        serverConnection = accepted;
        nw_connection_set_queue(accepted, self.queue);
        nw_connection_set_state_changed_handler(accepted, ^(nw_connection_state_t state, nw_error_t error) {
            XCTAssertNil((NSError *)error);
            if (state == nw_connection_state_ready) {
                [serverReady fulfill];
                nw_connection_receive_message(accepted, ^(dispatch_data_t content,
                                                          __unused nw_content_context_t context,
                                                          __unused bool is_complete,
                                                          nw_error_t receiveError) {
                    XCTAssertNil((NSError *)receiveError);
                    XCTAssertEqualObjects(SHNSDataFromDispatchData(content), payload);
                    [serverReceived fulfill];
                });
            }
        });
        nw_connection_start(accepted);
        [serverAccepted fulfill];
    });

    nw_listener_start(listener);
    [self waitForExpectations:@[listenerReady] timeout:6.0];

    NSString *portString = [NSString stringWithFormat:@"%u", port];
    nw_connection_t client = nw_connection_create(nw_endpoint_create_host("127.0.0.1", portString.UTF8String),
                                                  clientParameters);
    nw_connection_set_queue(client, self.queue);
    nw_connection_set_state_changed_handler(client, ^(nw_connection_state_t state, nw_error_t error) {
        XCTAssertNil((NSError *)error);
        if (state == nw_connection_state_ready) {
            clientIsReady = YES;
            [clientReady fulfill];
        }
    });

    nw_connection_start(client);
    nw_connection_send(client,
                       SHDispatchDataFromNSData(payload),
                       NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                       true,
                       ^(nw_error_t error) {
        XCTAssertNil((NSError *)error);
        XCTAssertTrue(clientIsReady);
        [sendCompleted fulfill];
    });

    [self waitForExpectations:@[serverAccepted, serverReady, clientReady, sendCompleted, serverReceived] timeout:12.0];

    nw_connection_cancel(client);
    if (serverConnection) {
        nw_connection_cancel(serverConnection);
    }
    nw_listener_cancel(listener);
}

@end

#else

@interface SSBNetworkShimLinuxTests : XCTestCase
@end

@implementation SSBNetworkShimLinuxTests

- (void)testLinuxOnlyPlaceholder {
    XCTAssertTrue(YES);
}

@end

#endif
