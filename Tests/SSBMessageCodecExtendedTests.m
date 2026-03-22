#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBMessageCodec.h>
#import <SSBNetwork/tweetnacl.h>
#import <SSBNetwork/SSBCommonCryptoCompat.h>

static void GenerateKeypair(NSData **outPublicKey, NSData **outSecretKey) {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPublicKey) *outPublicKey = [NSData dataWithBytes:pk length:32];
    if (outSecretKey) *outSecretKey = [NSData dataWithBytes:sk length:64];
}

static NSString *FeedIdFromPublicKey(NSData *pk) {
    NSString *b64 = [pk base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"@%@.ed25519", b64];
}

@interface SSBMessageCodecExtendedTests : XCTestCase
@property (nonatomic, strong) NSData *secretKey;
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, copy) NSString *feedId;
@end

@interface SSBMessageCodec (TestPrivate)
+ (NSString *)jsonStringLiteral:(NSString *)str;
+ (NSString *)jsonEncodeObject:(id)obj indent:(int)indent;
@end

@implementation SSBMessageCodecExtendedTests

- (void)setUp {
    [super setUp];
    NSData *publicKey = nil;
    NSData *secretKey = nil;
    GenerateKeypair(&publicKey, &secretKey);
    self.publicKey = publicKey;
    self.secretKey = secretKey;
    self.feedId = FeedIdFromPublicKey(publicKey);
}

#pragma mark - createSignedMessageWithContent:author:sequence:previousKey:secretKey:

- (void)testCreateSignedMessage_firstMessage {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Hello SSB"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    XCTAssertNotNil(value);
    XCTAssertEqualObjects(value[@"author"], self.feedId);
    XCTAssertEqualObjects(value[@"sequence"], @1);
    XCTAssertNil(value[@"previous"]);
    XCTAssertNotNil(value[@"signature"]);
    XCTAssertNotNil(value[@"timestamp"]);
    XCTAssertEqualObjects(value[@"hash"], @"sha256");
}

- (void)testCreateSignedMessage_subsequentMessage {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Second"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:2
                                                              previousKey:@"%prev.sha256"
                                                                secretKey:self.secretKey];
    XCTAssertNotNil(value);
    XCTAssertEqualObjects(value[@"previous"], @"%prev.sha256");
    XCTAssertEqualObjects(value[@"sequence"], @2);
}

- (void)testCreateSignedMessage_invalidKeyReturnsNil {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Bad key"];
    NSData *badKey = [NSData dataWithBytes:"\x00\x01\x02" length:3];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:badKey];
    XCTAssertNil(value);
}

- (void)testCreateSignedMessage_signatureVerifies {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Verify me"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    XCTAssertNotNil(value);
    BOOL valid = [SSBMessageCodec verifyMessage:value];
    XCTAssertTrue(valid, @"Freshly signed message must verify");
}

#pragma mark - computeMessageKey:

- (void)testComputeMessageKey_producesPercentHashSuffix {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Key me"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    NSString *key = [SSBMessageCodec computeMessageKey:value];
    XCTAssertNotNil(key);
    XCTAssertTrue([key hasPrefix:@"%"], @"Message key must start with %%");
    XCTAssertTrue([key hasSuffix:@".sha256"], @"Message key must end with .sha256");
}

- (void)testComputeMessageKey_isDeterministic {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Deterministic"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    NSString *k1 = [SSBMessageCodec computeMessageKey:value];
    NSString *k2 = [SSBMessageCodec computeMessageKey:value];
    XCTAssertEqualObjects(k1, k2);
}

#pragma mark - shouldShowContentForMessage: / contentWarningForMessage: (SIP-010)

- (void)testShouldShowContent_noWarning {
    NSDictionary *value = @{@"content": @{@"type": @"post", @"text": @"safe"}};
    XCTAssertTrue([SSBMessageCodec shouldShowContentForMessage:value]);
    XCTAssertNil([SSBMessageCodec contentWarningForMessage:value]);
}

- (void)testShouldShowContent_withWarning {
    NSDictionary *value = @{@"content": @{@"type": @"post", @"text": @"...",
                                           @"contentWarning": @"contains spoilers"}};
    XCTAssertFalse([SSBMessageCodec shouldShowContentForMessage:value]);
    XCTAssertEqualObjects([SSBMessageCodec contentWarningForMessage:value], @"contains spoilers");
}

