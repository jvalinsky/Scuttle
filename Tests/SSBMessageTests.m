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

// MARK: - Nullable properties

- (void)testPreviousKeyCanBeNilledAfterSet {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.previousKey = @"%prev.sha256";
    msg.previousKey = nil;
    XCTAssertNil(msg.previousKey);
}

- (void)testContentTypeCanBeNilledAfterSet {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.contentType = @"post";
    msg.contentType = nil;
    XCTAssertNil(msg.contentType);
}

- (void)testContentCanBeNilledAfterSet {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.content = @{@"type": @"post"};
    msg.content = nil;
    XCTAssertNil(msg.content);
}

- (void)testFeedStateMaxKeyCanBeNilledAfterSet {
    SSBFeedState *state = [[SSBFeedState alloc] init];
    state.maxKey = @"%latest.sha256";
    state.maxKey = nil;
    XCTAssertNil(state.maxKey);
}

// MARK: - All feed format enum values

- (void)testAllFeedFormatValues {
    SSBMessage *msg = [[SSBMessage alloc] init];

    msg.feedFormat = SSBBFEFeedFormatClassic;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatClassic);

    msg.feedFormat = SSBBFEFeedFormatGabbygroveV1;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatGabbygroveV1);

    msg.feedFormat = SSBBFEFeedFormatBamboo;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatBamboo);

    msg.feedFormat = SSBBFEFeedFormatBendybuttV1;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatBendybuttV1);

    msg.feedFormat = SSBBFEFeedFormatButtwooV1;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatButtwooV1);

    msg.feedFormat = SSBBFEFeedFormatIndexedV1;
    XCTAssertEqual(msg.feedFormat, SSBBFEFeedFormatIndexedV1);
}

// MARK: - Edge cases

- (void)testFirstMessageHasNilPreviousKey {
    // Sequence 1 messages have no previous key
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.sequence = 1;
    msg.previousKey = nil;
    XCTAssertEqual(msg.sequence, 1);
    XCTAssertNil(msg.previousKey);
}

- (void)testLargeTimestampPrecision {
    // int64_t must hold millisecond timestamps well beyond 2038
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.claimedTimestamp = 9999999999999LL;
    msg.receivedAt       = 9999999999999LL;
    XCTAssertEqual(msg.claimedTimestamp, 9999999999999LL);
    XCTAssertEqual(msg.receivedAt,       9999999999999LL);
}

- (void)testValueJSONRoundtrip {
    NSString *jsonString = @"{\"type\":\"post\",\"text\":\"hello world\"}";
    NSData *json = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.valueJSON = json;
    NSString *recovered = [[NSString alloc] initWithData:msg.valueJSON encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(recovered, jsonString);
}

- (void)testFeedStateFeedFormatAllValues {
    SSBFeedState *state = [[SSBFeedState alloc] init];

    state.feedFormat = SSBBFEFeedFormatClassic;
    XCTAssertEqual(state.feedFormat, SSBBFEFeedFormatClassic);

    state.feedFormat = SSBBFEFeedFormatBendybuttV1;
    XCTAssertEqual(state.feedFormat, SSBBFEFeedFormatBendybuttV1);

    state.feedFormat = SSBBFEFeedFormatIndexedV1;
    XCTAssertEqual(state.feedFormat, SSBBFEFeedFormatIndexedV1);
}

@end
