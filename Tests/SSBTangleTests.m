#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBTangle.h>
#import <SSBNetwork/SSBMessage.h>

/// Build a minimal SSBMessage for testing.
static SSBMessage *makeMsg(NSString *key, NSString *author, NSInteger seq,
                           int64_t ts, NSDictionary *content) {
    SSBMessage *m = [[SSBMessage alloc] init];
    m.key = key;
    m.author = author;
    m.sequence = seq;
    m.claimedTimestamp = ts;
    m.content = content;
    return m;
}

/// Build an SSBTangleData without a designated initializer (properties are publicly settable).
static SSBTangleData *makeTangleData(NSString *root, NSArray *previous) {
    SSBTangleData *d = [[SSBTangleData alloc] init];
    d.root = root;
    d.previous = previous;
    return d;
}

@interface SSBTangleTests : XCTestCase
@end

@implementation SSBTangleTests

#pragma mark - SSBTangleData properties

- (void)testTangleData_propertiesRoundTrip {
    SSBTangleData *d = makeTangleData(@"%r.sha256", @[@"%p1.sha256"]);
    XCTAssertEqualObjects(d.root, @"%r.sha256");
    XCTAssertEqualObjects(d.previous, @[@"%p1.sha256"]);
}

- (void)testTangleData_nilRootAndPrev_description {
    SSBTangleData *d = makeTangleData(nil, nil);
    XCTAssertNotNil(d.description);
}

- (void)testTangleData_isEqual_sameValues {
    SSBTangleData *a = makeTangleData(@"%r.sha256", @[@"%p.sha256"]);
    SSBTangleData *b = makeTangleData(@"%r.sha256", @[@"%p.sha256"]);
    XCTAssertEqualObjects(a, b);
}

- (void)testTangleData_isEqual_differentRoot {
    SSBTangleData *a = makeTangleData(@"%r1.sha256", nil);
    SSBTangleData *b = makeTangleData(@"%r2.sha256", nil);
    XCTAssertNotEqualObjects(a, b);
}

- (void)testTangleData_isEqual_differentPrevious {
    SSBTangleData *a = makeTangleData(@"%r.sha256", @[@"%p1.sha256"]);
    SSBTangleData *b = makeTangleData(@"%r.sha256", @[@"%p2.sha256"]);
    XCTAssertNotEqualObjects(a, b);
}

- (void)testTangleData_isEqual_nonTangleObject {
    SSBTangleData *a = makeTangleData(@"%r.sha256", nil);
    XCTAssertFalse([a isEqual:@"string"]);
}

- (void)testTangleData_bothNilRootsAndPrev_equal {
    SSBTangleData *a = makeTangleData(nil, nil);
    SSBTangleData *b = makeTangleData(nil, nil);
    XCTAssertEqualObjects(a, b);
}

- (void)testTangleData_hash {
    SSBTangleData *a = makeTangleData(@"%r.sha256", @[@"%p.sha256"]);
    XCTAssertEqual(a.hash, a.hash);
}

#pragma mark - extractMessageIdFromKey

- (void)testExtractMessageId_percentPrefixed_returnsSelf {
    XCTAssertEqualObjects([SSBTangle extractMessageIdFromKey:@"%abc.sha256"], @"%abc.sha256");
}

- (void)testExtractMessageId_dotSha256Suffix_returnsPrefixed {
    NSString *result = [SSBTangle extractMessageIdFromKey:@"abc.sha256"];
    XCTAssertEqualObjects(result, @"%abc.sha256");
}

- (void)testExtractMessageId_randomString_returnsNil {
    XCTAssertNil([SSBTangle extractMessageIdFromKey:@"nohash"]);
}

- (void)testExtractMessageId_nil_returnsNil {
    XCTAssertNil([SSBTangle extractMessageIdFromKey:nil]);
}

- (void)testExtractMessageId_singleChar_returnsNil {
    XCTAssertNil([SSBTangle extractMessageIdFromKey:@"%"]);
}

- (void)testExtractMessageId_emptyString_returnsNil {
    XCTAssertNil([SSBTangle extractMessageIdFromKey:@""]);
}

#pragma mark - tangleDataWithRoot:previous