- (void)testShouldShowContent_emptyWarningMeansShow {
    NSDictionary *value = @{@"content": @{@"type": @"post", @"contentWarning": @""}};
    XCTAssertTrue([SSBMessageCodec shouldShowContentForMessage:value]);
}

- (void)testContentWarningForNonDictionaryContentReturnsNil {
    NSDictionary *value = @{@"content": @"not-a-dictionary"};
    XCTAssertNil([SSBMessageCodec contentWarningForMessage:value]);
}

#pragma mark - encodeLegacyValue:includeSignature:

- (void)testEncodeLegacyValue_withSignature_containsAllFields {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Encode me"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    NSData *encoded = [SSBMessageCodec encodeLegacyValue:value includeSignature:YES];
    XCTAssertNotNil(encoded);
    NSString *json = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertTrue([json containsString:@"\"signature\""]);
    XCTAssertTrue([json containsString:@"\"author\""]);
    XCTAssertTrue([json containsString:@"\"content\""]);
}

- (void)testEncodeLegacyValue_withoutSignature_omitsSignatureField {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"No sig"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    NSData *encoded = [SSBMessageCodec encodeLegacyValue:value includeSignature:NO];
    XCTAssertNotNil(encoded);
    NSString *json = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertFalse([json containsString:@"\"signature\""]);
}

- (void)testEncodeLegacyValue_fieldOrdering {
    // SSB canonical JSON field order: previous, author, sequence, timestamp, hash, content, signature
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"Order matters"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    NSData *encoded = [SSBMessageCodec encodeLegacyValue:value includeSignature:YES];
    NSString *json = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    NSArray *fields = @[@"previous", @"author", @"sequence", @"timestamp", @"hash", @"content", @"signature"];
    NSInteger lastPos = 0;
    for (NSString *field in fields) {
        NSRange r = [json rangeOfString:[NSString stringWithFormat:@"\"%@\"", field]];
        if (r.location != NSNotFound) {
            XCTAssertGreaterThan(r.location, (NSUInteger)lastPos,
                                 @"Field '%@' should appear after previous fields", field);
            lastPos = (NSInteger)r.location;
        }
    }
}

#pragma mark - rootPostContentWithText:channel:contentWarning:mentions:recps: (SIP-010)

- (void)testRootPostContent_basic {
    NSDictionary *content = [SSBMessageCodec rootPostContentWithText:@"Hi" channel:@"general"
                                                      contentWarning:nil mentions:nil recps:nil];
    XCTAssertEqualObjects(content[@"type"], @"post");
    XCTAssertEqualObjects(content[@"text"], @"Hi");
    XCTAssertEqualObjects(content[@"channel"], @"general");
    XCTAssertNil(content[@"contentWarning"]);
}

- (void)testRootPostContent_withContentWarning {
    NSDictionary *content = [SSBMessageCodec rootPostContentWithText:@"Spoiler"
                                                             channel:nil
                                                     contentWarning:@"spoiler ahead"
                                                           mentions:nil recps:nil];
    XCTAssertEqualObjects(content[@"contentWarning"], @"spoiler ahead");
}

- (void)testRootPostContent_withMentions {
    NSDictionary *mention = [SSBMessageCodec mentionForFeed:@"@someone.ed25519" name:@"Someone"];
    NSDictionary *content = [SSBMessageCodec rootPostContentWithText:@"Hey @Someone"
                                                             channel:nil contentWarning:nil
                                                           mentions:@[mention] recps:nil];
    NSArray *mentions = content[@"mentions"];
    XCTAssertEqual(mentions.count, 1);
    XCTAssertEqualObjects(mentions[0][@"link"], @"@someone.ed25519");
}

#pragma mark - replyContentWithText:root:branch:... (SIP-010)

- (void)testReplyContent_branchAsString {
    NSDictionary *content = [SSBMessageCodec replyContentWithText:@"reply"
                                                             root:@"%root.sha256"
                                                           branch:@"%branch.sha256"
                                                          channel:nil contentWarning:nil
                                                         mentions:nil recps:nil];
    XCTAssertEqualObjects(content[@"type"], @"post");
    // Branch stored as string or single-element array — either is conformant
    id branch = content[@"branch"];
    XCTAssertNotNil(branch);
}

