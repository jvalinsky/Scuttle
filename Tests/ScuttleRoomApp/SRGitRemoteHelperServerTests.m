#import <XCTest/XCTest.h>
#import "../../App/Logic/SRGitRemoteHelperServer.h"

@interface SRGitRemoteHelperServerTests : XCTestCase
@end

@implementation SRGitRemoteHelperServerTests

- (NSString *)getScuttleSocketPath {
    NSString *xdgState = NSProcessInfo.processInfo.environment[@"XDG_STATE_HOME"];
    if (xdgState.length > 0) {
        return [[xdgState stringByAppendingPathComponent:@"scuttle"] stringByAppendingPathComponent:@"scuttle_helper.sock"];
    }
    NSString *xdgData = NSProcessInfo.processInfo.environment[@"XDG_DATA_HOME"];
    if (xdgData.length > 0) {
        return [[xdgData stringByAppendingPathComponent:@"scuttle"] stringByAppendingPathComponent:@"scuttle_helper.sock"];
    }
    return [[NSHomeDirectory() stringByAppendingPathComponent:@".local/state/scuttle"] stringByAppendingPathComponent:@"scuttle_helper.sock"];
}

- (void)testServerSingleton {
    SRGitRemoteHelperServer *server1 = [SRGitRemoteHelperServer sharedServer];
    SRGitRemoteHelperServer *server2 = [SRGitRemoteHelperServer sharedServer];
    XCTAssertEqual(server1, server2);
    XCTAssertNotNil(server1);
}

- (void)testStartCreatesSocketAndStopRemovesIt {
    SRGitRemoteHelperServer *server = [[SRGitRemoteHelperServer alloc] init];
    
    // Ensure clean state from any previous crashed tests
    [server stop];
    
    BOOL started = [server start];
    XCTAssertTrue(started, @"Server should start successfully");
    
    NSString *socketPath = [self getScuttleSocketPath];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:socketPath], @"Socket file should be created on start");
    
    [server stop];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:socketPath], @"Socket file should be unlinked on stop");
}

@end
