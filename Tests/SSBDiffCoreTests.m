#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBDiffCore.h>

@interface SSBDiffCoreTests : XCTestCase
@end

@implementation SSBDiffCoreTests

static uint32_t HashLine(NSString *line) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    return ssb_diff_hash_line(data.bytes, data.length);
}

- (void)testHashLineIsDeterministic {
    uint32_t a = HashLine(@"hello");
    uint32_t b = HashLine(@"hello");
    uint32_t c = HashLine(@"hello!");
    XCTAssertEqual(a, b);
    XCTAssertNotEqual(a, c);
}

- (void)testMyersProducesMatchesForIdenticalInputs {
    uint32_t values[] = { HashLine(@"a"), HashLine(@"b"), HashLine(@"c") };
    SSBDiffResult result = ssb_diff(values, 3, values, 3, SSB_DIFF_ALGORITHM_MYERS);
    XCTAssertEqual(result.count, 3);
    for (int i = 0; i < result.count; i++) {
        XCTAssertEqual(result.edits[i].type, SSB_EDIT_MATCH);
        XCTAssertEqual(result.edits[i].line_a, i);
        XCTAssertEqual(result.edits[i].line_b, i);
    }
    ssb_diff_free_result(result);
}

- (void)testMyersProducesDeleteThenAddForDifferentInputs {
    uint32_t a[] = { HashLine(@"a"), HashLine(@"b") };
    uint32_t b[] = { HashLine(@"x") };
    SSBDiffResult result = ssb_diff(a, 2, b, 1, SSB_DIFF_ALGORITHM_MYERS);
    XCTAssertEqual(result.count, 3);
    XCTAssertEqual(result.edits[0].type, SSB_EDIT_DELETE);
    XCTAssertEqual(result.edits[1].type, SSB_EDIT_DELETE);
    XCTAssertEqual(result.edits[2].type, SSB_EDIT_ADD);
    ssb_diff_free_result(result);
}

- (void)testHistogramHandlesEmptyLeftSide {
    uint32_t b[] = { HashLine(@"x"), HashLine(@"y") };
    SSBDiffResult result = ssb_diff(NULL, 0, b, 2, SSB_DIFF_ALGORITHM_HISTOGRAM);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqual(result.edits[0].type, SSB_EDIT_ADD);
    XCTAssertEqual(result.edits[1].type, SSB_EDIT_ADD);
    ssb_diff_free_result(result);
}

- (void)testHistogramHandlesEmptyRightSide {
    uint32_t a[] = { HashLine(@"x"), HashLine(@"y") };
    SSBDiffResult result = ssb_diff(a, 2, NULL, 0, SSB_DIFF_ALGORITHM_HISTOGRAM);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqual(result.edits[0].type, SSB_EDIT_DELETE);
    XCTAssertEqual(result.edits[1].type, SSB_EDIT_DELETE);
    ssb_diff_free_result(result);
}

- (void)testHistogramUsesAnchorAndRecursiveSplits {
    uint32_t a[] = { HashLine(@"left-only"), HashLine(@"anchor"), HashLine(@"right-only-a") };
    uint32_t b[] = { HashLine(@"anchor"), HashLine(@"right-only-b") };
    SSBDiffResult result = ssb_diff(a, 3, b, 2, SSB_DIFF_ALGORITHM_HISTOGRAM);
    XCTAssertGreaterThan(result.count, 0);

    BOOL sawAnchorMatch = NO;
    BOOL sawDelete = NO;
    BOOL sawAdd = NO;
    for (int i = 0; i < result.count; i++) {
        if (result.edits[i].type == SSB_EDIT_MATCH &&
            result.edits[i].line_a == 1 &&
            result.edits[i].line_b == 0) {
            sawAnchorMatch = YES;
        }
        if (result.edits[i].type == SSB_EDIT_DELETE) {
            sawDelete = YES;
        }
        if (result.edits[i].type == SSB_EDIT_ADD) {
            sawAdd = YES;
        }
    }

    XCTAssertTrue(sawAnchorMatch);
    XCTAssertTrue(sawDelete);
    XCTAssertTrue(sawAdd);
    ssb_diff_free_result(result);
}

- (void)testHistogramFallsBackWhenNoCommonLines {
    uint32_t a[] = { HashLine(@"a1"), HashLine(@"a2") };
    uint32_t b[] = { HashLine(@"b1"), HashLine(@"b2"), HashLine(@"b3") };
    SSBDiffResult result = ssb_diff(a, 2, b, 3, SSB_DIFF_ALGORITHM_HISTOGRAM);
    XCTAssertEqual(result.count, 5);

    int deleteCount = 0;
    int addCount = 0;
    for (int i = 0; i < result.count; i++) {
        if (result.edits[i].type == SSB_EDIT_DELETE) deleteCount++;
        if (result.edits[i].type == SSB_EDIT_ADD) addCount++;
    }
    XCTAssertEqual(deleteCount, 2);
    XCTAssertEqual(addCount, 3);
    ssb_diff_free_result(result);
}

@end