- (void)testReplyContent_branchAsArray {
    NSArray *branches = @[@"%b1.sha256", @"%b2.sha256"];
    NSDictionary *content = [SSBMessageCodec replyContentWithText:@"reply multi"
                                                             root:@"%root.sha256"
                                                           branch:branches
                                                          channel:nil contentWarning:nil
                                                         mentions:nil recps:nil];
    XCTAssertEqualObjects(content[@"root"], @"%root.sha256");
    id branch = content[@"branch"];
    XCTAssertNotNil(branch);
}

#pragma mark - voteContentForMessage: / likeVoteForMessage: (SIP-010)

- (void)testVoteContent_like {
    NSDictionary *vote = [SSBMessageCodec voteContentForMessage:@"%msg.sha256"
                                                     expression:@"Like"
                                                          value:1
                                                           root:nil
                                                         branch:nil];
    XCTAssertEqualObjects(vote[@"type"], @"vote");
    NSDictionary *v = vote[@"vote"];
    XCTAssertEqualObjects(v[@"link"], @"%msg.sha256");
    XCTAssertEqualObjects(v[@"value"], @1);
    XCTAssertEqualObjects(v[@"expression"], @"Like");
}

- (void)testVoteContent_unlike {
    NSDictionary *vote = [SSBMessageCodec voteContentForMessage:@"%msg.sha256"
                                                     expression:@"Unlike"
                                                          value:0
                                                           root:nil
                                                         branch:nil];
    NSDictionary *v = vote[@"vote"];
    XCTAssertEqualObjects(v[@"value"], @0);
}

- (void)testLikeVote_producesCorrectStructure {
    NSDictionary *like = [SSBMessageCodec likeVoteForMessage:@"%target.sha256"];
    XCTAssertEqualObjects(like[@"type"], @"vote");
    NSDictionary *v = like[@"vote"];
    XCTAssertEqualObjects(v[@"link"], @"%target.sha256");
    XCTAssertEqualObjects(v[@"value"], @1);
}

#pragma mark - contactContentWithTarget:following:blocking:

- (void)testContactContent_followingAndBlocking {
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:@"@peer.ed25519"
                                                            following:YES blocking:NO];
    XCTAssertEqualObjects(content[@"type"], @"contact");
    XCTAssertEqualObjects(content[@"contact"], @"@peer.ed25519");
    XCTAssertEqualObjects(content[@"following"], @YES);
    XCTAssertEqualObjects(content[@"blocking"], @NO);
}

- (void)testContactContent_blocking {
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:@"@spam.ed25519"
                                                            following:NO blocking:YES];
    XCTAssertEqualObjects(content[@"blocking"], @YES);
    XCTAssertEqualObjects(content[@"following"], @NO);
}

#pragma mark - aboutAvatarContentForFeed:name:imageBlob:description: (SIP-010)

- (void)testAboutAvatarContent_allFields {
    NSDictionary *content = [SSBMessageCodec aboutAvatarContentForFeed:@"@me.ed25519"
                                                                  name:@"Me"
                                                             imageBlob:@"&img.sha256"
                                                           description:@"About me"];
    XCTAssertEqualObjects(content[@"type"], @"about");
    XCTAssertEqualObjects(content[@"about"], @"@me.ed25519");
    XCTAssertEqualObjects(content[@"name"], @"Me");
    XCTAssertEqualObjects(content[@"description"], @"About me");
    // image field should contain blob reference
    id image = content[@"image"];
    XCTAssertNotNil(image);
}

- (void)testAboutAvatarContent_nameOnly {
    NSDictionary *content = [SSBMessageCodec aboutAvatarContentForFeed:@"@me.ed25519"
                                                                  name:@"Minimal"
                                                             imageBlob:nil
                                                           description:nil];
    XCTAssertEqualObjects(content[@"name"], @"Minimal");
    XCTAssertNil(content[@"description"]);
}

#pragma mark - normalizeChannelName: / isValidChannelName: (SIP-010)

