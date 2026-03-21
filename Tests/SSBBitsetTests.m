#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBitset.h>

@interface SSBBitsetTests : XCTestCase
@end

@implementation SSBBitsetTests

#pragma mark - Initialization

- (void)testInitWithCapacity_allBitsClearByDefault {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    XCTAssertNotNil(bs);
    XCTAssertEqual(bs.capacity, (uint64_t)64);
    for (uint64_t i = 0; i < 64; i++) {
        XCTAssertFalse([bs isBitSetAtIndex:i], @"All bits should be clear after init");
    }
}

- (void)testInitWithCapacity_large {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:1024];
    XCTAssertEqual(bs.capacity, (uint64_t)1024);
}

- (void)testInitWithData_roundTrip {
    SSBBitset *original = [[SSBBitset alloc] initWithCapacity:64];
    [original setBitAtIndex:3];
    [original setBitAtIndex:63];

    NSData *data = original.data;
    SSBBitset *restored = [[SSBBitset alloc] initWithData:data];
    XCTAssertTrue([restored isBitSetAtIndex:3]);
    XCTAssertTrue([restored isBitSetAtIndex:63]);
    XCTAssertFalse([restored isBitSetAtIndex:0]);
}

#pragma mark - setBitAtIndex: / clearBitAtIndex: / isBitSetAtIndex:

- (void)testSetBit_firstBit {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:0];
    XCTAssertTrue([bs isBitSetAtIndex:0]);
}

- (void)testSetBit_lastBit {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:63];
    XCTAssertTrue([bs isBitSetAtIndex:63]);
    XCTAssertFalse([bs isBitSetAtIndex:62]);
}

- (void)testClearBit {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:5];
    XCTAssertTrue([bs isBitSetAtIndex:5]);
    [bs clearBitAtIndex:5];
    XCTAssertFalse([bs isBitSetAtIndex:5]);
}

- (void)testClearBit_alreadyClear {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs clearBitAtIndex:10];  // should not crash
    XCTAssertFalse([bs isBitSetAtIndex:10]);
}

- (void)testSetMultipleBits {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:128];
    NSArray<NSNumber *> *indices = @[@0, @7, @8, @63, @64, @127];
    for (NSNumber *idx in indices) {
        [bs setBitAtIndex:idx.unsignedLongLongValue];
    }
    for (NSNumber *idx in indices) {
        XCTAssertTrue([bs isBitSetAtIndex:idx.unsignedLongLongValue],
                      @"Bit %@ should be set", idx);
    }
}

#pragma mark - countSetBits

- (void)testCountSetBits_zero {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    XCTAssertEqual([bs countSetBits], (uint64_t)0);
}

- (void)testCountSetBits_single {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:17];
    XCTAssertEqual([bs countSetBits], (uint64_t)1);
}

- (void)testCountSetBits_all {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    for (uint64_t i = 0; i < 64; i++) [bs setBitAtIndex:i];
    XCTAssertEqual([bs countSetBits], (uint64_t)64);
}

- (void)testCountSetBits_afterClear {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:1];
    [bs setBitAtIndex:2];
    [bs clearBitAtIndex:1];
    XCTAssertEqual([bs countSetBits], (uint64_t)1);
}

#pragma mark - andWithBitset:

- (void)testAND_commonBit {
    SSBBitset *a = [[SSBBitset alloc] initWithCapacity:64];
    SSBBitset *b = [[SSBBitset alloc] initWithCapacity:64];
    [a setBitAtIndex:5];
    [a setBitAtIndex:10];
    [b setBitAtIndex:5];
    [b setBitAtIndex:20];

    [a andWithBitset:b];
    XCTAssertTrue([a isBitSetAtIndex:5]);
    XCTAssertFalse([a isBitSetAtIndex:10]);
    XCTAssertFalse([a isBitSetAtIndex:20]);
}

- (void)testAND_noCommonBits {
    SSBBitset *a = [[SSBBitset alloc] initWithCapacity:64];
    SSBBitset *b = [[SSBBitset alloc] initWithCapacity:64];
    [a setBitAtIndex:0];
    [b setBitAtIndex:63];

    [a andWithBitset:b];
    XCTAssertEqual([a countSetBits], (uint64_t)0);
}

#pragma mark - orWithBitset:

