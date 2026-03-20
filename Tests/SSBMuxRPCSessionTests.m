#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPCSession.h"

@interface SSBMuxRPCSession (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *pendingRequests;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeIncomingRequests;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
@end

@interface SSBMuxRPCSessionTests : XCTestCase
@end

@implementation SSBMuxRPCSessionTests

- (SSBMuxRPCMessage *)jsonMessageWithFlags:(SSBMuxRPCFlags)flags
                             requestNumber:(int32_t)requestNumber
                                    object:(id)object {
    NSData *body = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingFragmentsAllowed error:nil];
    XCTAssertNotNil(body);
    return [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:requestNumber body:body];
}

- (SSBMuxRPCMessage *)stringMessageWithFlags:(SSBMuxRPCFlags)flags
                               requestNumber:(int32_t)requestNumber
                                      string:(NSString *)string {
    NSData *body = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:requestNumber body:body];
}

- (void)testSendRequestRegistersCallbackBeforeMessageIsSent {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"sendMessageBlock invoked"];

    __block BOOL callbackRegistered = NO;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
        callbackRegistered = (session.pendingRequests[@(message.requestNumber)] != nil);
        [expectation fulfill];
    };

    dispatch_sync(session.accessQueue, ^{
        int32_t reqID = [session sendRequest:@[@"room", @"attendants"]
                                        args:@[]
                                        type:@"source"
                                  completion:^(id _Nullable response, NSError * _Nullable error) {
                                      (void)response;
                                      (void)error;
                                  }];
        XCTAssertGreaterThan(reqID, 0);
    });

    [self waitForExpectations:@[expectation] timeout:2.0];
    XCTAssertTrue(callbackRegistered, @"pendingRequests should be populated before sendMessageBlock runs");
}

- (void)testNegativeResponseRemovesPositivePendingRequest {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"callback invoked"];

    __block int32_t reqID = 0;
    reqID = [session sendRequest:@[@"whoami"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertTrue([response isKindOfClass:[NSDictionary class]]);
        [callbackExpectation fulfill];
    }];
    XCTAssertGreaterThan(reqID, 0);

    SSBMuxRPCMessage *response = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)
                                              requestNumber:-reqID
                                                     object:@{@"id": @"@peer.ed25519"}];
    [session handleIncomingMessage:response];

    [self waitForExpectations:@[callbackExpectation] timeout:2.0];
    __block BOOL pendingEmpty = NO;
    dispatch_sync(session.accessQueue, ^{
        pendingEmpty = (session.pendingRequests[@(reqID)] == nil);
    });
    XCTAssertTrue(pendingEmpty, @"Negative response IDs must clear the positive pending request key");
}

- (void)testIncomingRequestEnvelopeWithCollidingIDDoesNotHitPendingCallback {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block int callbackCount = 0;
    __block int receiveRequestCount = 0;

    int32_t outgoingReqID = [session sendRequest:@[@"tunnel", @"connect"]
                                            args:@[@{@"target": @"@example.ed25519"}]
                                            type:@"duplex"
                                      completion:^(id _Nullable response, NSError * _Nullable error) {
                                          (void)response;
                                          (void)error;
                                          callbackCount += 1;
                                      }];
    XCTAssertEqual(outgoingReqID, 1);

    session.receiveRequestBlock = ^(id _Nullable payload, int32_t requestID, uint8_t flags) {
        (void)payload;
        (void)flags;
        if (requestID == outgoingReqID) {
            receiveRequestCount += 1;
        }
    };

    SSBMuxRPCMessage *requestEnvelope = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                     requestNumber:outgoingReqID
                                                            object:@{
                                                                @"name": @[@"ebt", @"replicate"],
                                                                @"args": @[@{@"version": @3}],
                                                                @"type": @"duplex"
                                                            }];
    [session handleIncomingMessage:requestEnvelope];

    SSBMuxRPCMessage *requestChunk = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                  requestNumber:outgoingReqID
                                                         object:@{@"@feed.ed25519": @1}];
    [session handleIncomingMessage:requestChunk];

    SSBMuxRPCMessage *requestEnd = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream | SSBMuxRPCFlagEndErr)
                                                requestNumber:outgoingReqID
                                                       object:@YES];
    [session handleIncomingMessage:requestEnd];

    XCTAssertEqual(callbackCount, 0, @"Inbound request traffic must not be routed to a colliding pending callback");
    XCTAssertEqual(receiveRequestCount, 3, @"Envelope, chunk, and end should all dispatch to receiveRequestBlock");

    __block BOOL incomingCleared = NO;
    dispatch_sync(session.accessQueue, ^{
        incomingCleared = ![session.activeIncomingRequests containsObject:@(outgoingReqID)];
    });
    XCTAssertTrue(incomingCleared, @"Incoming request tracking should clear when stream ends");
}