- (void)testNormalizeChannelName_lowercases {
    NSString *normalized = [SSBMessageCodec normalizeChannelName:@"SSB-General"];
    XCTAssertEqualObjects(normalized, @"ssb-general");
}

- (void)testNormalizeChannelName_truncatesAt30Chars {
    NSString *long30 = @"abcdefghijklmnopqrstuvwxyzabcd"; // 30 chars
    NSString *long31 = @"abcdefghijklmnopqrstuvwxyzabcde"; // 31 chars
    XCTAssertEqual([SSBMessageCodec normalizeChannelName:long30].length, 30);
    XCTAssertLessThanOrEqual([SSBMessageCodec normalizeChannelName:long31].length, 30);
}

- (void)testIsValidChannelName_valid {
    XCTAssertTrue([SSBMessageCodec isValidChannelName:@"ssb-general"]);
    XCTAssertTrue([SSBMessageCodec isValidChannelName:@"protocol"]);
}

- (void)testIsValidChannelName_invalidContainsSpace {
    XCTAssertFalse([SSBMessageCodec isValidChannelName:@"my channel"]);
}

- (void)testIsValidChannelName_invalidTooLong {
    NSString *tooLong = @"abcdefghijklmnopqrstuvwxyzabcdef"; // 32 chars
    XCTAssertFalse([SSBMessageCodec isValidChannelName:tooLong]);
}

#pragma mark - mentionForFeed: / mentionForMessage: / mentionForBlob:

- (void)testMentionForFeed {
    NSDictionary *mention = [SSBMessageCodec mentionForFeed:@"@alice.ed25519" name:@"Alice"];
    XCTAssertEqualObjects(mention[@"link"], @"@alice.ed25519");
    XCTAssertEqualObjects(mention[@"name"], @"Alice");
}

- (void)testMentionForFeed_nilName {
    NSDictionary *mention = [SSBMessageCodec mentionForFeed:@"@alice.ed25519" name:nil];
    XCTAssertEqualObjects(mention[@"link"], @"@alice.ed25519");
    XCTAssertNil(mention[@"name"]);
}

- (void)testMentionForMessage {
    NSDictionary *mention = [SSBMessageCodec mentionForMessage:@"%msg.sha256"];
    XCTAssertEqualObjects(mention[@"link"], @"%msg.sha256");
}

- (void)testMentionForBlob {
    NSDictionary *mention = [SSBMessageCodec mentionForBlob:@"&blob.sha256" name:@"photo.jpg" size:1024];
    XCTAssertEqualObjects(mention[@"link"], @"&blob.sha256");
    XCTAssertEqualObjects(mention[@"name"], @"photo.jpg");
    XCTAssertEqualObjects(mention[@"size"], @1024);
}

#pragma mark - isValidMessageId: / isValidFeedId: / isValidBlobId:

- (void)testIsValidMessageId_valid {
    XCTAssertTrue([SSBMessageCodec isValidMessageId:@"%abc123def.sha256"]);
}

- (void)testIsValidMessageId_missingPercent {
    XCTAssertFalse([SSBMessageCodec isValidMessageId:@"abc123.sha256"]);
}

- (void)testIsValidMessageId_missingSuffix {
    XCTAssertFalse([SSBMessageCodec isValidMessageId:@"%abc123"]);
}

- (void)testIsValidFeedId_valid {
    XCTAssertTrue([SSBMessageCodec isValidFeedId:@"@abc123.ed25519"]);
}

- (void)testIsValidFeedId_missingAt {
    XCTAssertFalse([SSBMessageCodec isValidFeedId:@"abc123.ed25519"]);
}

- (void)testIsValidBlobId_valid {
    XCTAssertTrue([SSBMessageCodec isValidBlobId:@"&abc123.sha256"]);
}

- (void)testIsValidBlobId_missingAmpersand {
    XCTAssertFalse([SSBMessageCodec isValidBlobId:@"abc123.sha256"]);
}

#pragma mark - signString:withSecretKey:

- (void)testSignString_producesBase64DotSigEd25519 {
    NSString *sig = [SSBMessageCodec signString:@"hello world" withSecretKey:self.secretKey];
    XCTAssertNotNil(sig);
    XCTAssertTrue([sig hasSuffix:@".sig.ed25519"], @"Signature must end with .sig.ed25519");
}

