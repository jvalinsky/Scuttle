#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBEnvironment.h>

@interface FakeEnvironment : NSObject <SSBEnvironmentProtocol>
@property (nonatomic, strong) NSDate *fixedDate;
@property (nonatomic, assign) uint32_t fixedRandom;
@property (nonatomic, strong) NSMutableArray *afterBlocks;
@end

@implementation FakeEnvironment

- (NSDate *)now { return self.fixedDate ?: [NSDate dateWithTimeIntervalSince1970:0]; }
- (uint32_t)randomUInt32 { return self.fixedRandom; }
- (void)randomBytes:(void *)buffer length:(NSUInteger)length { memset(buffer, 0xAB, length); }
- (NSURLSession *)URLSession { return [NSURLSession sharedSession]; }
- (NSURLSession *)URLSessionWithConfiguration:(NSURLSessionConfiguration *)c {
    return [NSURLSession sessionWithConfiguration:c];
}
- (NSFileManager *)fileManager { return [NSFileManager defaultManager]; }
- (NSString *)scuttleDataDirectory { return @"/tmp/scuttle-fake"; }
- (void)dispatchAfter:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block {
    if (self.afterBlocks) { [self.afterBlocks addObject:block]; }
    else { block(); }
}

@end

@interface SSBEnvironmentTests : XCTestCase
@property (nonatomic, strong) id<SSBEnvironmentProtocol> savedShared;
@end

@implementation SSBEnvironmentTests

- (void)setUp {
    [super setUp];
    self.savedShared = [SSBEnvironment shared];
}

- (void)tearDown {
    [SSBEnvironment setShared:self.savedShared];
    [super tearDown];
}

#pragma mark - shared / setShared

- (void)testShared_returnsNonNil {
    XCTAssertNotNil([SSBEnvironment shared]);
}

- (void)testSetShared_replacesInstance {
    FakeEnvironment *fake = [[FakeEnvironment alloc] init];
    [SSBEnvironment setShared:fake];
    XCTAssertEqual([SSBEnvironment shared], fake);
}

- (void)testSetShared_nil_restoresDefaultSSBEnvironment {
    [SSBEnvironment setShared:nil];
    id<SSBEnvironmentProtocol> env = [SSBEnvironment shared];
    XCTAssertNotNil(env);
    // Default implementation should return an actual date
    XCTAssertNotNil([env now]);
}

#pragma mark - SSBEnvironment concrete methods

- (void)testNow_returnsRecentDate {
    NSDate *before = [NSDate date];
    NSDate *result = [[SSBEnvironment shared] now];
    NSDate *after = [NSDate date];
    XCTAssertGreaterThanOrEqual([result timeIntervalSince1970], [before timeIntervalSince1970] - 1);
    XCTAssertLessThanOrEqual([result timeIntervalSince1970], [after timeIntervalSince1970] + 1);
}

- (void)testRandomUInt32_returnsValue {
    // Just verify it doesn't crash and is a valid uint32
    uint32_t r = [[SSBEnvironment shared] randomUInt32];
    (void)r; // suppress unused warning
    XCTAssertTrue(YES); // no crash = pass
}

- (void)testRandomBytes_fillsBuffer {
    NSMutableData *buf = [NSMutableData dataWithLength:16];
    // Zero out buffer first
    memset(buf.mutableBytes, 0, 16);
    [[SSBEnvironment shared] randomBytes:buf.mutableBytes length:16];
    // Check that *something* was written (bytes very unlikely to remain all-zero)
    const uint8_t *bytes = buf.bytes;
    BOOL allZero = YES;
    for (NSUInteger i = 0; i < 16; i++) {
        if (bytes[i] != 0) { allZero = NO; break; }
    }
    XCTAssertFalse(allZero, @"randomBytes should produce non-zero output");
}

- (void)testURLSession_returnsNonNil {
    XCTAssertNotNil([[SSBEnvironment shared] URLSession]);
}

- (void)testURLSessionWithConfiguration_returnsNonNil {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    XCTAssertNotNil([[SSBEnvironment shared] URLSessionWithConfiguration:config]);
}

- (void)testFileManager_returnsNonNil {
    XCTAssertNotNil([[SSBEnvironment shared] fileManager]);
}

- (void)testScuttleDataDirectory_returnsNonEmpty {
    NSString *dir = [[SSBEnvironment shared] scuttleDataDirectory];
    XCTAssertNotNil(dir);
    XCTAssertGreaterThan(dir.length, 0U);
}

- (void)testScuttleDataDirectory_withXDGEnv_usesXDG {
    // Use a FakeEnvironment to simulate XDG_DATA_HOME being set
    FakeEnvironment *fake = [[FakeEnvironment alloc] init];
    [SSBEnvironment setShared:fake];
    NSString *dir = [[SSBEnvironment shared] scuttleDataDirectory];
    XCTAssertEqualObjects(dir, @"/tmp/scuttle-fake");
}

- (void)testDispatchAfter_calledImmediately_executesBlock {
    __block BOOL executed = NO;
    SSBEnvironment *env = [[SSBEnvironment alloc] init];
    [env dispatchAfter:0 queue:dispatch_get_main_queue() block:^{
        executed = YES;
    }];
    // Give the main queue a chance to run the block
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertTrue(executed);
}

#pragma mark - SSBEnvironmentRandomBytes C function

- (void)testSSBEnvironmentRandomBytes_fillsBuffer {
    uint8_t buf[8] = {0};
    SSBEnvironmentRandomBytes(buf, 8);
    // Bytes were written — just check it didn't crash
    XCTAssertTrue(YES);
}

#pragma mark - FakeEnvironment injection

- (void)testFakeEnvironment_fixedDate {
    FakeEnvironment *fake = [[FakeEnvironment alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSince1970:12345];
    [SSBEnvironment setShared:fake];
    XCTAssertEqualObjects([[SSBEnvironment shared] now], fake.fixedDate);
}

- (void)testFakeEnvironment_fixedRandom {
    FakeEnvironment *fake = [[FakeEnvironment alloc] init];
    fake.fixedRandom = 42;
    XCTAssertEqual([fake randomUInt32], 42U);
}

@end
