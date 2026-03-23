#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPCSession.h"

@interface SSBMuxRPCSession (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *pendingRequests;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeIncomingRequests;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
- (id _Nullable)parsedBodyForMessage:(SSBMuxRPCMessage *)message;
- (nullable NSError *)errorFromEndPayload:(id _Nullable)payload;
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

// MARK: - parsedBodyForMessage edge cases

- (void)testParsedBodyJSONWithInvalidBodyReturnsNil {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSData *notJSON = [@"not valid json {{{{" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:1 body:notJSON];
    id result = [session parsedBodyForMessage:msg];
    XCTAssertNil(result, @"Invalid JSON body should return nil");
}

- (void)testParsedBodyJSONWithEmptyBodyReturnsRawData {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSData *empty = [NSData data];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:1 body:empty];
    id result = [session parsedBodyForMessage:msg];
    // length == 0, so skips JSON parse and falls through to return message.body
    XCTAssertEqualObjects(result, empty);
}

- (void)testParsedBodyStringFlagWithNonEmptyBodyReturnsString {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSData *body = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeString requestNumber:1 body:body];
    id result = [session parsedBodyForMessage:msg];
    XCTAssertEqualObjects(result, @"hello");
}

- (void)testParsedBodyStringFlagWithEmptyBodyReturnsRawData {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSData *empty = [NSData data];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeString requestNumber:1 body:empty];
    id result = [session parsedBodyForMessage:msg];
    XCTAssertEqualObjects(result, empty);
}

- (void)testParsedBodyNoTypeFlagReturnsBinaryData {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSData *body = [@"binary" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:0 requestNumber:1 body:body];
    id result = [session parsedBodyForMessage:msg];
    XCTAssertEqualObjects(result, body);
}

// MARK: - errorFromEndPayload edge cases

- (void)testErrorFromEndPayloadWithNilReturnsNil {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTAssertNil([session errorFromEndPayload:nil]);
}

- (void)testErrorFromEndPayloadWithDictNoErrorNameReturnsNil {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSDictionary *d = @{@"name": @"Success", @"message": @"ok"};
    XCTAssertNil([session errorFromEndPayload:d]);
}

- (void)testErrorFromEndPayloadWithDictContainingErrorReturnsNSError {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSDictionary *d = @{@"name": @"TypeError", @"message": @"bad type"};
    NSError *err = [session errorFromEndPayload:d];
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, @"SSBMuxRPC");
    XCTAssertTrue([err.localizedDescription containsString:@"bad type"]);
}

- (void)testErrorFromEndPayloadWithStringContainingErrorReturnsNSError {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSError *err = [session errorFromEndPayload:@"Error: something went wrong"];
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, @"SSBMuxRPC");
}

- (void)testErrorFromEndPayloadWithStringNotContainingErrorReturnsNil {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSError *err = [session errorFromEndPayload:@"operation complete"];
    XCTAssertNil(err);
}

- (void)testErrorFromEndPayloadWithDictMissingMessageKeyUsesDefault {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    NSDictionary *d = @{@"name": @"AppError"};
    NSError *err = [session errorFromEndPayload:d];
    XCTAssertNotNil(err);
    XCTAssertTrue([err.localizedDescription containsString:@"Unknown RPC Error"]);
}

// MARK: - sendData edge cases

- (void)testSendDataWithNSDataSendsRawBytes {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    NSData *data = [@"raw" dataUsingEncoding:NSUTF8StringEncoding];
    [session sendData:data forRequest:5 isEnd:NO];

    XCTAssertNotNil(sent);
    XCTAssertEqualObjects(sent.body, data);
    XCTAssertEqual(sent.requestNumber, 5);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagStream) != 0);
    XCTAssertFalse((sent.flags & SSBMuxRPCFlagEndErr) != 0);
}

- (void)testSendDataWithNSStringSetsStringFlag {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    [session sendData:@"hello-string" forRequest:3 isEnd:NO];

    XCTAssertNotNil(sent);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagTypeString) != 0);
    XCTAssertEqualObjects([[NSString alloc] initWithData:sent.body encoding:NSUTF8StringEncoding], @"hello-string");
}

- (void)testSendDataWithDictionarySetsJSONFlag {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    [session sendData:@{@"key": @"value"} forRequest:7 isEnd:NO];

    XCTAssertNotNil(sent);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagTypeJSON) != 0);
}

- (void)testSendDataWithIsEndSetsEndErrFlag {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    [session sendData:nil forRequest:9 isEnd:YES];

    XCTAssertNotNil(sent);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagEndErr) != 0);
}

// MARK: - sendRequest edge cases

- (void)testSendRequestWithoutSendMessageBlockDoesNotCrash {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    // No sendMessageBlock set — should not crash
    int32_t reqID = [session sendRequest:@[@"whoami"] args:@[] type:@"async" completion:nil];
    XCTAssertGreaterThan(reqID, 0);
}

- (void)testSendRequestWithDuplexTypeSetsStreamFlag {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    [session sendRequest:@[@"tunnel", @"connect"] args:@[] type:@"duplex" completion:nil];

    XCTAssertNotNil(sent);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagStream) != 0);
}

- (void)testSendRequestWithSinkTypeSetsStreamFlag {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    __block SSBMuxRPCMessage *sent = nil;
    session.sendMessageBlock = ^(SSBMuxRPCMessage *m) { sent = m; };

    [session sendRequest:@[@"blobs", @"add"] args:@[] type:@"sink" completion:nil];

    XCTAssertNotNil(sent);
    XCTAssertTrue((sent.flags & SSBMuxRPCFlagStream) != 0);
}

