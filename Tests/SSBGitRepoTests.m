#import <XCTest/XCTest.h>
#import "SSBGitRepo.h"
#import "SSBGitObjectStore.h"
#import "SSBBlobStore.h"
#import "SSBMessage.h"
#import <errno.h>
#import <limits.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *SSBGitRepoFixtureDirectory(void) {
    return [[@__FILE__ stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Fixtures/Git"];
}

static NSData *SSBGitRepoFixtureData(NSString *name) {
    NSString *path = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSCAssert(data != nil, @"Missing git fixture %@", path);
    return data;
}

static NSDictionary<NSString *, NSString *> *SSBGitRepoManifest(void) {
    NSData *data = SSBGitRepoFixtureData(@"manifest.json");
    NSDictionary<NSString *, NSString *> *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSCAssert([manifest isKindOfClass:[NSDictionary class]], @"Invalid git fixture manifest");
    return manifest;
}

static NSData *SSBGitRepoExpectedFixtureBlob(NSInteger updatedLine) {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger idx = 1; idx <= 400; idx++) {
        if (idx == updatedLine) {
            [text appendFormat:@"alpha line %ld updated same same same same same same same same same same\n", (long)idx];
        } else {
            [text appendFormat:@"alpha line %ld same same same same same same same same same same\n", (long)idx];
        }
    }
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

static int SSBGitReadLineFD(int fd, char *buffer, size_t size) {
    size_t used = 0;
    while (used + 1 < size) {
        ssize_t n = read(fd, buffer + used, 1);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) break;
        if (buffer[used++] == '\n') break;
    }
    buffer[used] = '\0';
    return (int)used;
}

static BOOL SSBGitReadExactFD(int fd, void *buffer, size_t size) {
    size_t readTotal = 0;
    unsigned char *cursor = buffer;
    while (readTotal < size) {
        ssize_t n = read(fd, cursor + readTotal, size - readTotal);
        if (n < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (n == 0) {
            return NO;
        }
        readTotal += (size_t)n;
    }
    return YES;
}

static BOOL SSBGitWriteExactFD(int fd, const void *buffer, size_t size) {
    size_t written = 0;
    const unsigned char *cursor = buffer;
    while (written < size) {
        ssize_t n = write(fd, cursor + written, size - written);
        if (n < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (n == 0) {
            return NO;
        }
        written += (size_t)n;
    }
    return YES;
}

@interface FakeGitFeedStore : SSBFeedStore
@property (nonatomic, copy) NSArray<SSBMessage *> *stubMessages;
@property (nonatomic, copy) NSDictionary<NSString *, id> *lastQuery;
@property (nonatomic, copy) NSDictionary<NSString *, id> *lastOptions;
@end

@implementation FakeGitFeedStore

- (NSArray<SSBMessage *> *)querySubset:(NSDictionary<NSString *,id> *)query
                               options:(NSDictionary<NSString *,id> *)options {
    self.lastQuery = query;
    self.lastOptions = options;
    return self.stubMessages ?: @[];
}

@end

@interface FakeGitPublishingClient : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *capturedContent;
@property (nonatomic, copy) NSString *messageKey;
@property (nonatomic, strong) NSError *publishError;
@end

@implementation FakeGitPublishingClient

- (void)publishLocalMessageWithContent:(NSDictionary<NSString *, id> *)content
                            completion:(void (^)(NSError * _Nullable, SSBMessage * _Nullable))completion {
    self.capturedContent = [content copy];
    if (self.publishError) {
        completion(self.publishError, nil);
        return;
    }

    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = self.messageKey ?: @"%published.sha256";
    completion(nil, msg);
}

@end

@interface SSBGitRepoTests : XCTestCase
@property (nonatomic, strong) FakeGitFeedStore *feedStore;
@property (nonatomic, strong) SSBBlobStore *blobStore;
@property (nonatomic, strong) SSBGitObjectStore *objectStore;
@property (nonatomic, strong) SSBGitRepo *repo;
@property (nonatomic, copy) NSString *tempBase;
@end

@implementation SSBGitRepoTests

- (void)setUp {
    [super setUp];

    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    self.tempBase = base;
    self.feedStore = [[FakeGitFeedStore alloc] initWithPath:[base stringByAppendingPathComponent:@"feeds.sqlite3"]];
    self.blobStore = [[SSBBlobStore alloc] initWithPath:[base stringByAppendingPathComponent:@"blobs"]];
    self.objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:self.blobStore];
    self.repo = [[SSBGitRepo alloc] initWithRepoID:@"%testrepo.sha256" feedStore:self.feedStore objectStore:self.objectStore];
}

- (void)tearDown {
    [self.feedStore wipeDatabase];
    [self.blobStore wipeBlobs];
    self.repo = nil;
    self.objectStore = nil;
    self.feedStore = nil;
    self.blobStore = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempBase error:nil];
    self.tempBase = nil;
    [super tearDown];
}

