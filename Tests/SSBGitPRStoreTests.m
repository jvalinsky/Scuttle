#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBGitPRStore.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBMessage.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBFeedCodecRegistry.h>

@interface MockPRCodec : NSObject <SSBFeedCodec>
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end
@implementation MockPRCodec
- (BOOL)verifyMessageData:(NSData *)d error:(NSError **)e { return YES; }
- (nullable NSData *)computeMessageKeyFromData:(NSData *)d error:(NSError **)e {
    return [@"%mock.sha256" dataUsingEncoding:NSUTF8StringEncoding];
}
- (SSBBFEMessageFormat)messageFormat { return SSBBFEMessageFormatClassic; }
@end

static BOOL insertPRMsg(SSBFeedStore *store, NSString *key, NSString *author,
                        NSInteger seq, NSString *prev, NSDictionary *content) {
    SSBMessage *m = [[SSBMessage alloc] init];
    m.key = key;
    m.author = author;
    m.sequence = seq;
    m.previousKey = prev;
    m.claimedTimestamp = (int64_t)(seq * 1000);
    m.valueJSON = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    m.content = content;
    m.contentType = content[@"type"];
    m.feedFormat = SSBBFEFeedFormatClassic;
    return [store appendMessage:m error:nil];
}

@interface SSBGitPRStoreTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, strong) SSBGitPRStore *prStore;
@property (nonatomic, copy) NSString *repoID;
@end

@implementation SSBGitPRStoreTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"prs_%@.db", [[NSUUID UUID] UUIDString]]];
    self.feedStore = [[SSBFeedStore alloc] initWithPath:self.dbPath];
    [self.feedStore wipeDatabase];

    MockPRCodec *codec = [[MockPRCodec alloc] init];
    codec.feedFormat = SSBBFEFeedFormatClassic;
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:codec];

    self.repoID = @"%repo42.sha256";
    self.prStore = [[SSBGitPRStore alloc] initWithRepoID:self.repoID
                                               feedStore:self.feedStore];
}

- (void)tearDown {
    [self.feedStore wipeDatabase];
    self.feedStore = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Properties

- (void)testRepoID_matchesInit {
    XCTAssertEqualObjects(self.prStore.repoID, self.repoID);
}

- (void)testFeedStore_matchesInit {
    XCTAssertEqual(self.prStore.feedStore, self.feedStore);
}

#pragma mark - pullRequests

- (void)testPullRequests_emptyDB {
    XCTAssertEqualObjects([self.prStore pullRequests], @[]);
}

- (void)testPullRequests_returnsMatchingPRs {
    insertPRMsg(self.feedStore, @"%pr1.sha256", @"@alice.ed25519", 1, nil,
                @{@"type": @"pull-request", @"repo": self.repoID, @"title": @"Feature A"});
    NSArray *prs = [self.prStore pullRequests];
    XCTAssertEqual(prs.count, 1U);
    XCTAssertEqualObjects([prs.firstObject content][@"title"], @"Feature A");
}

- (void)testPullRequests_excludesOtherRepo {
    insertPRMsg(self.feedStore, @"%pr1.sha256", @"@alice.ed25519", 1, nil,
                @{@"type": @"pull-request", @"repo": @"%otherRepo.sha256"});
    XCTAssertEqualObjects([self.prStore pullRequests], @[]);
}

#pragma mark - commentsForPR

- (void)testCommentsForPR_empty {
    XCTAssertEqualObjects([self.prStore commentsForPR:@"%pr1.sha256"], @[]);
}

- (void)testCommentsForPR_returnsPosts {
    insertPRMsg(self.feedStore, @"%c1.sha256", @"@bob.ed25519", 1, nil,
                @{@"type": @"post", @"root": @"%pr1.sha256", @"text": @"Looks good"});
    NSArray *comments = [self.prStore commentsForPR:@"%pr1.sha256"];
    XCTAssertEqual(comments.count, 1U);
    XCTAssertEqualObjects([comments.firstObject content][@"text"], @"Looks good");
}

- (void)testCommentsForPR_excludesOtherRoot {
    insertPRMsg(self.feedStore, @"%c1.sha256", @"@bob.ed25519", 1, nil,
                @{@"type": @"post", @"root": @"%otherPR.sha256"});
    XCTAssertEqualObjects([self.prStore commentsForPR:@"%pr1.sha256"], @[]);
}

@end
