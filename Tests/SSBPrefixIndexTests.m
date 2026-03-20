#import <XCTest/XCTest.h>

#import <SSBNetwork/SSBPrefixIndex.h>

@interface SSBPrefixIndexTests : XCTestCase
@end

@implementation SSBPrefixIndexTests

- (void)testAddAndFilterBitsetKeepsOnlyMatchingHashes {
    SSBPrefixIndex *index = [[SSBPrefixIndex alloc] initWithCapacity:4];
    [index addValue:@"alice" atSequence:0];
    [index addValue:@"bob" atSequence:1];
    [index addValue:@"alice" atSequence:2];
    [index addValue:@"carol" atSequence:3];

    SSBBitset *bitset = [[SSBBitset alloc] initWithCapacity:4];
    [bitset setBitAtIndex:0];
    [bitset setBitAtIndex:1];
    [bitset setBitAtIndex:2];
    [bitset setBitAtIndex:3];

    [index filterBitset:bitset withValue:@"alice"];

    XCTAssertTrue([bitset isBitSetAtIndex:0]);
    XCTAssertFalse([bitset isBitSetAtIndex:1]);
    XCTAssertTrue([bitset isBitSetAtIndex:2]);
    XCTAssertFalse([bitset isBitSetAtIndex:3]);
}

- (void)testAddOutOfBoundsSequenceDoesNotModifyBuffer {
    SSBPrefixIndex *index = [[SSBPrefixIndex alloc] initWithCapacity:2];
    NSData *before = index.data;

    [index addValue:@"alice" atSequence:5];
    NSData *after = index.data;

    XCTAssertEqualObjects(before, after);
}

- (void)testFilterUsesMinCapacityBetweenIndexAndBitset {
    SSBPrefixIndex *index = [[SSBPrefixIndex alloc] initWithCapacity:2];
    [index addValue:@"alice" atSequence:0];
    [index addValue:@"bob" atSequence:1];

    SSBBitset *bitset = [[SSBBitset alloc] initWithCapacity:4];
    [bitset setBitAtIndex:0];
    [bitset setBitAtIndex:1];
    [bitset setBitAtIndex:2];
    [bitset setBitAtIndex:3];

    [index filterBitset:bitset withValue:@"alice"];

    XCTAssertTrue([bitset isBitSetAtIndex:0]);
    XCTAssertFalse([bitset isBitSetAtIndex:1]);
    XCTAssertTrue([bitset isBitSetAtIndex:2]);
    XCTAssertTrue([bitset isBitSetAtIndex:3]);
}

- (void)testInitWithDataRoundTripPersistsStoredHashes {
    SSBPrefixIndex *original = [[SSBPrefixIndex alloc] initWithCapacity:3];
    [original addValue:@"alice" atSequence:0];
    [original addValue:@"bob" atSequence:1];
    [original addValue:@"carol" atSequence:2];

    NSData *archived = original.data;
    SSBPrefixIndex *restored = [[SSBPrefixIndex alloc] initWithData:archived];

    SSBBitset *bitset = [[SSBBitset alloc] initWithCapacity:3];
    [bitset setBitAtIndex:0];
    [bitset setBitAtIndex:1];
    [bitset setBitAtIndex:2];

    [restored filterBitset:bitset withValue:@"bob"];

    XCTAssertFalse([bitset isBitSetAtIndex:0]);
    XCTAssertTrue([bitset isBitSetAtIndex:1]);
    XCTAssertFalse([bitset isBitSetAtIndex:2]);
}

@end