- (SSBMessage *)gitUpdateMessageWithKey:(NSString *)key
                               sequence:(NSInteger)sequence
                         claimedTimestamp:(int64_t)claimedTimestamp
                                    refs:(NSDictionary<NSString *, id> *)refs
                                   packs:(NSArray<NSString *> *)packBlobIDs
                                 indexes:(NSArray<NSString *> *)idxBlobIDs {
    SSBMessage *message = [[SSBMessage alloc] init];
    message.key = key;
    message.author = @"@git-test.ed25519";
    message.sequence = sequence;
    message.claimedTimestamp = claimedTimestamp;
    message.receivedAt = claimedTimestamp;
    message.contentType = @"git-update";

    NSMutableDictionary<NSString *, id> *content = [NSMutableDictionary dictionaryWithDictionary:@{
        @"type": @"git-update",
        @"repo": self.repo.repoID,
        @"refs": refs ?: @{},
    }];

    if (packBlobIDs) {
        NSMutableArray *packs = [NSMutableArray arrayWithCapacity:packBlobIDs.count];
        for (NSString *blobID in packBlobIDs) {
            [packs addObject:@{ @"link": blobID }];
        }
        content[@"packs"] = packs;
    }

    if (idxBlobIDs) {
        NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:idxBlobIDs.count];
        for (NSString *blobID in idxBlobIDs) {
            [indexes addObject:@{ @"link": blobID }];
        }
        content[@"indexes"] = indexes;
    }

    message.content = content;
    message.valueJSON = [NSJSONSerialization dataWithJSONObject:content options:0 error:nil];
    return message;
}

- (NSString *)loadFixtureBlobNamed:(NSString *)fixtureName {
    return [self.blobStore addBlobWithData:SSBGitRepoFixtureData(fixtureName)];
}

- (NSString *)makeShortTemporaryDirectoryWithPrefix:(const char *)prefixTemplate {
    char buffer[PATH_MAX];
    snprintf(buffer, sizeof(buffer), "/tmp/%s", prefixTemplate);
    char *path = mkdtemp(buffer);
    XCTAssertNotEqual(path, NULL);
    return path ? [NSString stringWithUTF8String:path] : nil;
}

- (NSString *)buildHelperBinary {
    NSString *outputPath = [[self makeShortTemporaryDirectoryWithPrefix:"githelper.XXXXXX"] stringByAppendingPathComponent:@"git-remote-ssb"];
    NSString *root = [@__FILE__ stringByDeletingLastPathComponent].stringByDeletingLastPathComponent;
    NSString *mainPath = [root stringByAppendingPathComponent:@"Sources/git-remote-ssb.c"];
    NSString *corePath = [root stringByAppendingPathComponent:@"Sources/SSBGitRemoteCore.c"];
    NSString *includePath = [root stringByAppendingPathComponent:@"Sources"];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/clang"];
    task.arguments = @[ @"-Wall", @"-Wextra", @"-std=c11", @"-I", includePath, mainPath, corePath, @"-o", outputPath ];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardError = stderrPipe;

    NSError *error = nil;
    XCTAssertTrue([task launchAndReturnError:&error], @"Failed to launch clang: %@", error);
    [task waitUntilExit];

    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
    XCTAssertEqual(task.terminationStatus, 0, @"clang failed: %@", stderrText);
    return outputPath;
}

