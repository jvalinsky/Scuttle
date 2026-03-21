#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBThread.h>
#import <SSBNetwork/SSBMessage.h>

/// Convenience builder.
static SSBMessage *makeMsg(NSString *key, NSString *author, NSInteger seq,
                           NSDictionary *content) {
    SSBMessage *m = [[SSBMessage alloc] init];
    m.key = key;
    m.author = author;
    m.sequence = seq;
    m.content = content;
    m.valueJSON = [NSData data];
    return m;
}

@interface SSBThreadTests : XCTestCase
@end

@implementation SSBThreadTests

#pragma mark - linearize — basic

- (void)testLinearize_nilRoot_returnsEmpty {
    // Passing nil root exercises the early-return guard.
    SSBThread *t = [[SSBThread alloc] initWithRoot:nil messages:@[]];
    XCTAssertEqualObjects([t linearize], @[]);
}

- (void)testLinearize_rootOnly {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root]];
    NSArray *result = [t linearize];
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqual(result.firstObject, root);
}

- (void)testLinearize_rootAndReply_rootFirst {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBMessage *reply = makeMsg(@"%reply.sha256", @"@bob.ed25519", 1,
                                @{@"type": @"post",
                                  @"root": @"%root.sha256",
                                  @"branch": @"%root.sha256"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root, reply]];
    NSArray *result = [t linearize];
    XCTAssertEqual(result.count, 2U);
    XCTAssertEqual(result[0], root);
    XCTAssertEqual(result[1], reply);
}

- (void)testLinearize_deduplicatesRoot {
    // The root message appears in the messages array — must not appear twice.
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root, root]];
    NSArray *result = [t linearize];
    XCTAssertEqual(result.count, 1U);
}

#pragma mark - linearize — tangles-style branch

- (void)testLinearize_tangleBranch_arrayBranch {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"root"});
    SSBMessage *r2 = makeMsg(@"%r2.sha256", @"@bob.ed25519", 2,
                             @{@"type": @"post",
                               @"root": @"%root.sha256",
                               @"branch": @[@"%root.sha256"]});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root, r2]];
    NSArray *result = [t linearize];
    XCTAssertEqual(result.count, 2U);
}

#pragma mark - linearizeFilteredByBlockedAuthors

- (void)testFilterBlocked_excludesBlockedReplies {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBMessage *blocked = makeMsg(@"%blocked.sha256", @"@blocked.ed25519", 1,
                                  @{@"type": @"post",
                                    @"root": @"%root.sha256",
                                    @"branch": @"%root.sha256"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root, blocked]];
    NSArray *result = [t linearizeFilteredByBlockedAuthors:
                       [NSSet setWithObject:@"@blocked.ed25519"]];
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqual(result[0], root);
}

- (void)testFilterBlocked_blockedRoot_returnsEmpty {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@blocked.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root]];
    NSArray *result = [t linearizeFilteredByBlockedAuthors:
                       [NSSet setWithObject:@"@blocked.ed25519"]];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testFilterBlocked_emptySet_returnsAll {
    SSBMessage *root = makeMsg(@"%root.sha256", @"@alice.ed25519", 1,
                               @{@"type": @"post", @"text": @"hi"});
    SSBMessage *reply = makeMsg(@"%reply.sha256", @"@bob.ed25519", 1,
                                @{@"type": @"post",
                                  @"root": @"%root.sha256",
                                  @"branch": @"%root.sha256"});
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:@[root, reply]];
    NSArray *result = [t linearizeFilteredByBlockedAuthors:[NSSet set]];
    XCTAssertEqual(result.count, 2U);
}

#pragma mark - Properties

- (void)testProperties_rootAndMessages {
    SSBMessage *root = makeMsg(@"%r.sha256", @"@alice.ed25519", 1, @{});
    NSArray *msgs = @[root];
    SSBThread *t = [[SSBThread alloc] initWithRoot:root messages:msgs];
    XCTAssertEqual(t.root, root);
    XCTAssertEqualObjects(t.messages, msgs);
}

@end