- (void)testTangleDataWithRoot_nilAndNil_returnsData {
    SSBTangleData *result = [SSBTangle tangleDataWithRoot:nil previous:nil];
    XCTAssertNotNil(result);
}

#pragma mark - parseTangleData:fromContent

- (void)testParseTangleData_nilContent_returnsNil {
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:nil]);
}

- (void)testParseTangleData_noTanglesKey_returnsNil {
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:@{@"type": @"post"}]);
}

- (void)testParseTangleData_missingTangleName_returnsNil {
    NSDictionary *content = @{@"tangles": @{@"other": @{@"root": [NSNull null], @"previous": [NSNull null]}}};
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:content]);
}

- (void)testParseTangleData_rootMessage_rootIsNil {
    NSDictionary *content = @{
        @"tangles": @{@"main": @{@"root": [NSNull null], @"previous": [NSNull null]}}
    };
    SSBTangleData *data = [SSBTangle parseTangleData:@"main" fromContent:content];
    XCTAssertNotNil(data);
    XCTAssertNil(data.root);
    XCTAssertNil(data.previous);
}

- (void)testParseTangleData_nonRootMessage_parsesRootAndPrev {
    NSDictionary *content = @{
        @"tangles": @{@"main": @{
            @"root": @"%root.sha256",
            @"previous": @[@"%prev.sha256"]
        }}
    };
    SSBTangleData *data = [SSBTangle parseTangleData:@"main" fromContent:content];
    XCTAssertNotNil(data);
    XCTAssertEqualObjects(data.root, @"%root.sha256");
    XCTAssertEqualObjects(data.previous, @[@"%prev.sha256"]);
}

- (void)testParseTangleData_nonDictContent_returnsNil {
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:(id)@"string"]);
}

- (void)testParseTangleData_tanglesNotDict_returnsNil {
    NSDictionary *content = @{@"tangles": @"notadict"};
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:content]);
}

- (void)testParseTangleData_tangleDataNotDict_returnsNil {
    NSDictionary *content = @{@"tangles": @{@"main": @"notadict"}};
    XCTAssertNil([SSBTangle parseTangleData:@"main" fromContent:content]);
}

- (void)testParseTangleData_previousNotArray_noPrevious {
    NSDictionary *content = @{
        @"tangles": @{@"main": @{@"root": @"%root.sha256", @"previous": @"notarray"}}
    };
    SSBTangleData *data = [SSBTangle parseTangleData:@"main" fromContent:content];
    XCTAssertNotNil(data);
    XCTAssertNil(data.previous);
}

#pragma mark - validateClassicFeedMessage

- (void)testValidateClassicFeed_seq1_noPrev_valid {
    SSBMessage *m = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    m.previousKey = nil;
    XCTAssertTrue([SSBTangle validateClassicFeedMessage:m allMessages:@{}]);
}

- (void)testValidateClassicFeed_seq1_withPrev_invalid {
    SSBMessage *m = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    m.previousKey = @"%something.sha256";
    XCTAssertFalse([SSBTangle validateClassicFeedMessage:m allMessages:@{}]);
}

- (void)testValidateClassicFeed_seq2_noPrev_invalid {
    SSBMessage *m = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    m.previousKey = nil;
    XCTAssertFalse([SSBTangle validateClassicFeedMessage:m allMessages:@{}]);
}

- (void)testValidateClassicFeed_seq2_prevMissing_invalid {
    SSBMessage *m = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    m.previousKey = @"%m1.sha256";
    XCTAssertFalse([SSBTangle validateClassicFeedMessage:m allMessages:@{}]);
}

- (void)testValidateClassicFeed_seq2_prevPresent_valid {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    m2.previousKey = @"%m1.sha256";
    NSDictionary *all = @{@"%m1.sha256": m1};
    XCTAssertTrue([SSBTangle validateClassicFeedMessage:m2 allMessages:all]);
}

- (void)testValidateClassicFeed_wrongAuthor_invalid {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@bob.ed25519", 2, 2000, @{});
    m2.previousKey = @"%m1.sha256";
    NSDictionary *all = @{@"%m1.sha256": m1};
    XCTAssertFalse([SSBTangle validateClassicFeedMessage:m2 allMessages:all]);
}

