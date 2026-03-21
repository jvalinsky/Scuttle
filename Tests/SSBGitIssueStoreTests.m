#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBGitIssueStore.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBMessage.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBFeedCodecRegistry.h>

@interface MockIssueCodec : NSObject <SSBFeedCodec>
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end
@implementation MockIssueCodec
- (BOOL)verifyMessageData:(NSData *)d error:(NSError **)e { return YES; }
- (nullable NSData *)computeMessageKeyFromData:(NSData *)d error:(NSError **)e {
    return [@"%mock.sha256" dataUsingEncoding:NSUTF8StringEncoding];
}
- (SSBBFEMessageFormat)messageFormat { return SSBBFEMessageFormatClassic; }
@end

/// Inserts a message into the given feed store.
static BOOL insertMsg(SSBFeedStore *store, NSString *key, NSString *author,
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

@interface SSBGitIssueStoreTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, strong) SSBGitIssueStore *issueStore;
@property (nonatomic, copy) NSString *repoID;
@end

@implementation SSBGitIssueStoreTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"issues_%@.db", [[NSUUID UUID] UUIDString]]];
    self.feedStore = [[SSBFeedStore alloc] initWithPath:self.dbPath];
    [self.feedStore wipeDatabase];

    MockIssueCodec *codec = [[MockIssueCodec alloc] init];
    codec.feedFormat = SSBBFEFeedFormatClassic;
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:codec];

    self.repoID = @"%repo1.sha256";
    self.issueStore = [[SSBGitIssueStore alloc] initWithRepoID:self.repoID
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
    XCTAssertEqualObjects(self.issueStore.repoID, self.repoID);
}

- (void)testFeedStore_matchesInit {
    XCTAssertEqual(self.issueStore.feedStore, self.feedStore);
}

#pragma mark - issues

- (void)testIssues_emptyDB {
    XCTAssertEqualObjects([self.issueStore issues], @[]);
}

- (void)testIssues_returnsMatchingIssues {
    insertMsg(self.feedStore, @"%i1.sha256", @"@alice.ed25519", 1, nil,
              @{@"type": @"issue", @"repo": self.repoID, @"title": @"Bug"});
    NSArray *issues = [self.issueStore issues];
    XCTAssertEqual(issues.count, 1U);
    XCTAssertEqualObjects([issues.firstObject content][@"title"], @"Bug");
}

- (void)testIssues_excludesOtherRepo {
    insertMsg(self.feedStore, @"%i1.sha256", @"@alice.ed25519", 1, nil,
              @{@"type": @"issue", @"repo": @"%otherRepo.sha256", @"title": @"Other"});
    XCTAssertEqualObjects([self.issueStore issues], @[]);
}

#pragma mark - editsForIssue

- (void)testEditsForIssue_empty {
    XCTAssertEqualObjects([self.issueStore editsForIssue:@"%i1.sha256"], @[]);
}

- (void)testEditsForIssue_returnsEdits {
    insertMsg(self.feedStore, @"%e1.sha256", @"@alice.ed25519", 1, nil,
              @{@"type": @"issue-edit", @"root": @"%i1.sha256", @"title": @"Updated"});
    NSArray *edits = [self.issueStore editsForIssue:@"%i1.sha256"];
    XCTAssertEqual(edits.count, 1U);
}

- (void)testEditsForIssue_excludesOtherIssue {
    insertMsg(self.feedStore, @"%e1.sha256", @"@alice.ed25519", 1, nil,
              @{@"type": @"issue-edit", @"root": @"%otherIssue.sha256"});
    XCTAssertEqualObjects([self.issueStore editsForIssue:@"%i1.sha256"], @[]);
}

#pragma mark - commentsForIssue

- (void)testCommentsForIssue_empty {
    XCTAssertEqualObjects([self.issueStore commentsForIssue:@"%i1.sha256"], @[]);
}

- (void)testCommentsForIssue_returnsPosts {
    insertMsg(self.feedStore, @"%c1.sha256", @"@bob.ed25519", 1, nil,
              @{@"type": @"post", @"root": @"%i1.sha256", @"text": @"LGTM"});
    NSArray *comments = [self.issueStore commentsForIssue:@"%i1.sha256"];
    XCTAssertEqual(comments.count, 1U);
    XCTAssertEqualObjects([comments.firstObject content][@"text"], @"LGTM");
}

@end