- (NSString *)installStubGitInDirectory:(NSString *)binDir logDir:(NSString *)logDir {
    NSString *scriptPath = [binDir stringByAppendingPathComponent:@"git"];
    NSString *script =
    @"#!/bin/sh\n"
    "set -eu\n"
    "cmd=${1:-}\n"
    "shift || true\n"
    "case \"$cmd\" in\n"
    "  rev-parse)\n"
    "    printf '%s\\n' \"$GIT_STUB_REV_PARSE_SHA\"\n"
    "    ;;\n"
    "  pack-objects)\n"
    "    cat > \"$GIT_STUB_LOG_DIR/pack-objects.stdin\"\n"
    "    cat \"$GIT_STUB_PACK_PAYLOAD_PATH\"\n"
    "    ;;\n"
    "  index-pack)\n"
    "    if [ \"${1:-}\" = \"--stdin\" ]; then\n"
    "      cat > \"$GIT_STUB_LOG_DIR/index-pack.stdin\"\n"
    "    elif [ \"${1:-}\" = \"-o\" ]; then\n"
    "      out=$2\n"
    "      pack_path=$3\n"
    "      cp \"$GIT_STUB_IDX_SOURCE_PATH\" \"$out\"\n"
    "      cp \"$pack_path\" \"$GIT_STUB_LOG_DIR/index-pack.pack\"\n"
    "    else\n"
    "      echo \"unsupported index-pack invocation\" >&2\n"
    "      exit 98\n"
    "    fi\n"
    "    ;;\n"
    "  *)\n"
    "    echo \"unsupported git subcommand: $cmd\" >&2\n"
    "    exit 97\n"
    "    ;;\n"
    "esac\n";

    XCTAssertTrue([script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    XCTAssertEqual(chmod(scriptPath.fileSystemRepresentation, 0755), 0);
    return scriptPath;
}

- (NSDictionary<NSString *, id> *)runHelperAtPath:(NSString *)helperPath
                                            input:(NSString *)input
                                           envAdd:(NSDictionary<NSString *, NSString *> *)envAdd
                                     serverHandler:(void (^)(int clientFD))serverHandler {
    NSString *stateHome = [self makeShortTemporaryDirectoryWithPrefix:"ssbstate.XXXXXX"];
    NSString *socketDir = [stateHome stringByAppendingPathComponent:@"scuttle"];
    NSString *socketPath = [socketDir stringByAppendingPathComponent:@"scuttle_helper.sock"];
    [[NSFileManager defaultManager] createDirectoryAtPath:socketDir withIntermediateDirectories:YES attributes:nil error:nil];

    int serverFD = socket(AF_UNIX, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(serverFD, 0);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, socketPath.fileSystemRepresentation, sizeof(addr.sun_path));

    unlink(addr.sun_path);
    XCTAssertEqual(bind(serverFD, (struct sockaddr *)&addr, sizeof(addr)), 0);
    XCTAssertEqual(listen(serverFD, 1), 0);

    XCTestExpectation *serverFinished = [self expectationWithDescription:@"helper server finished"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        int clientFD = accept(serverFD, NULL, NULL);
        if (clientFD >= 0) {
            serverHandler(clientFD);
            close(clientFD);
        }
        close(serverFD);
        unlink(addr.sun_path);
        [serverFinished fulfill];
    });

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:helperPath];
    task.arguments = @[ @"origin", @"ssb://%testrepo.sha256" ];

    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionaryWithDictionary:NSProcessInfo.processInfo.environment];
    env[@"XDG_STATE_HOME"] = stateHome;
    [env addEntriesFromDictionary:envAdd ?: @{}];
    task.environment = env;

    NSPipe *stdinPipe = [NSPipe pipe];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardInput = stdinPipe;
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    NSError *error = nil;
    XCTAssertTrue([task launchAndReturnError:&error], @"Failed to launch helper: %@", error);
    [[stdinPipe fileHandleForWriting] writeData:[input dataUsingEncoding:NSUTF8StringEncoding]];
    [[stdinPipe fileHandleForWriting] closeFile];

    [task waitUntilExit];
    [self waitForExpectations:@[serverFinished] timeout:5.0];

    NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];

    return @{
        @"status": @(task.terminationStatus),
        @"stdout": [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"",
        @"stderr": [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"",
        @"stateHome": stateHome,
    };
}

- (void)testCurrentRefsEmpty {
    NSDictionary *refs = [self.repo currentRefs];
    XCTAssertEqual(refs.count, 0);
}

- (void)testUpdateMessagesEmpty {
    NSArray *updates = [self.repo updateMessages];
    XCTAssertEqual(updates.count, 0);
    XCTAssertEqualObjects(self.feedStore.lastOptions[@"descending"], @YES);
}

- (void)testObjectStoreResolvesFixtureObjectsAfterRegistration {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();
    NSString *packBlobID = [self loadFixtureBlobNamed:@"delta-ref.pack"];
    NSString *idxBlobID = [self loadFixtureBlobNamed:@"delta-ref.idx"];

    [self.objectStore registerPackBlob:packBlobID idxBlob:idxBlobID];

    XCTAssertEqualObjects([self.objectStore packBlobIDForSHA1:manifest[@"blob_file2_updated"]], packBlobID);
    SSBGitObject *object = [self.objectStore objectForSHA1:manifest[@"blob_file2_updated"]];
    XCTAssertEqual(object.type, SSBGitObjectTypeBlob);
    XCTAssertEqualObjects(object.data, SSBGitRepoExpectedFixtureBlob(300));
}

- (void)testCurrentRefsApplyReverseChronologicalMergeRulesAndTombstones {
    SSBMessage *older = [self gitUpdateMessageWithKey:@"%older.sha256"
                                             sequence:1
                                       claimedTimestamp:100
                                                  refs:@{
                                                      @"refs/heads/main": @"1111111111111111111111111111111111111111",
                                                      @"refs/heads/feature": @"2222222222222222222222222222222222222222",
                                                      @"refs/tags/v1": @"3333333333333333333333333333333333333333",
                                                  }
                                                 packs:nil
                                               indexes:nil];
    SSBMessage *newer = [self gitUpdateMessageWithKey:@"%newer.sha256"
                                             sequence:2
                                       claimedTimestamp:200
                                                  refs:@{
                                                      @"refs/heads/main": @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                                      @"refs/tags/v1": [NSNull null],
                                                  }
                                                 packs:nil
                                               indexes:nil];
    self.feedStore.stubMessages = @[ newer, older ];

    NSDictionary<NSString *, NSString *> *refs = [self.repo currentRefs];

    XCTAssertEqualObjects(refs[@"refs/heads/main"], @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    XCTAssertEqualObjects(refs[@"refs/heads/feature"], @"2222222222222222222222222222222222222222");
    XCTAssertNil(refs[@"refs/tags/v1"]);
}

- (void)testCurrentRefsRegistersPackIndexSideEffects {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();
    NSString *packBlobID = [self loadFixtureBlobNamed:@"delta-ref.pack"];
    NSString *idxBlobID = [self loadFixtureBlobNamed:@"delta-ref.idx"];
    self.feedStore.stubMessages = @[
        [self gitUpdateMessageWithKey:@"%fixture.sha256"
                             sequence:1
                       claimedTimestamp:100
                                  refs:@{ @"refs/heads/main": manifest[@"commit_head"] }
                                 packs:@[ packBlobID ]
                               indexes:@[ idxBlobID ]]
    ];

    NSDictionary<NSString *, NSString *> *refs = [self.repo currentRefs];

    XCTAssertEqualObjects(refs[@"refs/heads/main"], manifest[@"commit_head"]);
    XCTAssertEqualObjects([self.objectStore packBlobIDForSHA1:manifest[@"blob_base"]], packBlobID);
    XCTAssertEqualObjects([self.objectStore objectForSHA1:manifest[@"blob_base"]].data, SSBGitRepoExpectedFixtureBlob(0));
}

- (void)testPublishUpdateIncludesRepoBranchFromNewestMessage {
    self.feedStore.stubMessages = @[
        [self gitUpdateMessageWithKey:@"%previous.sha256"
                             sequence:2
                       claimedTimestamp:200
                                  refs:@{ @"refs/heads/main": @"old" }
                                 packs:nil
                               indexes:nil]
    ];

    FakeGitPublishingClient *client = [[FakeGitPublishingClient alloc] init];
    XCTestExpectation *published = [self expectationWithDescription:@"publish completion"];

    [self.repo publishUpdateWithRefs:@{ @"refs/heads/main": @"new" }
                               packs:@[ @"&pack.sha256" ]
                             indexes:@[ @"&idx.sha256" ]
                              client:(SSBRoomClient *)client
                          completion:^(NSString * _Nullable msgID, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(msgID, @"%published.sha256");
        [published fulfill];
    }];

    [self waitForExpectations:@[published] timeout:2.0];
    XCTAssertEqualObjects(client.capturedContent[@"repoBranch"], (@[@"%previous.sha256"]));
    XCTAssertEqualObjects(client.capturedContent[@"refs"][@"refs/heads/main"], @"new");
    XCTAssertEqualObjects(client.capturedContent[@"packs"], (@[@{ @"link": @"&pack.sha256" }]));
    XCTAssertEqualObjects(client.capturedContent[@"indexes"], (@[@{ @"link": @"&idx.sha256" }]));
}

- (void)testRemoteHelperListTranslatesRefsFromSocketServer {
    NSString *helperPath = [self buildHelperBinary];
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();

    NSDictionary<NSString *, id> *result = [self runHelperAtPath:helperPath
                                                           input:@"list\n\n"
                                                          envAdd:nil
                                                    serverHandler:^(int clientFD) {
        char line[1024];
        XCTAssertGreaterThan(SSBGitReadLineFD(clientFD, line, sizeof(line)), 0);
        XCTAssertEqualObjects([NSString stringWithUTF8String:line], @"LIST %testrepo.sha256\n");
        dprintf(clientFD, "refs/heads/main %s\n", manifest[@"commit_head"].UTF8String);
        dprintf(clientFD, "refs/tags/v1 %s\n", manifest[@"commit_previous"].UTF8String);
        dprintf(clientFD, "END\n");
    }];

    XCTAssertEqualObjects(result[@"status"], @0);
    XCTAssertEqualObjects(result[@"stderr"], @"");
    NSString *stdout = result[@"stdout"];
    NSString *expectedMainLine = [NSString stringWithFormat:@"%@ refs/heads/main", manifest[@"commit_head"]];
    NSString *expectedTagLine = [NSString stringWithFormat:@"%@ refs/tags/v1", manifest[@"commit_previous"]];
    XCTAssertTrue([stdout containsString:expectedMainLine]);
    XCTAssertTrue([stdout containsString:expectedTagLine]);
}

- (void)testRemoteHelperFetchStreamsPackPayloadToIndexPack {
    NSString *helperPath = [self buildHelperBinary];
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();
    NSString *baseDir = [self makeShortTemporaryDirectoryWithPrefix:"gitstub.XXXXXX"];
    NSString *binDir = [baseDir stringByAppendingPathComponent:@"bin"];
    NSString *logDir = [baseDir stringByAppendingPathComponent:@"log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:binDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    [self installStubGitInDirectory:binDir logDir:logDir];

    NSString *packPath = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.pack"];
    NSString *idxPath = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.idx"];
    NSData *packData = [NSData dataWithContentsOfFile:packPath];

    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", binDir, NSProcessInfo.processInfo.environment[@"PATH"] ?: @"/usr/bin:/bin"];
    env[@"GIT_STUB_LOG_DIR"] = logDir;
    env[@"GIT_STUB_PACK_PAYLOAD_PATH"] = packPath;
    env[@"GIT_STUB_IDX_SOURCE_PATH"] = idxPath;
    env[@"GIT_STUB_REV_PARSE_SHA"] = manifest[@"commit_head"];

    NSDictionary<NSString *, id> *result = [self runHelperAtPath:helperPath
                                                           input:[NSString stringWithFormat:@"fetch %@ refs/heads/main\n\n", manifest[@"blob_file2_updated"]]
                                                          envAdd:env
                                                    serverHandler:^(int clientFD) {
        char line[1024];
        XCTAssertGreaterThan(SSBGitReadLineFD(clientFD, line, sizeof(line)), 0);
        NSString *expected = [NSString stringWithFormat:@"FETCH_SHA %%testrepo.sha256 %@\n", manifest[@"blob_file2_updated"]];
        XCTAssertEqualObjects([NSString stringWithUTF8String:line], expected);
        dprintf(clientFD, "SEND_PACK %zu\n", packData.length);
        XCTAssertTrue(SSBGitWriteExactFD(clientFD, packData.bytes, packData.length));
    }];

    XCTAssertEqualObjects(result[@"status"], @0);
    NSData *captured = [NSData dataWithContentsOfFile:[logDir stringByAppendingPathComponent:@"index-pack.stdin"]];
    XCTAssertEqualObjects(captured, packData);
}

- (void)testRemoteHelperPushSendsPackAndIndexPayloadsWithoutCorruptingPackStream {
    NSString *helperPath = [self buildHelperBinary];
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();
    NSString *baseDir = [self makeShortTemporaryDirectoryWithPrefix:"gitpush.XXXXXX"];
    NSString *binDir = [baseDir stringByAppendingPathComponent:@"bin"];
    NSString *logDir = [baseDir stringByAppendingPathComponent:@"log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:binDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    [self installStubGitInDirectory:binDir logDir:logDir];

    NSString *packPath = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.pack"];
    NSString *idxPath = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.idx"];
    NSData *packData = [NSData dataWithContentsOfFile:packPath];
    NSData *idxData = [NSData dataWithContentsOfFile:idxPath];

    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", binDir, NSProcessInfo.processInfo.environment[@"PATH"] ?: @"/usr/bin:/bin"];
    env[@"GIT_STUB_LOG_DIR"] = logDir;
    env[@"GIT_STUB_PACK_PAYLOAD_PATH"] = packPath;
    env[@"GIT_STUB_IDX_SOURCE_PATH"] = idxPath;
    env[@"GIT_STUB_REV_PARSE_SHA"] = manifest[@"commit_head"];

    NSDictionary<NSString *, id> *result = [self runHelperAtPath:helperPath
                                                           input:@"push HEAD:refs/heads/main\n\n"
                                                          envAdd:env
                                                    serverHandler:^(int clientFD) {
        char line[1024];
        XCTAssertGreaterThan(SSBGitReadLineFD(clientFD, line, sizeof(line)), 0);
        NSString *prefix = [NSString stringWithFormat:@"PUSH %%testrepo.sha256 refs/heads/main %@ ", manifest[@"commit_head"]];
        XCTAssertTrue([[NSString stringWithUTF8String:line] hasPrefix:prefix]);

        NSArray<NSString *> *parts = [[[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@" "];
        XCTAssertEqual(parts.count, 6UL);

        size_t incomingPackSize = (size_t)[parts[4] integerValue];
        size_t incomingIdxSize = (size_t)[parts[5] integerValue];
        XCTAssertEqual(incomingPackSize, packData.length);
        XCTAssertEqual(incomingIdxSize, idxData.length);

        NSMutableData *incomingPack = [NSMutableData dataWithLength:incomingPackSize];
        NSMutableData *incomingIdx = [NSMutableData dataWithLength:incomingIdxSize];
        XCTAssertTrue(SSBGitReadExactFD(clientFD, incomingPack.mutableBytes, incomingPackSize));
        XCTAssertTrue(SSBGitReadExactFD(clientFD, incomingIdx.mutableBytes, incomingIdxSize));
        XCTAssertEqualObjects(incomingPack, packData);
        XCTAssertEqualObjects(incomingIdx, idxData);
        dprintf(clientFD, "OK\n");
    }];

    XCTAssertEqualObjects(result[@"status"], @0);
    XCTAssertTrue([result[@"stdout"] containsString:@"ok refs/heads/main"]);
    NSData *packObjectsInput = [NSData dataWithContentsOfFile:[logDir stringByAppendingPathComponent:@"pack-objects.stdin"]];
    NSData *expectedPackObjectsInput = [[NSString stringWithFormat:@"%@\n", manifest[@"commit_head"]] dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(packObjectsInput, expectedPackObjectsInput);
}

- (void)testRemoteHelperIgnoresMalformedFetchResponses {
    NSString *helperPath = [self buildHelperBinary];
    NSDictionary<NSString *, NSString *> *manifest = SSBGitRepoManifest();
    NSString *baseDir = [self makeShortTemporaryDirectoryWithPrefix:"gitbad.XXXXXX"];
    NSString *binDir = [baseDir stringByAppendingPathComponent:@"bin"];
    NSString *logDir = [baseDir stringByAppendingPathComponent:@"log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:binDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    [self installStubGitInDirectory:binDir logDir:logDir];

    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", binDir, NSProcessInfo.processInfo.environment[@"PATH"] ?: @"/usr/bin:/bin"];
    env[@"GIT_STUB_LOG_DIR"] = logDir;
    env[@"GIT_STUB_PACK_PAYLOAD_PATH"] = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.pack"];
    env[@"GIT_STUB_IDX_SOURCE_PATH"] = [SSBGitRepoFixtureDirectory() stringByAppendingPathComponent:@"delta-ref.idx"];
    env[@"GIT_STUB_REV_PARSE_SHA"] = manifest[@"commit_head"];

    NSDictionary<NSString *, id> *result = [self runHelperAtPath:helperPath
                                                           input:[NSString stringWithFormat:@"fetch %@ refs/heads/main\n\n", manifest[@"blob_base"]]
                                                          envAdd:env
                                                    serverHandler:^(int clientFD) {
        char line[1024];
        XCTAssertGreaterThan(SSBGitReadLineFD(clientFD, line, sizeof(line)), 0);
        dprintf(clientFD, "BROKEN_RESPONSE\n");
    }];

    XCTAssertEqualObjects(result[@"status"], @0);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[logDir stringByAppendingPathComponent:@"index-pack.stdin"]]);
}

@end
