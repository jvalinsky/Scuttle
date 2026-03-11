#import <XCTest/XCTest.h>
#import "SSBLogger.h"

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

@end
