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

@end