- (void)testEndErrTrueStringOnAsyncRequestReturnsSuccessValue {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"callback invoked"];

    __block id capturedResponse = nil;
    __block NSError *capturedError = nil;

    int32_t reqID = [session sendRequest:@[@"manifest"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        capturedResponse = response;
        capturedError = error;
        [callbackExpectation fulfill];
    }];

    SSBMuxRPCMessage *response = [self stringMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)
                                                requestNumber:-reqID
                                                       string:@"true"];
    [session handleIncomingMessage:response];

    [self waitForExpectations:@[callbackExpectation] timeout:2.0];
    XCTAssertNil(capturedError);
    XCTAssertEqualObjects(capturedResponse, @YES);
}

- (void)testEndErrSuccessObjectOnAsyncRequestReturnsObject {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"callback invoked"];

    __block NSDictionary *capturedResponse = nil;
    __block NSError *capturedError = nil;

    int32_t reqID = [session sendRequest:@[@"whoami"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        capturedResponse = response;
        capturedError = error;
        [callbackExpectation fulfill];
    }];

    NSDictionary *successObject = @{
        @"ok": @YES,
        @"status": @"success"
    };
    SSBMuxRPCMessage *response = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)
                                              requestNumber:-reqID
                                                     object:successObject];
    [session handleIncomingMessage:response];

    [self waitForExpectations:@[callbackExpectation] timeout:2.0];
    XCTAssertNil(capturedError);
    XCTAssertEqualObjects(capturedResponse[@"status"], @"success");
}

- (void)testEndErrErrorObjectReturnsNSErrorAndClearsPendingRequest {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *callbackExpectation = [self expectationWithDescription:@"callback invoked"];

    __block NSError *capturedError = nil;
    int32_t reqID = [session sendRequest:@[@"tunnel", @"ping"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(response);
        capturedError = error;
        [callbackExpectation fulfill];
    }];

    SSBMuxRPCMessage *response = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)
                                              requestNumber:-reqID
                                                     object:@{
                                                         @"name": @"PermissionError",
                                                         @"message": @"Access denied"
                                                     }];
    [session handleIncomingMessage:response];

    [self waitForExpectations:@[callbackExpectation] timeout:2.0];
    XCTAssertNotNil(capturedError);
    XCTAssertTrue([capturedError.localizedDescription containsString:@"Access denied"]);

    __block BOOL removed = NO;
    dispatch_sync(session.accessQueue, ^{
        removed = (session.pendingRequests[@(reqID)] == nil);
    });
    XCTAssertTrue(removed, @"Error responses must clear the pending request");
}

- (void)testStreamEndTrueClearsPendingRequestWithoutEmittingExtraPayload {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *dataExpectation = [self expectationWithDescription:@"stream data callback"];

    __block NSInteger callbackCount = 0;
    __block id capturedResponse = nil;

    int32_t reqID = [session sendRequest:@[@"room", @"attendants"] args:@[] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        callbackCount += 1;
        capturedResponse = response;
        [dataExpectation fulfill];
    }];

    SSBMuxRPCMessage *dataMessage = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                 requestNumber:-reqID
                                                        object:@{ @"type": @"joined", @"id": @"@peer.ed25519" }];
    [session handleIncomingMessage:dataMessage];

    SSBMuxRPCMessage *endMessage = [self stringMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream | SSBMuxRPCFlagEndErr)
                                                  requestNumber:-reqID
                                                         string:@"true"];
    [session handleIncomingMessage:endMessage];

    [self waitForExpectations:@[dataExpectation] timeout:2.0];
    XCTAssertEqual(callbackCount, 1);
    XCTAssertEqualObjects(capturedResponse[@"id"], @"@peer.ed25519");

    __block BOOL removed = NO;
    dispatch_sync(session.accessQueue, ^{
        removed = (session.pendingRequests[@(reqID)] == nil);
    });
    XCTAssertTrue(removed, @"Stream end markers must clear the pending request");
}

@end
