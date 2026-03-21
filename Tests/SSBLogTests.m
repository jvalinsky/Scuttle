#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBLog.h>

/// Returns a unique temp directory path for a single test run.
static NSString *uniqueTempDir(void) {
    NSString *base = NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:
            [NSString stringWithFormat:@"SSBLogTests_%@", [[NSUUID UUID] UUIDString]]];
}

/// SSBLog requires callers to supply the full record bytes: [4-byte LE uint32_t length][payload].
/// readRecordAtIndex: and enumerateRecordsUsingBlock: strip the prefix and return only the payload.
static NSData *packRecord(NSData *payload) {
    uint32_t len = (uint32_t)payload.length;
    NSMutableData *packed = [NSMutableData dataWithCapacity:sizeof(uint32_t) + len];
    [packed appendBytes:&len length:sizeof(uint32_t)];
    [packed appendData:payload];
    return packed;
}

@interface SSBLogTests : XCTestCase
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *logPath;
@property (nonatomic, strong) SSBLog *log;
@end

@implementation SSBLogTests

- (void)setUp {
    [super setUp];
    self.tempDir = uniqueTempDir();
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    self.logPath = [self.tempDir stringByAppendingPathComponent:@"test.log"];
    self.log = [[SSBLog alloc] initWithPath:self.logPath];
    XCTAssertNotNil(self.log, @"Log must be created at a writable path");
}

