#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBRandom.h>

@interface SSBRandomTests : XCTestCase
@end

@implementation SSBRandomTests

- (void)testFillRandomBytes_succeeds {
    uint8_t buf[32] = {0};
    BOOL ok = SSBFillRandomBytes(buf, sizeof(buf));
    XCTAssertTrue(ok);
}

- (void)testFillRandomBytes_producesNonZeroOutput {
    // The probability that 32 random bytes are all zero is astronomically small.
    uint8_t buf[32] = {0};
    SSBFillRandomBytes(buf, sizeof(buf));
    BOOL allZero = YES;
    for (NSUInteger i = 0; i < sizeof(buf); i++) {
        if (buf[i] != 0) { allZero = NO; break; }
    }
    XCTAssertFalse(allZero);
}

- (void)testFillRandomBytes_twoCalls_differ {
    uint8_t a[32], b[32];
    SSBFillRandomBytes(a, sizeof(a));
    SSBFillRandomBytes(b, sizeof(b));
    XCTAssertNotEqual(0, memcmp(a, b, sizeof(a)), @"Two random buffers should differ");
}

- (void)testFillRandomBytes_zeroLength_succeeds {
    uint8_t dummy = 0;
    BOOL ok = SSBFillRandomBytes(&dummy, 0);
    XCTAssertTrue(ok);
}

- (void)testRandomUInt32_returnsValue {
    // Just verify it doesn't crash and returns something.
    uint32_t v = SSBRandomUInt32();
    (void)v; // suppress unused warning — we only care it doesn't crash
    XCTAssertTrue(YES);
}

- (void)testRandomUInt32_twoCalls_likelyDiffer {
    // P(collision) = 1/2^32, negligible in a test.
    uint32_t a = SSBRandomUInt32();
    uint32_t b = SSBRandomUInt32();
    XCTAssertNotEqual(a, b, @"Two random uint32 values should differ (astronomically unlikely to collide)");
}

@end
