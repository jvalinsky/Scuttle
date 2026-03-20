#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBTransport.h>

@interface SSBTransportTests : XCTestCase
@end

@implementation SSBTransportTests

- (void)testDefaultBackendMatchesPlatform {
    id<SSBTransportBackend> backend = [SSBTransport defaultBackend];
#ifdef __APPLE__
    XCTAssertTrue([backend isKindOfClass:[SSBAppleTransportBackend class]]);
#else
    XCTAssertTrue([backend isKindOfClass:[SSBLinuxTransportBackend class]]);
#endif
}

- (void)testRawLoopbackConnectionRoundTripsData {
    id<SSBTransportBackend> backend = [SSBTransport defaultBackend];
    dispatch_queue_t queue = dispatch_queue_create("com.scuttlebutt.tests.transport", DISPATCH_QUEUE_SERIAL);

    XCTestExpectation *listenerReady = [self expectationWithDescription:@"listener ready"];
    XCTestExpectation *serverAccepted = [self expectationWithDescription:@"server accepted"];
    XCTestExpectation *serverReceived = [self expectationWithDescription:@"server received ping"];
    XCTestExpectation *clientReady = [self expectationWithDescription:@"client ready"];
    XCTestExpectation *clientReceived = [self expectationWithDescription:@"client received pong"];

    id<SSBTransportListener> listener = [backend listenerOnEndpoint:[SSBTransportEndpoint endpointWithHost:@"127.0.0.1" port:0]
                                                              queue:queue];

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
                                                                          queue:queue];
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

@end
