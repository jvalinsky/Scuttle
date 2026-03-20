#import <XCTest/XCTest.h>

#import "SSBGitRemoteCore.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

@interface GitRemoteSSBTests : XCTestCase
@end

@implementation GitRemoteSSBTests

- (void)testExtractRepoIDAcceptsSSBURL {
    char repoID[SSB_GIT_REMOTE_MAX_LINE];
    int ok = ssb_git_remote_extract_repo_id("ssb://%testrepo.sha256", repoID, sizeof(repoID));
    XCTAssertEqual(ok, 1);
    XCTAssertEqualObjects([NSString stringWithUTF8String:repoID], @"%testrepo.sha256");
}

- (void)testExtractRepoIDRejectsNonSSBScheme {
    char repoID[SSB_GIT_REMOTE_MAX_LINE];
    memset(repoID, 0, sizeof(repoID));
    int ok = ssb_git_remote_extract_repo_id("https://example.com", repoID, sizeof(repoID));
    XCTAssertEqual(ok, 0);
}

- (void)testResolveSocketPathPrefersXDGStateHome {
    char path[256];
    ssb_git_remote_resolve_socket_path_for_values(path,
                                                  sizeof(path),
                                                  "/tmp/state-home",
                                                  "/tmp/data-home",
                                                  "/tmp/home");
    XCTAssertEqualObjects([NSString stringWithUTF8String:path], @"/tmp/state-home/scuttle/scuttle_helper.sock");
}

- (void)testResolveSocketPathFallsBackToXDGDataHome {
    char path[256];
    ssb_git_remote_resolve_socket_path_for_values(path, sizeof(path), "", "/tmp/data-home", "/tmp/home");
    XCTAssertEqualObjects([NSString stringWithUTF8String:path], @"/tmp/data-home/scuttle/scuttle_helper.sock");
}

- (void)testResolveSocketPathFallsBackToHome {
    char path[256];
    ssb_git_remote_resolve_socket_path_for_values(path, sizeof(path), NULL, NULL, "/tmp/home");
    XCTAssertEqualObjects([NSString stringWithUTF8String:path], @"/tmp/home/.local/state/scuttle/scuttle_helper.sock");
}

- (void)testParseFetchRequestSuccess {
    char sha[SSB_GIT_REMOTE_MAX_LINE];
    char name[SSB_GIT_REMOTE_MAX_LINE];
    int ok = ssb_git_remote_parse_fetch_request("fetch abc123 refs/heads/main\n", sha, sizeof(sha), name, sizeof(name));
    XCTAssertEqual(ok, 1);
    XCTAssertEqualObjects([NSString stringWithUTF8String:sha], @"abc123");
    XCTAssertEqualObjects([NSString stringWithUTF8String:name], @"refs/heads/main");
}

- (void)testParseFetchRequestFailure {
    char sha[SSB_GIT_REMOTE_MAX_LINE];
    char name[SSB_GIT_REMOTE_MAX_LINE];
    int ok = ssb_git_remote_parse_fetch_request("fetch onlysha\n", sha, sizeof(sha), name, sizeof(name));
    XCTAssertEqual(ok, 0);
}

- (void)testParsePushRequestSuccess {
    char src[SSB_GIT_REMOTE_MAX_LINE];
    char dst[SSB_GIT_REMOTE_MAX_LINE];
    int ok = ssb_git_remote_parse_push_request("push refs/heads/main:refs/heads/main\n", src, sizeof(src), dst, sizeof(dst));
    XCTAssertEqual(ok, 1);
    XCTAssertEqualObjects([NSString stringWithUTF8String:src], @"refs/heads/main");
    XCTAssertEqualObjects([NSString stringWithUTF8String:dst], @"refs/heads/main");
}

- (void)testParsePushRequestFailure {
    char src[SSB_GIT_REMOTE_MAX_LINE];
    char dst[SSB_GIT_REMOTE_MAX_LINE];
    int ok = ssb_git_remote_parse_push_request("push refs/heads/main refs/heads/main\n", src, sizeof(src), dst, sizeof(dst));
    XCTAssertEqual(ok, 0);
}

