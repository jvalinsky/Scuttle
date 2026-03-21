#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBQueryEngine.h>

@interface SSBQueryEngineTests : XCTestCase
@end

@implementation SSBQueryEngineTests

#pragma mark - isValidQuery

- (void)testIsValidQuery_emptyDict_returnsFalse {
    XCTAssertFalse([SSBQueryEngine isValidQuery:@{}]);
}

- (void)testIsValidQuery_missingAuthor_returnsFalse {
    NSDictionary *q = @{@"type": @"post", @"private": @(NO)};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_emptyAuthor_returnsFalse {
    NSDictionary *q = @{@"author": @"", @"type": @"post", @"private": @(NO)};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_nonStringAuthor_returnsFalse {
    NSDictionary *q = @{@"author": @42, @"type": @"post", @"private": @(NO)};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_missingPrivate_returnsFalse {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"type": @"post"};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_nonBooleanPrivate_returnsFalse {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @"yes", @"type": @"post"};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_validPublicQuery_returnsTrue {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @"post"};
    XCTAssertTrue([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_validPublicNoType_returnsTrue {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": [NSNull null]};
    XCTAssertTrue([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_validPrivateNoType_returnsTrue {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": [NSNull null]};
    XCTAssertTrue([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_privateWithType_returnsFalse {
    // private: true + type != null is invalid per ssb-ql-0
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": @"post"};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

- (void)testIsValidQuery_nonStringType_returnsFalse {
    NSDictionary *q = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @42};
    XCTAssertFalse([SSBQueryEngine isValidQuery:q]);
}

#pragma mark - evaluateQuery:againstMessage

- (void)testEvaluateQuery_invalidQuery_returnsFalse {
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}};
    XCTAssertFalse([SSBQueryEngine evaluateQuery:@{} againstMessage:msg]);
}

- (void)testEvaluateQuery_authorMatch_returnsTrue {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @"post"};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}};
    XCTAssertTrue([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_wrongAuthor_returnsFalse {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @"post"};
    NSDictionary *msg = @{@"author": @"@bob.ed25519", @"content": @{@"type": @"post"}};
    XCTAssertFalse([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_wrongType_returnsFalse {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @"post"};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"contact"}};
    XCTAssertFalse([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_noTypeFilter_matchesAny {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": [NSNull null]};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"contact"}};
    XCTAssertTrue([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_privateMessage_queriedPublic_returnsFalse {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": [NSNull null]};
    // A string content ending in .box indicates a private (encrypted) message
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @"some_encrypted_content.box"};
    XCTAssertFalse([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_privateMessage_queriedPrivate_returnsTrue {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": [NSNull null]};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @"some_encrypted_content.box"};
    XCTAssertTrue([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_box2Message_queriedPrivate_returnsTrue {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": [NSNull null]};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @"some_encrypted_content.box2"};
    XCTAssertTrue([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

- (void)testEvaluateQuery_privateQueryPublicMsg_returnsFalse {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": [NSNull null]};
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}};
    XCTAssertFalse([SSBQueryEngine evaluateQuery:query againstMessage:msg]);
}

#pragma mark - sqlFragmentForQuery

- (void)testSqlFragment_invalidQuery_returnsEmptyDict {
    NSDictionary *result = [SSBQueryEngine sqlFragmentForQuery:@{}];
    XCTAssertNil(result[@"sql"]);
}

- (void)testSqlFragment_publicQueryWithType_returnsSQLWithType {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": @"post"};
    NSDictionary *result = [SSBQueryEngine sqlFragmentForQuery:query];
    NSString *sql = result[@"sql"];
    NSArray *params = result[@"params"];
    XCTAssertNotNil(sql);
    XCTAssertTrue([sql containsString:@"author = ?"], @"SQL must filter by author");
    XCTAssertTrue([sql containsString:@"is_private = ?"], @"SQL must filter by privacy");
    XCTAssertTrue([sql containsString:@"content_type = ?"], @"SQL must filter by content_type");
    XCTAssertEqual(params.count, 3U);
    XCTAssertEqualObjects(params[0], @"@alice.ed25519");
    XCTAssertEqualObjects(params[1], @0);
    XCTAssertEqualObjects(params[2], @"post");
}

- (void)testSqlFragment_publicQueryNoType_returnsSQLWithoutContentType {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(NO), @"type": [NSNull null]};
    NSDictionary *result = [SSBQueryEngine sqlFragmentForQuery:query];
    NSString *sql = result[@"sql"];
    NSArray *params = result[@"params"];
    XCTAssertNotNil(sql);
    XCTAssertFalse([sql containsString:@"content_type"], @"No type filter should omit content_type");
    XCTAssertEqual(params.count, 2U);
}

- (void)testSqlFragment_privateQuery_returnsPrivateSQL {
    NSDictionary *query = @{@"author": @"@alice.ed25519", @"private": @(YES), @"type": [NSNull null]};
    NSDictionary *result = [SSBQueryEngine sqlFragmentForQuery:query];
    NSArray *params = result[@"params"];
    XCTAssertEqualObjects(params[1], @1, @"Private query must set is_private = 1");
}

@end