- (void)testSignString_isDeterministicForSameInput {
    // Ed25519 is deterministic: same key + same message → same signature
    NSString *s1 = [SSBMessageCodec signString:@"deterministic" withSecretKey:self.secretKey];
    NSString *s2 = [SSBMessageCodec signString:@"deterministic" withSecretKey:self.secretKey];
    XCTAssertEqualObjects(s1, s2);
}

- (void)testSignString_invalidKeyReturnsNil {
    NSData *badKey = [NSData dataWithBytes:"\x00" length:1];
    NSString *sig = [SSBMessageCodec signString:@"hello" withSecretKey:badKey];
    XCTAssertNil(sig);
}

#pragma mark - Feed Codec Instance Methods

- (void)testFeedCodecFormatsAreClassic {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    XCTAssertEqual(codec.feedFormat, SSBBFEFeedFormatClassic);
    XCTAssertEqual(codec.messageFormat, SSBBFEMessageFormatClassic);
}

- (void)testVerifyMessageDataRejectsInvalidJSON {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    NSData *garbage = [@"not-json" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    XCTAssertFalse([codec verifyMessageData:garbage error:&error]);
    XCTAssertNotNil(error);
}

- (void)testVerifyMessageDataRejectsInvalidSignature {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    NSDictionary *invalidValue = @{
        @"author": self.feedId,
        @"previous": [NSNull null],
        @"sequence": @1,
        @"timestamp": @1,
        @"hash": @"sha256",
        @"content": @{@"type": @"post", @"text": @"bad"},
        @"signature": @"ZmFrZQ==.sig.ed25519"
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:invalidValue options:0 error:nil];
    NSError *error = nil;
    XCTAssertFalse([codec verifyMessageData:json error:&error]);
    XCTAssertNotNil(error);
}

- (void)testVerifyMessageDataAcceptsValidSignedMessage {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"valid"];
    NSDictionary *value = [SSBMessageCodec createSignedMessageWithContent:content
                                                                   author:self.feedId
                                                                 sequence:1
                                                              previousKey:nil
                                                                secretKey:self.secretKey];
    XCTAssertNotNil(value);
    NSData *encoded = [SSBMessageCodec encodeLegacyValue:value includeSignature:YES];
    XCTAssertNotNil(encoded);

    NSError *error = nil;
    XCTAssertTrue([codec verifyMessageData:encoded error:&error]);
    XCTAssertNil(error);
}

- (void)testComputeMessageKeyFromDataErrorsOnEmptyInput {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    NSError *error = nil;
    NSData *digest = [codec computeMessageKeyFromData:[NSData data] error:&error];
    XCTAssertNil(digest);
    XCTAssertNotNil(error);
}

- (void)testComputeMessageKeyFromDataReturnsSHA256Digest {
    SSBMessageCodec *codec = [SSBMessageCodec sharedCodec];
    NSData *payload = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *digest = [codec computeMessageKeyFromData:payload error:&error];
    XCTAssertNotNil(digest);
    XCTAssertNil(error);
    XCTAssertEqual(digest.length, (NSUInteger)CC_SHA256_DIGEST_LENGTH);
}

#pragma mark - JSON Helper Branches

- (void)testPostContentWithRootAndBranchIncludesReferences {
    NSDictionary *content = [SSBMessageCodec postContentWithText:@"reply"
                                                            root:@"%root.sha256"
                                                          branch:@"%branch.sha256"];
    XCTAssertEqualObjects(content[@"root"], @"%root.sha256");
    XCTAssertEqualObjects(content[@"branch"], @"%branch.sha256");
}

- (void)testJsonStringLiteralEscapesControlCharacters {
    NSString *escaped = [SSBMessageCodec jsonStringLiteral:@"a\"\n\tb"];
    XCTAssertEqualObjects(escaped, @"\"a\\\"\\n\\tb\"");
}

