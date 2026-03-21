#import <XCTest/XCTest.h>
#import "../Sources/SSBMessage.h"

@interface SSBMessageTests : XCTestCase
@end

@implementation SSBMessageTests

- (void)testSSBMessageDefaultInitialization {
    SSBMessage *msg = [[SSBMessage alloc] init];
    XCTAssertNotNil(msg);
    XCTAssertNil(msg.key);
    XCTAssertNil(msg.author);
    XCTAssertEqual(msg.sequence, 0);
    XCTAssertNil(msg.previousKey);
    XCTAssertEqual(msg.claimedTimestamp, 0);
    XCTAssertEqual(msg.receivedAt, 0);
    XCTAssertFalse(msg.isPrivate);
    XCTAssertNil(msg.contentType);
    XCTAssertNil(msg.valueJSON);
    XCTAssertNil(msg.content);
    // Defaults to SSBBFEFeedFormatClassic (0)
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatClassic);
}

- (void)testSSBMessagePropertyAssignment {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = @"%testHash";
    msg.author = @"@testPubKey";
    msg.sequence = 10;
    msg.previousKey = @"%prevHash";
    msg.claimedTimestamp = 1234567890;
    msg.receivedAt = 1234567891;
    msg.isPrivate = YES;
    msg.contentType = @"post";
    msg.valueJSON = [@"{\"test\": true}" dataUsingEncoding:NSUTF8StringEncoding];
    msg.content = @{@"test": @YES};
    msg.feedFormat = SSBBFEFeedFormatButtwooV1;

    XCTAssertEqualObjects(msg.key, @"%testHash");
    XCTAssertEqualObjects(msg.author, @"@testPubKey");
    XCTAssertEqual(msg.sequence, 10);
    XCTAssertEqualObjects(msg.previousKey, @"%prevHash");
    XCTAssertEqual(msg.claimedTimestamp, 1234567890);
    XCTAssertEqual(msg.receivedAt, 1234567891);
    XCTAssertTrue(msg.isPrivate);
    XCTAssertEqualObjects(msg.contentType, @"post");
    XCTAssertNotNil(msg.valueJSON);
    XCTAssertEqualObjects(msg.content[@"test"], @YES);
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatButtwooV1);
}

- (void)testSSBFeedStateDefaultInitialization {
    SSBFeedState *state = [[SSBFeedState alloc] init];
    XCTAssertNotNil(state);
    XCTAssertNil(state.author);
    XCTAssertEqual(state.maxSequence, 0);
    XCTAssertNil(state.maxKey);
    XCTAssertEqual(state.feedFormat, SSBBFEFeedFormatClassic);
}

- (void)testSSBFeedStatePropertyAssignment {
    SSBFeedState *state = [[SSBFeedState alloc] init];
    state.author = @"@testPubKey";
    state.maxSequence = 55;
    state.maxKey = @"%testKey";
    state.feedFormat = SSBBFEFeedFormatBamboo;

    XCTAssertEqualObjects(state.author, @"@testPubKey");
    XCTAssertEqual(state.maxSequence, 55);
    XCTAssertEqualObjects(state.maxKey, @"%testKey");
    XCTAssertEqual(state.feedFormat, SSBBFEFeedFormatBamboo);
}

@end