- (void)testOR_unionOfBits {
    SSBBitset *a = [[SSBBitset alloc] initWithCapacity:64];
    SSBBitset *b = [[SSBBitset alloc] initWithCapacity:64];
    [a setBitAtIndex:1];
    [b setBitAtIndex:2];

    [a orWithBitset:b];
    XCTAssertTrue([a isBitSetAtIndex:1]);
    XCTAssertTrue([a isBitSetAtIndex:2]);
}

- (void)testOR_bothSetSameBit {
    SSBBitset *a = [[SSBBitset alloc] initWithCapacity:64];
    SSBBitset *b = [[SSBBitset alloc] initWithCapacity:64];
    [a setBitAtIndex:7];
    [b setBitAtIndex:7];

    [a orWithBitset:b];
    XCTAssertTrue([a isBitSetAtIndex:7]);
    XCTAssertEqual([a countSetBits], (uint64_t)1);
}

#pragma mark - not

- (void)testNOT_flipsBits {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:0];
    [bs not];
    XCTAssertFalse([bs isBitSetAtIndex:0]);
    XCTAssertTrue([bs isBitSetAtIndex:1]);
    XCTAssertTrue([bs isBitSetAtIndex:63]);
}

- (void)testNOT_allSet_becomesAllClear {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    for (uint64_t i = 0; i < 64; i++) [bs setBitAtIndex:i];
    [bs not];
    XCTAssertEqual([bs countSetBits], (uint64_t)0);
}

- (void)testNOT_doubleInversion_restoresOriginal {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    [bs setBitAtIndex:3];
    [bs setBitAtIndex:33];
    uint64_t before = [bs countSetBits];
    [bs not];
    [bs not];
    XCTAssertEqual([bs countSetBits], before);
    XCTAssertTrue([bs isBitSetAtIndex:3]);
    XCTAssertTrue([bs isBitSetAtIndex:33]);
}

#pragma mark - NSCopying

- (void)testCopy_isIndependent {
    SSBBitset *original = [[SSBBitset alloc] initWithCapacity:64];
    [original setBitAtIndex:5];

    SSBBitset *copy = [original copy];
    XCTAssertTrue([copy isBitSetAtIndex:5]);

    // Mutating original should not affect copy
    [original setBitAtIndex:10];
    XCTAssertFalse([copy isBitSetAtIndex:10]);
}

- (void)testCopy_mutatingCopyDoesNotAffectOriginal {
    SSBBitset *original = [[SSBBitset alloc] initWithCapacity:64];
    [original setBitAtIndex:1];

    SSBBitset *copy = [original copy];
    [copy setBitAtIndex:2];

    XCTAssertFalse([original isBitSetAtIndex:2]);
}

#pragma mark - data property

#pragma mark - Non-multiple-of-8 capacity

- (void)testCountSetBits_nonByteAligned_countsBitsWithinCapacity {
    // 10 bits = 1 full byte + 2 remaining bits
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:10];
    [bs setBitAtIndex:0];
    [bs setBitAtIndex:7]; // last of full byte
    [bs setBitAtIndex:8]; // first remaining bit
    [bs setBitAtIndex:9]; // second remaining bit
    XCTAssertEqual([bs countSetBits], (uint64_t)4);
}

- (void)testCountSetBits_nonByteAligned_emptyBitset {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:7];
    XCTAssertEqual([bs countSetBits], (uint64_t)0);
}

- (void)testAndWithBitset_selfLarger_zeroesExtraBits {
    // self has 128 bits, other has 64 bits: extra 64 bits of self should be zero'd
    SSBBitset *a = [[SSBBitset alloc] initWithCapacity:128];
    [a setBitAtIndex:0];
    [a setBitAtIndex:64];  // in the upper half
    [a setBitAtIndex:100]; // in the upper half

    SSBBitset *b = [[SSBBitset alloc] initWithCapacity:64];
    [b setBitAtIndex:0];

    [a andWithBitset:b];

    // bit 0: both set → 1
    XCTAssertTrue([a isBitSetAtIndex:0]);
    // bits 64 and 100: self had them set but other has no data for that range → 0
    XCTAssertFalse([a isBitSetAtIndex:64]);
    XCTAssertFalse([a isBitSetAtIndex:100]);
    XCTAssertEqual([a countSetBits], (uint64_t)1);
}

#pragma mark - data property

- (void)testData_notNil {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    XCTAssertNotNil(bs.data);
}

- (void)testData_sizeMatchesCapacity {
    SSBBitset *bs = [[SSBBitset alloc] initWithCapacity:64];
    // 64 bits = 8 bytes minimum
    XCTAssertGreaterThanOrEqual(bs.data.length, (NSUInteger)8);
}

@end