- (void)testWriteAllAndReadFullRoundTrip {
    int pipeFDs[2];
    XCTAssertEqual(pipe(pipeFDs), 0);

    const char *payload = "hello coverage";
    size_t payloadSize = strlen(payload);
    XCTAssertEqual(ssb_git_remote_write_all(pipeFDs[1], payload, payloadSize), 0);
    close(pipeFDs[1]);

    char output[32];
    memset(output, 0, sizeof(output));
    XCTAssertEqual(ssb_git_remote_read_full(pipeFDs[0], output, payloadSize), 0);
    close(pipeFDs[0]);
    XCTAssertEqualObjects([NSString stringWithUTF8String:output], @"hello coverage");
}

- (void)testReadLineReadsUntilNewline {
    int pipeFDs[2];
    XCTAssertEqual(pipe(pipeFDs), 0);

    const char *payload = "line one\nline two\n";
    XCTAssertEqual(ssb_git_remote_write_all(pipeFDs[1], payload, strlen(payload)), 0);
    close(pipeFDs[1]);

    char line[64];
    ssize_t n = ssb_git_remote_read_line_fd(pipeFDs[0], line, sizeof(line));
    close(pipeFDs[0]);
    XCTAssertGreaterThan(n, 0);
    XCTAssertEqualObjects([NSString stringWithUTF8String:line], @"line one\n");
}

- (void)testHelperMainEndToEndList {
    NSString *productsDir = NSProcessInfo.processInfo.environment[@"BUILT_PRODUCTS_DIR"];
    if (productsDir.length == 0) {
        NSBundle *testBundle = [NSBundle bundleForClass:self.class];
        productsDir = [testBundle.bundleURL URLByDeletingLastPathComponent].path;
    }
    XCTAssertNotNil(productsDir);
    NSString *toolPath = [productsDir stringByAppendingPathComponent:@"git-remote-ssb"];
    XCTAssertTrue([[NSFileManager defaultManager] isExecutableFileAtPath:toolPath]);

    NSString *stateRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *scuttleDir = [stateRoot stringByAppendingPathComponent:@"scuttle"];
    NSString *socketPath = [scuttleDir stringByAppendingPathComponent:@"scuttle_helper.sock"];
    NSError *mkdirError = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:scuttleDir
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&mkdirError]);
    XCTAssertNil(mkdirError);

    int serverFD = socket(AF_UNIX, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(serverFD, 0);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.UTF8String, sizeof(addr.sun_path) - 1);
    unlink(addr.sun_path);

    XCTAssertEqual(bind(serverFD, (struct sockaddr *)&addr, sizeof(addr)), 0);
    XCTAssertEqual(listen(serverFD, 1), 0);

    XCTestExpectation *serverExpectation = [self expectationWithDescription:@"fake server handled list"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int clientFD = accept(serverFD, NULL, NULL);
        if (clientFD < 0) {
            close(serverFD);
            [serverExpectation fulfill];
            return;
        }

        char line[256];
        ssize_t n = ssb_git_remote_read_line_fd(clientFD, line, sizeof(line));
        if (n > 0) {
            NSString *request = [NSString stringWithUTF8String:line];
            if ([request hasPrefix:@"LIST %repo-main.sha256"]) {
                const char *resp = "refs/heads/main deadbeef\nEND\n";
                (void)ssb_git_remote_write_all(clientFD, resp, strlen(resp));
            }
        }

        close(clientFD);
        close(serverFD);
        [serverExpectation fulfill];
    });

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:toolPath];
    task.arguments = @[@"origin", @"ssb://%repo-main.sha256"];

    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"XDG_STATE_HOME"] = stateRoot;
    task.environment = env;

    NSPipe *stdinPipe = [NSPipe pipe];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardInput = stdinPipe;
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    NSError *launchError = nil;
    XCTAssertTrue([task launchAndReturnError:&launchError]);
    XCTAssertNil(launchError);

    NSData *input = [@"capabilities\nlist\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    [[stdinPipe fileHandleForWriting] writeData:input];
    [[stdinPipe fileHandleForWriting] closeFile];

    [task waitUntilExit];
    [self waitForExpectations:@[serverExpectation] timeout:5.0];

    NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";

    XCTAssertEqual(task.terminationStatus, 0, @"stderr: %@", stderrText);
    XCTAssertTrue([stdoutText containsString:@"list"]);
    XCTAssertTrue([stdoutText containsString:@"fetch"]);
    XCTAssertTrue([stdoutText containsString:@"push"]);
    XCTAssertTrue([stdoutText containsString:@"deadbeef refs/heads/main"]);

    [[NSFileManager defaultManager] removeItemAtPath:stateRoot error:nil];
}

@end