- (void)tearDown {
    [self.log close];
    self.log = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Initial state

- (void)testInitialRecordCount_isZero {
    XCTAssertEqual(self.log.recordCount, 0ULL);
}

- (void)testInitialCurrentOffset_isZero {
    XCTAssertEqual(self.log.currentOffset, 0ULL);
}

#pragma mark - appendRecord

- (void)testAppendRecord_incrementsRecordCount {
    XCTestExpectation *exp = [self expectationWithDescription:@"append"];
    NSData *payload = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    [self.log appendRecord:packRecord(payload) completion:^(uint64_t idx, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqual(idx, 0ULL);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(self.log.recordCount, 1ULL);
}

- (void)testAppendMultipleRecords_assignsSequentialIndexes {
    XCTestExpectation *exp1 = [self expectationWithDescription:@"append1"];
    XCTestExpectation *exp2 = [self expectationWithDescription:@"append2"];

    NSData *d1 = [@"record0" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *d2 = [@"record1" dataUsingEncoding:NSUTF8StringEncoding];

    __block uint64_t idx1 = UINT64_MAX, idx2 = UINT64_MAX;
    [self.log appendRecord:packRecord(d1) completion:^(uint64_t idx, NSError *err) {
        idx1 = idx; [exp1 fulfill];
    }];
    [self.log appendRecord:packRecord(d2) completion:^(uint64_t idx, NSError *err) {
        idx2 = idx; [exp2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTAssertEqual(idx1, 0ULL);
    XCTAssertEqual(idx2, 1ULL);
    XCTAssertEqual(self.log.recordCount, 2ULL);
}

#pragma mark - readRecordAtIndex

- (void)testReadRecordAtIndex_returnsAppendedData {
    XCTestExpectation *written = [self expectationWithDescription:@"written"];
    NSData *payload = [@"test payload" dataUsingEncoding:NSUTF8StringEncoding];
    [self.log appendRecord:packRecord(payload) completion:^(uint64_t idx, NSError *err) {
        [written fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *read = [self expectationWithDescription:@"read"];
    [self.log readRecordAtIndex:0 completion:^(NSData *data, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqualObjects(data, payload);
        [read fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testReadRecordAtIndex_outOfBounds_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"oob"];
    [self.log readRecordAtIndex:99 completion:^(NSData *data, NSError *err) {
        XCTAssertNotNil(err);
        XCTAssertNil(data);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

#pragma mark - readRecordAtOffset

- (void)testReadRecordAtOffset_readsBytes {
    // Write a known byte sequence, then read back the first 5 bytes via offset API.
    XCTestExpectation *written = [self expectationWithDescription:@"written"];
    NSData *payload = [@"abcdefghij" dataUsingEncoding:NSUTF8StringEncoding];
    [self.log appendRecord:packRecord(payload) completion:^(uint64_t idx, NSError *err) {
        [written fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    // payload starts at byte offset 4 (after 4-byte length prefix).
    XCTestExpectation *exp = [self expectationWithDescription:@"readOffset"];
    [self.log readRecordAtOffset:4 length:5 completion:^(NSData *data, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqual(data.length, 5U);
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        XCTAssertEqualObjects(s, @"abcde");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

#pragma mark - enumerateRecordsUsingBlock

- (void)testEnumerate_visitsAllRecords {
    NSArray<NSString *> *strings = @[@"alpha", @"beta", @"gamma"];
    for (NSString *s in strings) {
        XCTestExpectation *e = [self expectationWithDescription:s];
        [self.log appendRecord:packRecord([s dataUsingEncoding:NSUTF8StringEncoding])
                    completion:^(uint64_t i, NSError *err) { [e fulfill]; }];
    }
    [self waitForExpectationsWithTimeout:2 handler:nil];

    NSMutableArray *visited = [NSMutableArray array];
    [self.log enumerateRecordsUsingBlock:^BOOL(NSData *data, uint64_t idx) {
        [visited addObject:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
        return YES;
    }];

    XCTAssertEqualObjects(visited, strings);
}

- (void)testEnumerate_earlyStop_respectsReturnNO {
    for (int i = 0; i < 5; i++) {
        XCTestExpectation *e = [self expectationWithDescription:[NSString stringWithFormat:@"w%d",i]];
        NSData *d = [[NSString stringWithFormat:@"r%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        [self.log appendRecord:packRecord(d) completion:^(uint64_t idx, NSError *err) { [e fulfill]; }];
    }
    [self waitForExpectationsWithTimeout:2 handler:nil];

    __block NSInteger count = 0;
    [self.log enumerateRecordsUsingBlock:^BOOL(NSData *data, uint64_t idx) {
        count++;
        return count < 3; // stop after 3
    }];
    XCTAssertEqual(count, 3);
}

#pragma mark - close / reopen

- (void)testCloseAndReopen_preservesRecords {
    XCTestExpectation *written = [self expectationWithDescription:@"written"];
    NSData *payload = [@"persistent" dataUsingEncoding:NSUTF8StringEncoding];
    [self.log appendRecord:packRecord(payload) completion:^(uint64_t idx, NSError *err) {
        [written fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [self.log close];
    self.log = nil;

    // Reopen the same path.
    SSBLog *reopened = [[SSBLog alloc] initWithPath:self.logPath];
    XCTAssertNotNil(reopened);
    XCTAssertEqual(reopened.recordCount, 1ULL);

    XCTestExpectation *read = [self expectationWithDescription:@"read"];
    [reopened readRecordAtIndex:0 completion:^(NSData *data, NSError *err) {
        XCTAssertNil(err);
        XCTAssertEqualObjects(data, payload);
        [read fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [reopened close];
}

- (void)testCloseAndReopen_offsetMapMismatch_rebuilds {
    // Write some records, then delete the .offsets file to force a scan rebuild.
    for (int i = 0; i < 3; i++) {
        XCTestExpectation *e = [self expectationWithDescription:[NSString stringWithFormat:@"w%d",i]];
        NSData *d = [[NSString stringWithFormat:@"x%d", i] dataUsingEncoding:NSUTF8StringEncoding];
        [self.log appendRecord:packRecord(d) completion:^(uint64_t idx, NSError *err) { [e fulfill]; }];
    }
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [self.log close];
    self.log = nil;

    // Delete the offsets file so the next open must rebuild from scratch.
    NSString *offsetsPath = [self.logPath stringByAppendingString:@".offsets"];
    [[NSFileManager defaultManager] removeItemAtPath:offsetsPath error:nil];

    SSBLog *reopened = [[SSBLog alloc] initWithPath:self.logPath];
    XCTAssertNotNil(reopened);
    XCTAssertEqual(reopened.recordCount, 3ULL);
    [reopened close];
}

@end