// MARK: - handleIncomingMessage edge cases

- (void)testHandleIncomingPositiveReqIDResponseTriggersCallback {
    // A positive reqID response (not negated) should still match a pending request with the same ID
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *exp = [self expectationWithDescription:@"callback fired"];
    __block id capturedPayload = nil;

    int32_t reqID = [session sendRequest:@[@"test"] args:@[] type:@"async" completion:^(id _Nullable r, NSError *_Nullable e) {
        capturedPayload = r;
        [exp fulfill];
    }];

    // Respond with the positive reqID (same value, not negated)
    SSBMuxRPCMessage *resp = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr)
                                           requestNumber:reqID
                                                  object:@{@"result": @YES}];
    [session handleIncomingMessage:resp];
    [self waitForExpectations:@[exp] timeout:2.0];
    XCTAssertNotNil(capturedPayload);
}

- (void)testHandleIncomingMessageWithNoCallbackAndNoReceiveBlockDoesNotCrash {
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    // No pending request, no receiveRequestBlock — should not crash
    SSBMuxRPCMessage *msg = [self jsonMessageWithFlags:SSBMuxRPCFlagTypeJSON requestNumber:99 object:@{}];
    XCTAssertNoThrow([session handleIncomingMessage:msg]);
}

- (void)testStreamEndWithNonTrueValueFiresCallbackOnce {
    // isEndErr && isStream && parsedBody != @YES → fires callback with data then removes pending
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *exp = [self expectationWithDescription:@"stream final value callback"];
    __block NSInteger count = 0;
    __block id captured = nil;

    int32_t reqID = [session sendRequest:@[@"room", @"attendants"] args:@[] type:@"source" completion:^(id _Nullable r, NSError *_Nullable e) {
        count++;
        captured = r;
        [exp fulfill];
    }];

    // End with a non-@YES payload (actual final data value)
    SSBMuxRPCMessage *end = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream | SSBMuxRPCFlagEndErr)
                                          requestNumber:-reqID
                                                 object:@{@"final": @"value"}];
    [session handleIncomingMessage:end];
    [self waitForExpectations:@[exp] timeout:2.0];
    XCTAssertEqual(count, 1);
    XCTAssertEqualObjects(captured[@"final"], @"value");
}

- (void)testAsyncRequest_nonStreamNonEndErr_response_cleansUpPendingRequest {
    // A non-stream, non-endErr response to an async request hits the else branch
    // (lines 239-244) which calls the callback and removes the pending request.
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *exp = [self expectationWithDescription:@"async callback"];
    __block id receivedResult = nil;

    int32_t reqID = [session sendRequest:@[@"whoami"]
                                    args:@[]
                                    type:@"async"
                              completion:^(id _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        receivedResult = response;
        [exp fulfill];
    }];

    SSBMuxRPCMessage *response = [self jsonMessageWithFlags:SSBMuxRPCFlagTypeJSON
                                              requestNumber:-reqID
                                                     object:@{@"id": @"@peer.ed25519"}];
    [session handleIncomingMessage:response];

    [self waitForExpectations:@[exp] timeout:2.0];
    XCTAssertEqualObjects(receivedResult[@"id"], @"@peer.ed25519");

    __block BOOL cleaned = NO;
    dispatch_sync(session.accessQueue, ^{
        cleaned = (session.pendingRequests[@(reqID)] == nil);
    });
    XCTAssertTrue(cleaned, @"Pending request must be removed after async non-stream response");
}

- (void)testStreamEndFiresEndOfStreamCallbackAndClearsPendingRequest {
    // A clean stream end (@YES sentinel) must:
    // 1. Fire the data callback once with the real payload
    // 2. Fire the callback again with (nil, nil) to signal end-of-stream to consumers
    // 3. Clear the pending request so no further callbacks fire
    SSBMuxRPCSession *session = [[SSBMuxRPCSession alloc] init];
    XCTestExpectation *dataExpectation = [self expectationWithDescription:@"stream data callback"];
    XCTestExpectation *endExpectation = [self expectationWithDescription:@"end-of-stream callback"];

    __block NSInteger callbackCount = 0;
    __block id capturedResponse = nil;

    int32_t reqID = [session sendRequest:@[@"room", @"attendants"] args:@[] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error);
        callbackCount += 1;
        if (callbackCount == 1) {
            capturedResponse = response;
            [dataExpectation fulfill];
        } else {
            XCTAssertNil(response, @"End-of-stream callback must deliver nil response");
            [endExpectation fulfill];
        }
    }];

    SSBMuxRPCMessage *dataMessage = [self jsonMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                 requestNumber:-reqID
                                                        object:@{ @"type": @"joined", @"id": @"@peer.ed25519" }];
    [session handleIncomingMessage:dataMessage];

    SSBMuxRPCMessage *endMessage = [self stringMessageWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream | SSBMuxRPCFlagEndErr)
                                                  requestNumber:-reqID
                                                         string:@"true"];
    [session handleIncomingMessage:endMessage];

    [self waitForExpectations:@[dataExpectation, endExpectation] timeout:2.0];
    XCTAssertEqual(callbackCount, 2);
    XCTAssertEqualObjects(capturedResponse[@"id"], @"@peer.ed25519");

    __block BOOL removed = NO;
    dispatch_sync(session.accessQueue, ^{
        removed = (session.pendingRequests[@(reqID)] == nil);
    });
    XCTAssertTrue(removed, @"Stream end must clear the pending request");
}

@end
