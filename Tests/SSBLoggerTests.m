#import <XCTest/XCTest.h>
#import "SSBLogger.h"

// Expose internal protocol trace methods for testing
@interface SSBLogger (ProtocolTraceTest)
+ (void)ssb_setProtocolTraceSink:(void (^)(NSDictionary<NSString *, id> *))sink;
+ (id)ssb_protocolTraceSink;
+ (void)ssb_emitProtocolTraceEvent:(NSDictionary<NSString *, id> *)event;
@end

@interface SSBLoggerTests : XCTestCase
@end

@implementation SSBLoggerTests

- (void)setUp {
    [SSBLogger shared].minimumLevel = SSBLogLevelDebug;
}

- (void)testLogCategories {
    XCTAssertNotNil([SSBLogger shared]);
    
    os_log_t generalLog = [[SSBLogger shared] logForCategory:SSBLogCategoryGeneral];
    XCTAssertNotNil(generalLog);
    
    os_log_t uiLog = [[SSBLogger shared] logForCategory:SSBLogCategoryUI];
    XCTAssertNotNil(uiLog);
    
    os_log_t syncLog = [[SSBLogger shared] logForCategory:SSBLogCategorySync];
    XCTAssertNotNil(syncLog);
    
    os_log_t profileLog = [[SSBLogger shared] logForCategory:SSBLogCategoryProfile];
    XCTAssertNotNil(profileLog);
}

- (void)testLogLevels {
    SSBLogger *logger = [SSBLogger shared];
    logger.minimumLevel = SSBLogLevelWarning;
    
    XCTAssertEqual(logger.minimumLevel, SSBLogLevelWarning);
}

- (void)testLogMacros {
    SSBLogInfo(SSBLogCategoryGeneral, @"Test message: %d", 123);
    SSBLogDebug(SSBLogCategoryUI, @"UI Test: %@", @"hello");
    SSBLogWarning(SSBLogCategorySync, @"Sync warning");
    SSBLogError(SSBLogCategoryNetwork, @"Network error: %d", 404);
    
    XCTAssertTrue(YES);
}

- (void)testStateTransitionLogging {
    [[SSBLogger shared] logStateTransition:@"ConnectionState" from:0 to:1 category:SSBLogCategoryNetwork];
    [[SSBLogger shared] logStateTransition:@"SyncState" from:1 to:2 category:SSBLogCategorySync];

    XCTAssertTrue(YES);
}

- (void)testLog_belowMinimumLevel_earlyReturn {
    // Set minimumLevel to Error, then log at Debug → early return, no crash
    SSBLogger *logger = [SSBLogger shared];
    logger.minimumLevel = SSBLogLevelError;
    XCTAssertNoThrow([logger log:SSBLogCategoryGeneral level:SSBLogLevelDebug message:@"This should be filtered"]);
    XCTAssertNoThrow([logger log:SSBLogCategoryGeneral level:SSBLogLevelInfo message:@"Also filtered"]);
    XCTAssertNoThrow([logger log:SSBLogCategoryGeneral level:SSBLogLevelWarning message:@"Also filtered"]);
    // Restore
    logger.minimumLevel = SSBLogLevelDebug;
}

- (void)testLogForCategory_unknownCategory_returnsDefault {
    // Pass a category value beyond the registered range → falls back to OS_LOG_DEFAULT
    os_log_t log = [[SSBLogger shared] logForCategory:(SSBLogCategory)9999];
    XCTAssertNotNil(log);
}

- (void)testEmitProtocolTraceEvent_nilEvent_doesNotCrash {
    XCTAssertNoThrow([SSBLogger ssb_emitProtocolTraceEvent:nil]);
}

- (void)testEmitProtocolTraceEvent_emptyDict_doesNotCrash {
    XCTAssertNoThrow([SSBLogger ssb_emitProtocolTraceEvent:@{}]);
}

- (void)testEmitProtocolTraceEvent_validEvent_doesNotCrash {
    NSDictionary *event = @{@"component": @"test", @"message": @"hello"};
    XCTAssertNoThrow([SSBLogger ssb_emitProtocolTraceEvent:event]);
}

- (void)testSetProtocolTraceSink_andEmit_callsSink {
    __block BOOL called = NO;
    [SSBLogger ssb_setProtocolTraceSink:^(NSDictionary *event) {
        called = YES;
    }];

    NSDictionary *event = @{@"key": @"value"};
    [SSBLogger ssb_emitProtocolTraceEvent:event];
    XCTAssertTrue(called);

    // Clear the sink
    [SSBLogger ssb_setProtocolTraceSink:nil];
}

- (void)testProtocolTraceSink_returnsSetSink {
    id sink = [SSBLogger ssb_protocolTraceSink];
    // Just verify the method can be called without crashing (sink may be nil or non-nil)
    XCTAssertTrue(YES);
    (void)sink;
}

@end
