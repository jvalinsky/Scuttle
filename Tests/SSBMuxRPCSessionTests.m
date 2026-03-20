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

@end
