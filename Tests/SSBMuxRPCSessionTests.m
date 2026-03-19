#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPCSession.h"

@interface SSBMuxRPCSession (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *pendingRequests;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
@end

@interface SSBMuxRPCSessionTests : XCTestCase
@end

@implementation SSBMuxRPCSessionTests

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

@end
