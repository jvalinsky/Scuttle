#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBFeedStore.h>

/// Builds a minimal SSBMessage suitable for insertion into an isolated store.
static SSBMessage *MakeMessage(NSString *key, NSString *author, NSInteger sequence,
                               NSString *previousKey, NSString *contentType,
                               NSDictionary *content) {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = key;
    msg.author = author;
    msg.sequence = sequence;
    msg.previousKey = previousKey;
    msg.contentType = contentType;
    msg.content = content;
    msg.claimedTimestamp = (int64_t)(sequence * 1000);
    msg.valueJSON = [NSJSONSerialization dataWithJSONObject:@{@"author": author, @"sequence": @(sequence)} options:0 error:nil];
    return msg;
}

@interface SSBFeedStoreQueryTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *store;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation SSBFeedStoreQueryTests

- (void)setUp {
    [super setUp];
    // Use a unique temp file per test so tests are fully isolated.
    NSString *tmp = NSTemporaryDirectory();
    self.dbPath = [tmp stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"test_feedstore_%@.db", [[NSUUID UUID] UUIDString]]];
    self.store = [[SSBFeedStore alloc] initWithPath:self.dbPath];
    XCTAssertNotNil(self.store, @"Store must open successfully");
}

- (void)tearDown {
    [self.store wipeDatabase];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - appendMessage:error:

- (void)testAppendFirstMessage_succeeds {
    SSBMessage *msg = MakeMessage(@"%first.sha256", @"@alice.ed25519", 1, nil, @"post",
                                  @{@"type": @"post", @"text": @"hello"});
    NSError *err = nil;
    BOOL ok = [self.store appendMessage:msg error:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
}

- (void)testAppendSequentialMessages_succeed {
    NSString *author = @"@bob.ed25519";
    NSError *err = nil;

    SSBMessage *m1 = MakeMessage(@"%seq1.sha256", author, 1, nil, @"post",
                                 @{@"type": @"post", @"text": @"first"});
    XCTAssertTrue([self.store appendMessage:m1 error:&err]);

    SSBMessage *m2 = MakeMessage(@"%seq2.sha256", author, 2, @"%seq1.sha256", @"post",
                                 @{@"type": @"post", @"text": @"second"});
    XCTAssertTrue([self.store appendMessage:m2 error:&err]);
    XCTAssertNil(err);
}

- (void)testAppendDuplicateKey_returnsErrorCode6 {
    NSString *author = @"@carol.ed25519";
    SSBMessage *m1 = MakeMessage(@"%dup.sha256", author, 1, nil, @"post",
                                 @{@"type": @"post", @"text": @"once"});
    NSError *err = nil;
    [self.store appendMessage:m1 error:&err];

    // Same sequence = past/duplicate → error code 6
    SSBMessage *m1dup = MakeMessage(@"%dup2.sha256", author, 1, nil, @"post",
                                    @{@"type": @"post", @"text": @"twice"});
    BOOL ok = [self.store appendMessage:m1dup error:&err];
    XCTAssertFalse(ok);
    XCTAssertNotNil(err);
    XCTAssertEqual(err.code, 6);
}

- (void)testAppendPastSequence_returnsErrorCode6 {
    NSString *author = @"@dave.ed25519";
    NSError *err = nil;

    SSBMessage *m1 = MakeMessage(@"%d1.sha256", author, 1, nil, @"post", @{@"type": @"post"});
    SSBMessage *m2 = MakeMessage(@"%d2.sha256", author, 2, @"%d1.sha256", @"post", @{@"type": @"post"});
    [self.store appendMessage:m1 error:nil];
    [self.store appendMessage:m2 error:nil];

    // Sequence 1 is now in the past
    SSBMessage *past = MakeMessage(@"%dpast.sha256", author, 1, nil, @"post", @{@"type": @"post"});
    BOOL ok = [self.store appendMessage:past error:&err];
    XCTAssertFalse(ok);
    XCTAssertEqual(err.code, 6);
}

- (void)testAppendOutOfOrderMessage_goesToQuarantine {
    NSString *author = @"@eve.ed25519";
    NSError *err = nil;

    // sequence 2 before sequence 1 — should quarantine (return YES, no error)
    SSBMessage *m2 = MakeMessage(@"%e2.sha256", author, 2, @"%e1.sha256", @"post",
                                 @{@"type": @"post", @"text": @"out of order"});
    BOOL ok = [self.store appendMessage:m2 error:&err];
    XCTAssertTrue(ok);  // quarantine succeeds
    XCTAssertNil(err);
}

- (void)testQuarantineReleasedWhenPredecessorArrives {
    NSString *author = @"@frank.ed25519";

    // Deliver seq 2 first → quarantined
    SSBMessage *m2 = MakeMessage(@"%f2.sha256", author, 2, @"%f1.sha256", @"post",
                                 @{@"type": @"post", @"text": @"second"});
    [self.store appendMessage:m2 error:nil];

    // Now deliver seq 1 → should drain quarantine
    SSBMessage *m1 = MakeMessage(@"%f1.sha256", author, 1, nil, @"post",
                                 @{@"type": @"post", @"text": @"first"});
    NSError *err = nil;
    BOOL ok = [self.store appendMessage:m1 error:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);

    // Feed state should now reflect sequence 2
    SSBFeedState *state = [self.store feedStateForAuthor:author];
    XCTAssertNotNil(state);
    XCTAssertEqual(state.maxSequence, 2);
}

#pragma mark - feedForAuthor:limit:

- (void)testFeedForAuthor_returnsMessagesInReverseChronologicalOrder {
    NSString *author = @"@gina.ed25519";
    for (NSInteger i = 1; i <= 5; i++) {
        NSString *prevKey = (i > 1) ? [NSString stringWithFormat:@"%%g%ld.sha256", (long)(i-1)] : nil;
        SSBMessage *m = MakeMessage([NSString stringWithFormat:@"%%g%ld.sha256", (long)i],
                                    author, i, prevKey, @"post", @{@"type": @"post"});
        [self.store appendMessage:m error:nil];
    }

    NSArray<SSBMessage *> *feed = [self.store feedForAuthor:author limit:3];
    XCTAssertEqual(feed.count, 3);
    // Reverse chronological: seq 5, 4, 3
    XCTAssertEqual(feed[0].sequence, 5);
    XCTAssertEqual(feed[1].sequence, 4);
    XCTAssertEqual(feed[2].sequence, 3);
}

- (void)testFeedForAuthor_unknownAuthorReturnsEmpty {
    NSArray *feed = [self.store feedForAuthor:@"@nobody.ed25519" limit:10];
    XCTAssertNotNil(feed);
    XCTAssertEqual(feed.count, 0);
}

#pragma mark - recentMessagesWithLimit:

- (void)testRecentMessagesWithLimit_acrossAllFeeds {
    // Two authors
    SSBMessage *a1 = MakeMessage(@"%a1.sha256", @"@ha.ed25519", 1, nil, @"post", @{@"type": @"post"});
    SSBMessage *b1 = MakeMessage(@"%b1.sha256", @"@hb.ed25519", 1, nil, @"post", @{@"type": @"post"});
    [self.store appendMessage:a1 error:nil];
    [self.store appendMessage:b1 error:nil];

    NSArray<SSBMessage *> *recent = [self.store recentMessagesWithLimit:10];
    XCTAssertGreaterThanOrEqual(recent.count, 2);
}

- (void)testRecentMessagesWithLimit_respectsLimit {
    NSString *author = @"@many.ed25519";
    for (NSInteger i = 1; i <= 10; i++) {
        NSString *prev = (i > 1) ? [NSString stringWithFormat:@"%%m%ld.sha256", (long)(i-1)] : nil;
        SSBMessage *m = MakeMessage([NSString stringWithFormat:@"%%m%ld.sha256", (long)i],
                                    author, i, prev, @"post", @{@"type": @"post"});
        [self.store appendMessage:m error:nil];
    }
    NSArray<SSBMessage *> *recent = [self.store recentMessagesWithLimit:5];
    XCTAssertEqual(recent.count, 5);
}

#pragma mark - timelineWithLimit: (followed authors only)

- (void)testTimelineWithLimit_onlyIncludesFollowedAuthors {
    NSString *followed = @"@followed.ed25519";
    NSString *unfollowed = @"@unfollowed.ed25519";

    SSBMessage *fm = MakeMessage(@"%fm1.sha256", followed, 1, nil, @"post", @{@"type": @"post", @"text": @"followed post"});
    SSBMessage *um = MakeMessage(@"%um1.sha256", unfollowed, 1, nil, @"post", @{@"type": @"post", @"text": @"unfollowed post"});
    [self.store appendMessage:fm error:nil];
    [self.store appendMessage:um error:nil];

    [self.store setFollowing:YES forAuthor:followed atSequence:1];

    NSArray<SSBMessage *> *timeline = [self.store timelineWithLimit:100];
    for (SSBMessage *msg in timeline) {
        XCTAssertEqualObjects(msg.author, followed, @"Timeline must only contain messages from followed authors");
    }
}

#pragma mark - searchMessages:limit:

- (void)testSearchMessages_findsMatchingText {
    SSBMessage *m = MakeMessage(@"%srch1.sha256", @"@searcher.ed25519", 1, nil, @"post",
                                @{@"type": @"post", @"text": @"unique_search_term_xyz"});
    [self.store appendMessage:m error:nil];

    NSArray<SSBMessage *> *results = [self.store searchMessages:@"unique_search_term_xyz" limit:10];
    XCTAssertGreaterThanOrEqual(results.count, 1);
}

- (void)testSearchMessages_noMatchReturnsEmpty {
    NSArray<SSBMessage *> *results = [self.store searchMessages:@"absolutely_not_present_99zz" limit:10];
    XCTAssertNotNil(results);
    XCTAssertEqual(results.count, 0);
}

#pragma mark - querySubset:options: (ssb-ql-0, SIP-3)

- (void)testQuerySubset_byAuthor {
    NSString *author = @"@qsub.ed25519";
    SSBMessage *m = MakeMessage(@"%qs1.sha256", author, 1, nil, @"post",
                                @{@"type": @"post", @"text": @"query test"});
    [self.store appendMessage:m error:nil];

    NSDictionary *query = @{@"author": author};
    NSArray<SSBMessage *> *results = [self.store querySubset:query options:@{}];
    XCTAssertGreaterThanOrEqual(results.count, 1);
    for (SSBMessage *msg in results) {
        XCTAssertEqualObjects(msg.author, author);
    }
}

- (void)testQuerySubset_byContentType {
    NSString *author = @"@qtype.ed25519";
    SSBMessage *post = MakeMessage(@"%qtype_post.sha256", author, 1, nil, @"post",
                                   @{@"type": @"post", @"text": @"hello"});
    SSBMessage *contact = MakeMessage(@"%qtype_contact.sha256", author, 2, @"%qtype_post.sha256",
                                      @"contact", @{@"type": @"contact", @"contact": @"@other.ed25519", @"following": @YES});
    [self.store appendMessage:post error:nil];
    [self.store appendMessage:contact error:nil];

    NSDictionary *query = @{@"author": author, @"contentType": @"contact"};
    NSArray<SSBMessage *> *results = [self.store querySubset:query options:@{}];
    XCTAssertEqual(results.count, 1);
    XCTAssertEqualObjects(results[0].contentType, @"contact");
}

- (void)testQuerySubset_pageSize {
    NSString *author = @"@qpage.ed25519";
    for (NSInteger i = 1; i <= 5; i++) {
        NSString *prev = (i > 1) ? [NSString stringWithFormat:@"%%qp%ld.sha256", (long)(i-1)] : nil;
        SSBMessage *m = MakeMessage([NSString stringWithFormat:@"%%qp%ld.sha256", (long)i],
                                    author, i, prev, @"post", @{@"type": @"post"});
        [self.store appendMessage:m error:nil];
    }
    NSDictionary *query = @{@"author": author};
    NSDictionary *options = @{@"pageSize": @2};
    NSArray<SSBMessage *> *results = [self.store querySubset:query options:options];
    XCTAssertEqual(results.count, 2);
}

#pragma mark - followedAuthors

- (void)testFollowedAuthors_includesFollowedExcludesUnfollowed {
    [self.store setFollowing:YES forAuthor:@"@fa1.ed25519" atSequence:1];
    [self.store setFollowing:YES forAuthor:@"@fa2.ed25519" atSequence:1];
    [self.store setFollowing:NO forAuthor:@"@fa3.ed25519" atSequence:1];

    NSArray<NSString *> *followed = [self.store followedAuthors];
    XCTAssertTrue([followed containsObject:@"@fa1.ed25519"]);
    XCTAssertTrue([followed containsObject:@"@fa2.ed25519"]);
    XCTAssertFalse([followed containsObject:@"@fa3.ed25519"]);
}

#pragma mark - allChannels

- (void)testAllChannels_returnsChannelNamesFromPostMessages {
    NSDictionary *content = @{@"type": @"post", @"text": @"hello", @"channel": @"ssb-protocol"};
    SSBMessage *m = MakeMessage(@"%chan1.sha256", @"@channy.ed25519", 1, nil, @"post", content);
    [self.store appendMessage:m error:nil];

    NSArray<NSString *> *channels = [self.store allChannels];
    XCTAssertTrue([channels containsObject:@"ssb-protocol"],
                  @"Channel 'ssb-protocol' should appear in allChannels");
}

#pragma mark - totalMessageCount

- (void)testTotalMessageCount_incrementsOnAppend {
    NSInteger before = [self.store totalMessageCount];

    SSBMessage *m = MakeMessage(@"%count1.sha256", @"@counter.ed25519", 1, nil, @"post",
                                @{@"type": @"post"});
    [self.store appendMessage:m error:nil];

    NSInteger after = [self.store totalMessageCount];
    XCTAssertEqual(after, before + 1);
}

#pragma mark - messagesOfType:limit:

- (void)testMessagesOfType_returnsOnlyMatchingType {
    NSString *author = @"@typed.ed25519";
    SSBMessage *postMsg = MakeMessage(@"%t_post.sha256", author, 1, nil, @"post",
                                      @{@"type": @"post", @"text": @"post"});
    SSBMessage *contactMsg = MakeMessage(@"%t_contact.sha256", author, 2, @"%t_post.sha256",
                                          @"contact", @{@"type": @"contact", @"contact": @"@x.ed25519", @"following": @YES});
    [self.store appendMessage:postMsg error:nil];
    [self.store appendMessage:contactMsg error:nil];

    NSArray<SSBMessage *> *contacts = [self.store messagesOfType:@"contact" limit:10];
    for (SSBMessage *msg in contacts) {
        XCTAssertEqualObjects(msg.contentType, @"contact");
    }
    XCTAssertGreaterThanOrEqual(contacts.count, 1);
}

#pragma mark - displayNameForAuthor:

- (void)testDisplayNameForAuthor_defaultsToAuthorId {
    NSString *author = @"@unknowndisplay.ed25519";
    NSString *name = [self.store displayNameForAuthor:author];
    XCTAssertEqualObjects(name, author);
}

- (void)testDisplayNameForAuthor_updatedByAboutMessage {
    NSString *author = @"@displayme.ed25519";
    NSDictionary *content = @{@"type": @"about", @"about": author, @"name": @"Display Me"};
    SSBMessage *aboutMsg = MakeMessage(@"%aboutdm.sha256", author, 1, nil, @"about", content);
    [self.store appendMessage:aboutMsg error:nil];

    NSString *name = [self.store displayNameForAuthor:author];
    XCTAssertEqualObjects(name, @"Display Me");
}

- (void)testDisplayNameForAuthor_notUpdatedByOtherAuthorAbout {
    // An about from a different author should NOT override the target's own display name
    NSString *target = @"@target_display.ed25519";
    NSString *otherAuthor = @"@otherperson.ed25519";
    NSDictionary *content = @{@"type": @"about", @"about": target, @"name": @"Imposter Name"};
    SSBMessage *msg = MakeMessage(@"%fakeabout.sha256", otherAuthor, 1, nil, @"about", content);
    [self.store appendMessage:msg error:nil];

    // The store only applies self-about — display name should remain the author ID
    NSString *name = [self.store displayNameForAuthor:target];
    XCTAssertEqualObjects(name, target, @"Display name should not be set from another author's about");
}

#pragma mark - messagesForAuthor:fromSequence:limit:

- (void)testMessagesForAuthor_fromSequence {
    NSString *author = @"@histstream.ed25519";
    for (NSInteger i = 1; i <= 5; i++) {
        NSString *prev = (i > 1) ? [NSString stringWithFormat:@"%%hs%ld.sha256", (long)(i-1)] : nil;
        SSBMessage *m = MakeMessage([NSString stringWithFormat:@"%%hs%ld.sha256", (long)i],
                                    author, i, prev, @"post", @{@"type": @"post"});
        [self.store appendMessage:m error:nil];
    }

    NSArray<SSBMessage *> *msgs = [self.store messagesForAuthor:author fromSequence:3 limit:10];
    XCTAssertEqual(msgs.count, 3); // seq 3, 4, 5
    XCTAssertEqual(msgs[0].sequence, 3);
}

@end
