#import <XCTest/XCTest.h>
#import "RoomInviteHandler.h"
#import "RoomStorage.h"

// Expose private methods for testing
@interface RoomInviteHandler (Test)
+ (void)parseAndCompleteWithMSA:(NSString *)msa 
                         invite:(NSString *)invite 
                        localId:(NSString *)localId 
                     completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion;
@end

@interface RoomInviteHandlerTests : XCTestCase
@end

@implementation RoomInviteHandlerTests

- (void)testParseAndCompleteWithValidMSA {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"net:example.com:8008~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
    
    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"test-token" localId:@"@me" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNotNil(config);
        XCTAssertNil(error);
        XCTAssertEqualObjects(config.host, @"example.com");
        XCTAssertEqual(config.port, 8008);
        XCTAssertEqualObjects(config.inviteToken, @"test-token");
        XCTAssertTrue(config.usedHTTPInvite);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testParseAndCompleteWithInvalidMSA {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"invalid-msa";

    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"test-token" localId:@"@me" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNil(config);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, -6);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testParseAndCompleteWithMSA_invalidNetworkPart {
    // net part has only 2 colon-separated components (missing port), triggers < 3 branch
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"net:example.com~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";

    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"tok" localId:@"@me" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNil(config);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, -6);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testParseAndCompleteWithMSA_invalidPubKey {
    // Valid structure but pubkey is not valid base64 → fails to decode → else branch
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"net:example.com:8008~shs:!!!not-base64!!!";

    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"tok" localId:@"@me" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNil(config);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, -6);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testParseAndCompleteWithMSA_portZero {
    // Valid pubkey but port = 0 → condition (port > 0) fails → else branch
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"net:example.com:0~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";

    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"tok" localId:@"@me" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNil(config);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, -6);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testParseAndCompleteWithMSA_setsHTTPInviteFields {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
    NSString *msa = @"net:room.test:8008~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";

    [RoomInviteHandler parseAndCompleteWithMSA:msa invite:@"myToken" localId:@"@alice.ed25519" completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
        XCTAssertNotNil(config);
        XCTAssertEqualObjects(config.httpInviteClaimIdentity, @"@alice.ed25519");
        XCTAssertTrue(config.usedHTTPInvite);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
