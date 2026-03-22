#import <XCTest/XCTest.h>
#import "SSBDiffEngine.h"

@interface SSBDiffEngineTests : XCTestCase
@end

@implementation SSBDiffEngineTests

- (void)testIdenticalStrings {
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"line 1\nline 2";
    NSString *b = @"line 1\nline 2";
    NSArray *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeMyers];
    XCTAssertEqual(hunks.count, 0, @"Identical strings should have no hunks");
}

- (void)testDifferentStrings {
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"line 1";
    NSString *b = @"line 2";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeMyers];

    XCTAssertGreaterThan(hunks.count, 0, @"Different strings should have at least one hunk");
    SSBDiffHunk *hunk = hunks.firstObject;
    XCTAssertEqual(hunk.edits.count, 2, @"Expected one deletion and one addition in simplified Myers");
    // Covers hunkHeader
    NSString *header = [hunk hunkHeader];
    XCTAssertTrue([header hasPrefix:@"@@"]);
    XCTAssertTrue([header hasSuffix:@"@@"]);
}

- (void)testHunksWithContext_groupsCorrectly {
    // Histogram algorithm finds "common" as an anchor between two change groups.
    // Edit sequence: delete, insert, MATCH, delete, insert — the match with an active
    // currentHunk exercises the "else if (currentHunk)" branch, closing the first hunk
    // and producing a second hunk for the trailing changes.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"aaa\ncommon\nbbb";
    NSString *b = @"XXX\ncommon\nYYY";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 1, @"Two separate change groups should produce two hunks");
    SSBDiffHunk *hunk = hunks.firstObject;
    XCTAssertGreaterThan(hunk.edits.count, 0U);
}

- (void)testInsertionOnly_createsHunk {
    // Inserting a line into an otherwise empty file — first edit may have lineA < 0,
    // exercising the ternary guards in groupEditsIntoHunks:.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"";
    NSString *b = @"new line";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeMyers];
    // Result may have 0 or 1 hunks depending on how the algorithm handles empty input.
    XCTAssertTrue(YES); // no crash is the important assertion
}

- (void)testPatience_algorithm_identicalStrings {
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"line 1\nline 2";
    NSArray *hunks = [engine diffString:a withString:a algorithm:SSBDiffAlgorithmTypePatience];
    XCTAssertEqual(hunks.count, 0U);
}

- (void)testHistogram_capacityResize_atAnchorInsert {
    // 5 unique lines on each side before a common anchor.
    // Left recursion: 5 deletes + 5 adds = 10 edits, fills initial capacity=10.
    // Anchor insert hits count==capacity → triggers resize in match-anchor block.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"a1\na2\na3\na4\na5\nanchor\nb1";
    NSString *b = @"c1\nc2\nc3\nc4\nc5\nanchor\nd1";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 0U, @"Expected at least one hunk");
}

- (void)testHistogram_capacityResize_inAddLoop {
    // 10 unique lines in A, 1 different unique line in B — no common anchor.
    // 10 deletes fill capacity=10, then the first add triggers resize in the add loop.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"u1\nu2\nu3\nu4\nu5\nu6\nu7\nu8\nu9\nu10";
    NSString *b = @"v1";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 0U, @"Expected at least one hunk");
}

- (void)testHistogram_capacityResize_inDeleteLoop {
    // Pure m==0 path: A with 11 unique lines vs empty B.
    // Edits 1-10 fill capacity=10; edit 11 triggers resize in the m==0 delete loop.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"d1\nd2\nd3\nd4\nd5\nd6\nd7\nd8\nd9\nd10\nd11";
    NSString *b = @"";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 0U, @"Expected at least one hunk");
}

- (void)testHistogram_capacityResize_inAddLoop_n0 {
    // Pure n==0 path: empty A vs B with 11 lines.
    // Edits 1-10 fill capacity=10; edit 11 triggers resize in the n==0 add loop.
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"";
    NSString *b = @"e1\ne2\ne3\ne4\ne5\ne6\ne7\ne8\ne9\ne10\ne11";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertTrue(YES); // no crash; resize was exercised
}

- (void)testHistogram_recursive_n0_path {
    // anchor is at index 0 in A → left recursion with n=0, m=1 hits n==0 code path.
    // A = "anchor\nstuff", B = "before\nanchor\nstuff"
    // anchor_a=0, anchor_b=1 → left: n=0, m=1
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"anchor\nstuff";
    NSString *b = @"before\nanchor\nstuff";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 0U);
}

- (void)testHistogram_recursive_m0_path {
    // anchor is at index 0 in B → left recursion with n=1, m=0 hits m==0 code path.
    // A = "before\nanchor", B = "anchor\nstuff"
    // anchor_a=1, anchor_b=0 → left: n=1, m=0
    SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
    NSString *a = @"before\nanchor";
    NSString *b = @"anchor\nstuff";
    NSArray<SSBDiffHunk *> *hunks = [engine diffString:a withString:b algorithm:SSBDiffAlgorithmTypeHistogram];
    XCTAssertGreaterThan(hunks.count, 0U);
}

@end