- (void)testValidateClassicFeed_seqGap_invalid {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m3 = makeMsg(@"%m3.sha256", @"@alice.ed25519", 3, 3000, @{});
    m3.previousKey = @"%m1.sha256";
    NSDictionary *all = @{@"%m1.sha256": m1};
    XCTAssertFalse([SSBTangle validateClassicFeedMessage:m3 allMessages:all]);
}

#pragma mark - validateMessage:inTangle

- (void)testValidateMessage_noContent_returnsFalse {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, nil);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_noTangles_returnsFalse {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{@"type": @"post"});
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_missingTangleName_returnsFalse {
    NSDictionary *content = @{@"tangles": @{@"other": @{@"root": [NSNull null], @"previous": [NSNull null]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_tangleDataNotDict_returnsFalse {
    NSDictionary *content = @{@"tangles": @{@"main": @"notadict"}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_rootMessage_valid {
    NSDictionary *content = @{@"tangles": @{@"main": @{@"root": [NSNull null], @"previous": [NSNull null]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, content);
    XCTAssertTrue([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_rootWithNonNullPrev_returnsFalse {
    NSDictionary *content = @{@"tangles": @{@"main": @{@"root": [NSNull null], @"previous": @[@"%p.sha256"]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_nonRootNullPrev_returnsFalse {
    NSDictionary *content = @{@"tangles": @{@"main": @{@"root": @"%r.sha256", @"previous": [NSNull null]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 2, 2000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_nonRootWithPrevArray_valid {
    NSDictionary *content = @{@"tangles": @{@"main": @{@"root": @"%r.sha256", @"previous": @[@"%p.sha256"]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 2, 2000, content);
    XCTAssertTrue([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_prevArrayWithNonString_returnsFalse {
    NSDictionary *content = @{@"tangles": @{@"main": @{@"root": @"%r.sha256", @"previous": @[@42]}}};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 2, 2000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

- (void)testValidateMessage_tanglesNotDict_returnsFalse {
    NSDictionary *content = @{@"tangles": @"notadict"};
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, content);
    XCTAssertFalse([SSBTangle validateMessage:m inTangle:@"main" allMessages:@{}]);
}

#pragma mark - findTipsInTangle

- (void)testFindTips_empty_returnsEmpty {
    NSArray *tips = [SSBTangle findTipsInTangle:@"main" messages:@[] tangleDataMap:@{}];
    XCTAssertEqualObjects(tips, @[]);
}

- (void)testFindTips_singleMessage_returnsThatKey {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBTangleData *d = makeTangleData(nil, nil);
    NSArray *tips = [SSBTangle findTipsInTangle:@"main"
                                        messages:@[m]
                                   tangleDataMap:@{@"%m.sha256": d}];
    XCTAssertEqual(tips.count, 1U);
    XCTAssertEqualObjects(tips.firstObject, @"%m.sha256");
}

- (void)testFindTips_linearChain_returnsOnlyTip {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBTangleData *d1 = makeTangleData(nil, nil);
    SSBTangleData *d2 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    NSDictionary *dataMap = @{@"%m1.sha256": d1, @"%m2.sha256": d2};
    NSArray *tips = [SSBTangle findTipsInTangle:@"main"
                                        messages:@[m1, m2]
                                   tangleDataMap:dataMap];
    XCTAssertEqual(tips.count, 1U);
    XCTAssertEqualObjects(tips.firstObject, @"%m2.sha256");
}

#pragma mark - topologicalSort

- (void)testTopologicalSort_empty_returnsEmpty {
    NSArray *sorted = [SSBTangle topologicalSort:@[] tangleName:@"main" tangleDataMap:@{}];
    XCTAssertEqualObjects(sorted, @[]);
}

- (void)testTopologicalSort_singleMessage_returnsIt {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{});
    NSArray *sorted = [SSBTangle topologicalSort:@[m] tangleName:@"main" tangleDataMap:@{}];
    XCTAssertEqual(sorted.count, 1U);
}

- (void)testTopologicalSort_linearChain_rootFirst {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBTangleData *d2 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    NSDictionary *dataMap = @{@"%m2.sha256": d2};
    NSArray *sorted = [SSBTangle topologicalSort:@[m2, m1] tangleName:@"main" tangleDataMap:dataMap];
    XCTAssertEqual(sorted.count, 2U);
    XCTAssertEqualObjects(((SSBMessage *)sorted[0]).key, @"%m1.sha256");
    XCTAssertEqualObjects(((SSBMessage *)sorted[1]).key, @"%m2.sha256");
}


#pragma mark - detectForksInTangle

- (void)testDetectForks_empty_returnsEmpty {
    NSArray *forks = [SSBTangle detectForksInTangle:@"main" messages:@[] tangleDataMap:@{}];
    XCTAssertEqualObjects(forks, @[]);
}

- (void)testDetectForks_singleMessage_noForks {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{});
    NSArray *forks = [SSBTangle detectForksInTangle:@"main" messages:@[m] tangleDataMap:@{}];
    XCTAssertEqualObjects(forks, @[]);
}

- (void)testDetectForks_twoConnectedMessages_returnsGroup {
    // detectForksInTangle returns all connected components of size > 1,
    // so a linear 2-message chain IS returned as a group.
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBTangleData *d2 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    NSDictionary *dataMap = @{@"%m2.sha256": d2};
    NSArray *forks = [SSBTangle detectForksInTangle:@"main"
                                            messages:@[m1, m2]
                                       tangleDataMap:dataMap];
    XCTAssertNotNil(forks);
}

- (void)testDetectForks_forkedMessages_detectsFork {
    // m1 -> m2 and m1 -> m3 (two children of m1 = fork)
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBMessage *m3 = makeMsg(@"%m3.sha256", @"@alice.ed25519", 3, 3000, @{});
    SSBTangleData *d2 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    SSBTangleData *d3 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    NSDictionary *dataMap = @{@"%m2.sha256": d2, @"%m3.sha256": d3};
    NSArray *forks = [SSBTangle detectForksInTangle:@"main"
                                            messages:@[m1, m2, m3]
                                       tangleDataMap:dataMap];
    XCTAssertGreaterThan(forks.count, 0U);
}

#pragma mark - isMessage:connectedTo

- (void)testIsMessageConnected_sameId_returnsTrue {
    XCTAssertTrue([SSBTangle isMessage:@"%m.sha256" connectedTo:@"%m.sha256"
                              inTangle:@"main" messages:@[] tangleDataMap:@{}]);
}

- (void)testIsMessageConnected_nilId_returnsFalse {
    XCTAssertFalse([SSBTangle isMessage:nil connectedTo:@"%m.sha256"
                               inTangle:@"main" messages:@[] tangleDataMap:@{}]);
}

- (void)testIsMessageConnected_nilTarget_returnsFalse {
    XCTAssertFalse([SSBTangle isMessage:@"%m.sha256" connectedTo:nil
                               inTangle:@"main" messages:@[] tangleDataMap:@{}]);
}

- (void)testIsMessageConnected_directPrev_returnsTrue {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBTangleData *d2 = makeTangleData(@"%m1.sha256", @[@"%m1.sha256"]);
    NSDictionary *dataMap = @{@"%m2.sha256": d2};
    BOOL connected = [SSBTangle isMessage:@"%m2.sha256" connectedTo:@"%m1.sha256"
                                 inTangle:@"main" messages:@[m1, m2] tangleDataMap:dataMap];
    XCTAssertTrue(connected);
}

- (void)testIsMessageConnected_notConnected_returnsFalse {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    BOOL connected = [SSBTangle isMessage:@"%m2.sha256" connectedTo:@"%m1.sha256"
                                 inTangle:@"main" messages:@[m1, m2] tangleDataMap:@{}];
    XCTAssertFalse(connected);
}

#pragma mark - tangleTypeForMessages

- (void)testTangleType_empty_returnsMultiAuthor {
    SSBTangleType type = [SSBTangle tangleTypeForMessages:@[] tangleName:@"main" tangleDataMap:@{}];
    XCTAssertEqual(type, SSBTangleTypeMultiAuthor);
}

- (void)testTangleType_singleAuthor_returnsSingleAuthor {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@alice.ed25519", 2, 2000, @{});
    SSBTangleType type = [SSBTangle tangleTypeForMessages:@[m1, m2] tangleName:@"main" tangleDataMap:@{}];
    XCTAssertEqual(type, SSBTangleTypeSingleAuthor);
}

- (void)testTangleType_multipleAuthors_returnsMultiAuthor {
    SSBMessage *m1 = makeMsg(@"%m1.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBMessage *m2 = makeMsg(@"%m2.sha256", @"@bob.ed25519", 2, 2000, @{});
    SSBTangleType type = [SSBTangle tangleTypeForMessages:@[m1, m2] tangleName:@"main" tangleDataMap:@{}];
    XCTAssertEqual(type, SSBTangleTypeMultiAuthor);
}

- (void)testTangleType_singleAuthorWithTangleData_returnsSingleAuthor {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBTangleData *d = makeTangleData(nil, nil);
    SSBTangleType type = [SSBTangle tangleTypeForMessages:@[m] tangleName:@"main"
                                            tangleDataMap:@{@"%m.sha256": d}];
    XCTAssertEqual(type, SSBTangleTypeSingleAuthor);
}

#pragma mark - findRootForTangle

- (void)testFindRoot_empty_returnsNil {
    XCTAssertNil([SSBTangle findRootForTangle:@"main" messages:@[] tangleDataMap:@{}]);
}

- (void)testFindRoot_rootMessageWithNilRoot_returnsKey {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000,
                            @{@"tangles": @{@"main": @{@"root": [NSNull null], @"previous": [NSNull null]}}});
    SSBTangleData *d = makeTangleData(nil, nil);
    NSString *root = [SSBTangle findRootForTangle:@"main" messages:@[m]
                                    tangleDataMap:@{@"%m.sha256": d}];
    XCTAssertEqualObjects(root, @"%m.sha256");
}

#pragma mark - previousForNewMessageInTangle

- (void)testPreviousForNew_empty_returnsNil {
    NSArray *prev = [SSBTangle previousForNewMessageInTangle:@"main" messages:@[] tangleDataMap:@{}];
    XCTAssertNil(prev);
}

- (void)testPreviousForNew_singleMessage_returnsThatKey {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{});
    SSBTangleData *d = makeTangleData(nil, nil);
    NSArray *prev = [SSBTangle previousForNewMessageInTangle:@"main"
                                                     messages:@[m]
                                                tangleDataMap:@{@"%m.sha256": d}];
    XCTAssertEqual(prev.count, 1U);
    XCTAssertEqualObjects(prev.firstObject, @"%m.sha256");
}

#pragma mark - tangleDataMapForMessages

- (void)testTangleDataMapForMessages_noTangles_returnsEmpty {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{@"type": @"post"});
    NSDictionary *map = [SSBTangle tangleDataMapForMessages:@[m]];
    XCTAssertEqualObjects(map, @{});
}

- (void)testTangleDataMapForMessages_withTangles_buildsMap {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{
        @"tangles": @{@"main": @{@"root": [NSNull null], @"previous": [NSNull null]}}
    });
    NSDictionary *map = [SSBTangle tangleDataMapForMessages:@[m]];
    XCTAssertNotNil(map[@"%m.sha256"]);
}

- (void)testTangleDataMapForMessages_nilContent_skipsMessage {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, nil);
    NSDictionary *map = [SSBTangle tangleDataMapForMessages:@[m]];
    XCTAssertEqualObjects(map, @{});
}

- (void)testTangleDataMapForMessages_tanglesNotDict_skipsMessage {
    SSBMessage *m = makeMsg(@"%m.sha256", @"@alice.ed25519", 1, 1000, @{@"tangles": @"notadict"});
    NSDictionary *map = [SSBTangle tangleDataMapForMessages:@[m]];
    XCTAssertEqualObjects(map, @{});
}

#pragma mark - filterValidMessageIds

- (void)testFilterValidMessageIds_emptyInput_returnsEmpty {
    NSArray *result = [SSBTangle filterValidMessageIds:@[] allMessages:@{}];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testFilterValidMessageIds_nilInput_returnsEmpty {
    NSArray *result = [SSBTangle filterValidMessageIds:nil allMessages:@{}];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testFilterValidMessageIds_nonStringEntries_filtered {
    NSArray *result = [SSBTangle filterValidMessageIds:@[@42, @YES] allMessages:@{}];
    XCTAssertEqualObjects(result, @[]);
}

@end
