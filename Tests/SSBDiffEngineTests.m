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
}

@end
