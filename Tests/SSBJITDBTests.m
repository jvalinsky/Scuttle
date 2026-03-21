#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBJITDB.h>

static NSString *uniqueTempDir(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"SSBJITDBTests_%@", [[NSUUID UUID] UUIDString]]];
}

@interface SSBJITDBTests : XCTestCase
@property (nonatomic, copy) NSString *dir;
@property (nonatomic, strong) SSBJITDB *db;
@end

@implementation SSBJITDBTests

- (void)setUp {
    [super setUp];
    self.dir = uniqueTempDir();
    self.db = [[SSBJITDB alloc] initWithDirectory:self.dir];
    XCTAssertNotNil(self.db);
}

- (void)tearDown {
    [self.db close];
    self.db = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dir error:nil];
    [super tearDown];
}

#pragma mark - appendMessage / fetchMessageAtSequence

- (void)testAppendAndFetch_roundTrip {
    NSDictionary *msg = @{@"author": @"@alice.ed25519",
                          @"content": @{@"type": @"post", @"text": @"hello"}};
    XCTestExpectation *appended = [self expectationWithDescription:@"appended"];
    __block uint64_t seq = UINT64_MAX;
    [self.db appendMessage:msg completion:^(uint64_t s, NSError *err) {
        XCTAssertNil(err);
        seq = s;
        [appended fulfill];
    }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    XCTestExpectation *fetched = [self expectationWithDescription:@"fetched"];
    [self.db fetchMessageAtSequence:seq completion:^(NSDictionary *result, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqualObjects(result[@"author"], @"@alice.ed25519");
        [fetched fulfill];
    }];
    [self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testFetch_outOfBounds_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"oob"];
    [self.db fetchMessageAtSequence:999 completion:^(NSDictionary *result, NSError *err) {
        XCTAssertNotNil(err);
        XCTAssertNil(result);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

#pragma mark - appendMessages (batch)

- (void)testAppendMessages_batch {
    NSArray<NSDictionary *> *msgs = @[
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post", @"text": @"a"}},
        @{@"author": @"@bob.ed25519",   @"content": @{@"type": @"contact"}},
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post", @"text": @"b"}}
    ];
    XCTestExpectation *exp = [self expectationWithDescription:@"batch"];
    [self.db appendMessages:msgs completion:^(NSError *err) {
        XCTAssertNil(err);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testAppendMessages_empty_completesImmediately {
    XCTestExpectation *exp = [self expectationWithDescription:@"empty"];
    [self.db appendMessages:@[] completion:^(NSError *err) {
        XCTAssertNil(err);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - query

- (void)testQuery_byType_returnsMatchingBit {
    NSArray<NSDictionary *> *msgs = @[
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}},
        @{@"author": @"@bob.ed25519",   @"content": @{@"type": @"contact"}},
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}}
    ];
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    [self.db appendMessages:msgs completion:^(NSError *err) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    SSBBitset *result = [self.db query:@{@"type": @"post"}];
    XCTAssertTrue([result isBitSetAtIndex:0], @"Record 0 (post) should match");
    XCTAssertFalse([result isBitSetAtIndex:1], @"Record 1 (contact) should not match");
    XCTAssertTrue([result isBitSetAtIndex:2], @"Record 2 (post) should match");
}

- (void)testQuery_byAuthor_returnsMatchingBit {
    NSArray<NSDictionary *> *msgs = @[
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}},
        @{@"author": @"@bob.ed25519",   @"content": @{@"type": @"post"}}
    ];
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    [self.db appendMessages:msgs completion:^(NSError *err) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    SSBBitset *result = [self.db query:@{@"author": @"@alice.ed25519"}];
    XCTAssertTrue([result isBitSetAtIndex:0]);
    XCTAssertFalse([result isBitSetAtIndex:1]);
}

- (void)testQuery_byTypeAndAuthor_intersection {
    NSArray<NSDictionary *> *msgs = @[
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}},
        @{@"author": @"@bob.ed25519",   @"content": @{@"type": @"post"}},
        @{@"author": @"@alice.ed25519", @"content": @{@"type": @"contact"}}
    ];
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    [self.db appendMessages:msgs completion:^(NSError *err) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    SSBBitset *result = [self.db query:@{@"type": @"post", @"author": @"@alice.ed25519"}];
    XCTAssertTrue([result isBitSetAtIndex:0]);   // alice + post
    XCTAssertFalse([result isBitSetAtIndex:1]);  // bob + post (wrong author)
    XCTAssertFalse([result isBitSetAtIndex:2]);  // alice + contact (wrong type)
}

- (void)testQuery_emptyDB_returnsNonNilBitset {
    // An empty DB returns a non-nil bitset; no records exist so the result has no meaningful bits.
    SSBBitset *result = [self.db query:@{@"type": @"post"}];
    XCTAssertNotNil(result);
}

- (void)testQuery_unknownType_returnsNoBits {
    NSDictionary *msg = @{@"author": @"@alice.ed25519", @"content": @{@"type": @"post"}};
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    [self.db appendMessage:msg completion:^(uint64_t s, NSError *err) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    SSBBitset *result = [self.db query:@{@"type": @"nonexistent"}];
    XCTAssertFalse([result isBitSetAtIndex:0]);
}

#pragma mark - close / reopen

- (void)testCloseAndReopen_indexesSurvive {
    NSDictionary *msg = @{@"author": @"@alice.ed25519",
                          @"content": @{@"type": @"post"}};
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    [self.db appendMessage:msg completion:^(uint64_t s, NSError *err) { [exp fulfill]; }];
    [self waitForExpectationsWithTimeout:3 handler:nil];

    [self.db close];
    self.db = nil;

    SSBJITDB *reopened = [[SSBJITDB alloc] initWithDirectory:self.dir];
    XCTAssertNotNil(reopened);

    SSBBitset *result = [reopened query:@{@"type": @"post"}];
    XCTAssertTrue([result isBitSetAtIndex:0], @"Index must survive close/reopen");
    [reopened close];
    self.db = reopened; // tearDown will close it
}

@end