- (void)testJsonEncodeObjectHandlesNumbersCollectionsAndFallback {
    NSString *boolJSON = [SSBMessageCodec jsonEncodeObject:@YES indent:0];
    XCTAssertEqualObjects(boolJSON, @"true");

    NSString *intJSON = [SSBMessageCodec jsonEncodeObject:@42 indent:0];
    XCTAssertEqualObjects(intJSON, @"42");

    NSString *floatJSON = [SSBMessageCodec jsonEncodeObject:@(3.5) indent:0];
    XCTAssertTrue([floatJSON containsString:@"3.5"]);

    NSString *arrayJSON = [SSBMessageCodec jsonEncodeObject:@[@"x", @1] indent:0];
    XCTAssertTrue([arrayJSON containsString:@"\"x\""]);
    XCTAssertTrue([arrayJSON containsString:@"1"]);

    NSString *dictJSON = [SSBMessageCodec jsonEncodeObject:@{@"b": @2, @"a": @1} indent:0];
    NSRange aPos = [dictJSON rangeOfString:@"\"a\""];
    NSRange bPos = [dictJSON rangeOfString:@"\"b\""];
    XCTAssertNotEqual(aPos.location, NSNotFound);
    XCTAssertNotEqual(bPos.location, NSNotFound);
    XCTAssertLessThan(aPos.location, bPos.location);

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
    NSString *fallbackJSON = [SSBMessageCodec jsonEncodeObject:date indent:0];
    XCTAssertTrue([fallbackJSON hasPrefix:@"\""]);
}

- (void)testJsonHelpersHandleNullAndEmptyCollections {
    NSString *nullLiteral = [SSBMessageCodec jsonStringLiteral:nil];
    XCTAssertEqualObjects(nullLiteral, @"null");

    NSString *nullEncoded = [SSBMessageCodec jsonEncodeObject:[NSNull null] indent:0];
    XCTAssertEqualObjects(nullEncoded, @"null");

    NSString *emptyArray = [SSBMessageCodec jsonEncodeObject:@[] indent:0];
    XCTAssertEqualObjects(emptyArray, @"[]");

    NSString *emptyDict = [SSBMessageCodec jsonEncodeObject:@{} indent:0];
    XCTAssertEqualObjects(emptyDict, @"{}");
}

- (void)testJsonStringLiteralEscapesBackslash {
    // Input @"a\b" (one backslash) should produce JSON "a\\b"
    NSString *input = @"a\\b"; // ObjC: a\b (single backslash)
    NSString *result = [SSBMessageCodec jsonStringLiteral:input];
    XCTAssertTrue([result containsString:@"\\\\"]);
}

- (void)testJsonStringLiteralEscapesBackspace {
    unichar bs = 0x08;
    NSString *input = [NSString stringWithCharacters:&bs length:1];
    NSString *result = [SSBMessageCodec jsonStringLiteral:input];
    XCTAssertTrue([result containsString:@"\\b"]);
}

- (void)testJsonStringLiteralEscapesFormFeed {
    unichar ff = 0x0C;
    NSString *input = [NSString stringWithCharacters:&ff length:1];
    NSString *result = [SSBMessageCodec jsonStringLiteral:input];
    XCTAssertTrue([result containsString:@"\\f"]);
}

- (void)testJsonStringLiteralEscapesCarriageReturn {
    unichar cr = 0x0D;
    NSString *input = [NSString stringWithCharacters:&cr length:1];
    NSString *result = [SSBMessageCodec jsonStringLiteral:input];
    XCTAssertTrue([result containsString:@"\\r"]);
}

- (void)testJsonStringLiteralEscapesControlCharsBelowU0020 {
    // Control char 0x01 (SOH) -> \u0001
    unichar soh = 0x01;
    NSString *sohStr = [NSString stringWithCharacters:&soh length:1];
    NSString *sohResult = [SSBMessageCodec jsonStringLiteral:sohStr];
    XCTAssertTrue([sohResult containsString:@"\\u0001"]);

    // Control char 0x1F (US) -> \u001f
    unichar us = 0x1F;
    NSString *usStr = [NSString stringWithCharacters:&us length:1];
    NSString *usResult = [SSBMessageCodec jsonStringLiteral:usStr];
    XCTAssertTrue([usResult containsString:@"\\u001f"]);
}

- (void)testJsonEncodeObjectFalseBoolean {
    NSString *falseJSON = [SSBMessageCodec jsonEncodeObject:@NO indent:0];
    XCTAssertEqualObjects(falseJSON, @"false");
}

@end
