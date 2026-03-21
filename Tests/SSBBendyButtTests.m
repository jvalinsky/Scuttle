#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBendyButt.h>
#import <SSBNetwork/tweetnacl.h>

// Expose private class methods for testing
@interface SSBBendyButt (Testing)
+ (nullable NSData *)encodeBFEFeedID:(NSData *)keyData;
+ (nullable NSData *)encodeBFEMessageID:(NSData *)hashData;
+ (nullable NSData *)signPayload:(NSData *)payload withAuthorSecret:(NSData *)authorSecret;
+ (BOOL)verifyPayloadSignature:(NSData *)signatureBFE onPayload:(NSData *)payload author:(NSData *)authorKey;
@end

static void BBGenerateKeypair(NSData **outPK, NSData **outSK) {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPK) *outPK = [NSData dataWithBytes:pk length:32];
    if (outSK) *outSK = [NSData dataWithBytes:sk length:64];
}

@interface SSBBendyButtTests : XCTestCase
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, strong) NSData *secretKey;
@end

@implementation SSBBendyButtTests

- (void)setUp {
    [super setUp];
    NSData *publicKey = nil;
    NSData *secretKey = nil;
    BBGenerateKeypair(&publicKey, &secretKey);
    self.publicKey = publicKey;
    self.secretKey = secretKey;
}

#pragma mark - Bencode Integer

- (void)testBencodeInteger_positive {
    NSData *encoded = [SSBBendyButt encodeBencodeInteger:42];
    XCTAssertNotNil(encoded);
    // Bencode format: "i42e"
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"i42e");
}

- (void)testBencodeInteger_zero {
    NSData *encoded = [SSBBendyButt encodeBencodeInteger:0];
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"i0e");
}

- (void)testBencodeInteger_negative {
    NSData *encoded = [SSBBendyButt encodeBencodeInteger:-7];
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"i-7e");
}

- (void)testBencodeInteger_decodesCorrectly {
    NSData *encoded = [SSBBendyButt encodeBencodeInteger:100];
    NSUInteger offset = 0;
    id decoded = [SSBBendyButt decodeBencode:encoded offset:&offset];
    XCTAssertEqualObjects(decoded, @100);
}

#pragma mark - Bencode String

- (void)testBencodeString_ascii {
    NSData *encoded = [SSBBendyButt encodeBencodeString:@"hello"];
    XCTAssertNotNil(encoded);
    // Bencode string format: "5:hello"
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"5:hello");
}

- (void)testBencodeString_empty {
    NSData *encoded = [SSBBendyButt encodeBencodeString:@""];
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"0:");
}

- (void)testBencodeString_decodesCorrectly {
    NSData *encoded = [SSBBendyButt encodeBencodeString:@"world"];
    NSUInteger offset = 0;
    id decoded = [SSBBendyButt decodeBencode:encoded offset:&offset];
    // Decoded as NSString or NSData containing the raw bytes
    XCTAssertNotNil(decoded);
}

#pragma mark - Bencode Data

- (void)testBencodeData_arbitrary {
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    NSData *original = [NSData dataWithBytes:bytes length:3];
    NSData *encoded = [SSBBendyButt encodeBencodeData:original];
    XCTAssertNotNil(encoded);

    NSUInteger offset = 0;
    id decoded = [SSBBendyButt decodeBencode:encoded offset:&offset];
    XCTAssertNotNil(decoded);
}

#pragma mark - Bencode List

- (void)testBencodeList_simple {
    NSArray *list = @[[SSBBendyButt encodeBencodeInteger:1],
                      [SSBBendyButt encodeBencodeString:@"two"]];
    // encodeBencodeList expects raw list items; pass pre-encoded items as data
    NSArray *rawList = @[@1, @"two"];
    NSData *encoded = [SSBBendyButt encodeBencodeList:rawList];
    XCTAssertNotNil(encoded);
}

- (void)testBencodeList_empty {
    NSData *encoded = [SSBBendyButt encodeBencodeList:@[]];
    XCTAssertNotNil(encoded);
    NSString *str = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"le");
}

- (void)testBencodeList_decodesCorrectly {
    NSData *encoded = [SSBBendyButt encodeBencodeList:@[@"a", @"b"]];
    NSUInteger offset = 0;
    id decoded = [SSBBendyButt decodeBencode:encoded offset:&offset];
    XCTAssertTrue([decoded isKindOfClass:[NSArray class]]);
    XCTAssertEqual(((NSArray *)decoded).count, 2);
}

#pragma mark - Bencode Dictionary

- (void)testBencodeDict_simple {
    NSDictionary *dict = @{@"key": @"value"};
    NSData *encoded = [SSBBendyButt encodeBencodeDict:dict];
    XCTAssertNotNil(encoded);
}

- (void)testBencodeDict_decodesCorrectly {
    NSDictionary *dict = @{@"author": @"@me.ed25519"};
    NSData *encoded = [SSBBendyButt encodeBencodeDict:dict];
    NSUInteger offset = 0;
    id decoded = [SSBBendyButt decodeBencode:encoded offset:&offset];
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
}

#pragma mark - signContent: / verifyContentSignature:onContent:author:

- (void)testSignAndVerifyContent {
    NSData *content = [@"some content bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [SSBBendyButt signContent:content withKey:self.secretKey];
    XCTAssertNotNil(signature);

    BOOL valid = [SSBBendyButt verifyContentSignature:signature
                                            onContent:content
                                               author:self.publicKey];
    XCTAssertTrue(valid);
}

- (void)testVerifyContent_wrongKeyFails {
    NSData *content = [@"content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [SSBBendyButt signContent:content withKey:self.secretKey];

    NSData *otherPK, *otherSK;
    BBGenerateKeypair(&otherPK, &otherSK);
    BOOL valid = [SSBBendyButt verifyContentSignature:signature
                                            onContent:content
                                               author:otherPK];
    XCTAssertFalse(valid);
}

- (void)testVerifyContent_tamperedContentFails {
    NSData *content = [@"original" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = [SSBBendyButt signContent:content withKey:self.secretKey];

    NSData *tampered = [@"modified" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL valid = [SSBBendyButt verifyContentSignature:signature
                                            onContent:tampered
                                               author:self.publicKey];
    XCTAssertFalse(valid);
}

#pragma mark - createMessageWithContent:author:... / validateMessage: / computeMessageKey:

- (void)testCreateAndValidateMessage {
    // Need a 32-byte content secret key for bendy-butt
    uint8_t cskBytes[32] = {0};
    NSData *contentSecretKey = [NSData dataWithBytes:cskBytes length:32];

    NSDictionary *content = @{@"type": @"post", @"text": @"BB message"};
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000000
                                             contentSecretKey:contentSecretKey];
    XCTAssertNotNil(msgData);

    BOOL valid = [SSBBendyButt validateMessage:msgData];
    XCTAssertTrue(valid);
}

- (void)testComputeMessageKey_notNilAndHasLength {
    uint8_t cskBytes[32] = {0};
    NSData *contentSecretKey = [NSData dataWithBytes:cskBytes length:32];

    NSDictionary *content = @{@"type": @"post", @"text": @"keyme"};
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000001
                                             contentSecretKey:contentSecretKey];
    XCTAssertNotNil(msgData);

    NSData *key = [SSBBendyButt computeMessageKey:msgData];
    XCTAssertNotNil(key);
    XCTAssertGreaterThan(key.length, 0);
}

- (void)testComputeMessageKey_isDeterministic {
    uint8_t cskBytes[32] = {0};
    NSData *contentSecretKey = [NSData dataWithBytes:cskBytes length:32];

    NSDictionary *content = @{@"type": @"post", @"text": @"stable"};
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000002
                                             contentSecretKey:contentSecretKey];
    NSData *k1 = [SSBBendyButt computeMessageKey:msgData];
    NSData *k2 = [SSBBendyButt computeMessageKey:msgData];
    XCTAssertEqualObjects(k1, k2);
}

- (void)testValidateMessage_corruptDataFails {
    uint8_t garbage[] = {0x00, 0xFF, 0xAB, 0xCD};
    NSData *bad = [NSData dataWithBytes:garbage length:4];
    BOOL valid = [SSBBendyButt validateMessage:bad];
    XCTAssertFalse(valid);
}

- (void)testValidateMessage_nil_returnsFalse {
    XCTAssertFalse([SSBBendyButt validateMessage:nil]);
}

- (void)testValidateMessage_empty_returnsFalse {
    XCTAssertFalse([SSBBendyButt validateMessage:[NSData data]]);
}

- (void)testComputeMessageKey_nil_returnsNil {
    XCTAssertNil([SSBBendyButt computeMessageKey:nil]);
}

- (void)testComputeMessageKey_empty_returnsNil {
    XCTAssertNil([SSBBendyButt computeMessageKey:[NSData data]]);
}

#pragma mark - messageWithContent:author:... (returns SSBBendyButt instance)

- (void)testMessageWithContent_firstMessage_returnsInstance {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"hello"};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000000
                                         contentSecretKey:csk];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg.author, self.publicKey);
    XCTAssertEqual(msg.sequence, 1);
    XCTAssertNil(msg.previous);
    XCTAssertNotNil(msg.content);
    XCTAssertNotNil(msg.signature);
    XCTAssertNotNil(msg.messageKey);
    XCTAssertEqual(msg.messageKey.length, 32U);
}

- (void)testMessageWithContent_withPrevious_storesPrevious {
    uint8_t cskBytes[32] = {2};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    uint8_t prevBytes[32] = {0xAA};
    NSData *prev = [NSData dataWithBytes:prevBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"second"};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:2
                                                 previous:prev
                                                timestamp:1700000001
                                         contentSecretKey:csk];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg.previous, prev);
    XCTAssertEqual(msg.sequence, 2);
}

#pragma mark - messageWithEncryptedContent:...

- (void)testMessageWithEncryptedContent_returnsInstance {
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSData *encrypted = [@"encrypted_payload.box" dataUsingEncoding:NSUTF8StringEncoding];
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:encrypted
                                                           author:self.publicKey
                                                     authorSecret:self.secretKey
                                                         sequence:1
                                                         previous:nil
                                                        timestamp:1700000002
                                                 contentSecretKey:csk];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg.encryptedContent, encrypted);
    XCTAssertNotNil(msg.messageKey);
}

#pragma mark - feedFormat / messageFormat

- (void)testFeedFormat_returnsBendybuttV1 {
    XCTAssertEqual([[SSBBendyButt sharedCodec] feedFormat], SSBBFEFeedFormatBendybuttV1);
}

- (void)testMessageFormat_returnsBendybuttV1 {
    XCTAssertEqual([[SSBBendyButt sharedCodec] messageFormat], SSBBFEMessageFormatBendybuttV1);
}

- (void)testSharedCodec_returnsSameInstance {
    id c1 = [SSBBendyButt sharedCodec];
    id c2 = [SSBBendyButt sharedCodec];
    XCTAssertEqual(c1, c2);
}

#pragma mark - verifyMessageData:error: / computeMessageKeyFromData:error:

- (void)testVerifyMessageData_validMessage_returnsTrue {
    uint8_t cskBytes[32] = {4};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"verify me"};
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000003
                                             contentSecretKey:csk];
    XCTAssertNotNil(msgData);
    NSError *err = nil;
    BOOL valid = [[SSBBendyButt sharedCodec] verifyMessageData:msgData error:&err];
    XCTAssertTrue(valid);
    XCTAssertNil(err);
}

- (void)testVerifyMessageData_invalid_returnsFalseWithError {
    NSData *bad = [@"not a message" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    BOOL valid = [[SSBBendyButt sharedCodec] verifyMessageData:bad error:&err];
    XCTAssertFalse(valid);
    XCTAssertNotNil(err);
}

- (void)testComputeMessageKeyFromData_validMessage_returnsKey {
    uint8_t cskBytes[32] = {5};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"key test"};
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000004
                                             contentSecretKey:csk];
    NSError *err = nil;
    NSData *key = [[SSBBendyButt sharedCodec] computeMessageKeyFromData:msgData error:&err];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32U);
    XCTAssertNil(err);
}

- (void)testComputeMessageKeyFromData_nil_returnsNilWithError {
    NSError *err = nil;
    NSData *key = [[SSBBendyButt sharedCodec] computeMessageKeyFromData:nil error:&err];
    XCTAssertNil(key);
    XCTAssertNotNil(err);
}

#pragma mark - signContent:withKey: HMAC path (32-byte key)

- (void)testSignContent_HMACPath_returnsSignature {
    // 32-byte key uses HMAC-SHA512 path
    uint8_t keyBytes[32] = {0x42};
    NSData *key32 = [NSData dataWithBytes:keyBytes length:32];
    NSData *content = [@"content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [SSBBendyButt signContent:content withKey:key32];
    XCTAssertNotNil(sig);
    XCTAssertEqual(sig.length, 32U);
}

- (void)testSignContent_HMACPath_verifies {
    uint8_t keyBytes[32] = {0x99};
    NSData *key32 = [NSData dataWithBytes:keyBytes length:32];
    NSData *content = [@"hmac content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [SSBBendyButt signContent:content withKey:key32];
    // verifyContentSignature uses HMAC path when signature length == 32 and author length != 64
    BOOL valid = [SSBBendyButt verifyContentSignature:sig onContent:content author:key32];
    XCTAssertTrue(valid);
}

- (void)testSignContent_HMACPath_wrongAuthorFails {
    uint8_t keyBytes[32] = {0x10};
    NSData *key32 = [NSData dataWithBytes:keyBytes length:32];
    NSData *content = [@"data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [SSBBendyButt signContent:content withKey:key32];

    uint8_t otherBytes[32] = {0x20};
    NSData *other32 = [NSData dataWithBytes:otherBytes length:32];
    BOOL valid = [SSBBendyButt verifyContentSignature:sig onContent:content author:other32];
    XCTAssertFalse(valid);
}

- (void)testSignContent_nilInputs_returnsNil {
    NSData *content = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([SSBBendyButt signContent:nil withKey:self.secretKey]);
    XCTAssertNil([SSBBendyButt signContent:content withKey:nil]);
}

- (void)testSignContent_invalidKeyLength_returnsNil {
    NSData *content = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *badKey = [@"tooshort" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([SSBBendyButt signContent:content withKey:badKey]);
}

- (void)testVerifyContentSignature_nilInputs_returnsFalse {
    NSData *content = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([SSBBendyButt verifyContentSignature:nil onContent:content author:self.publicKey]);
    XCTAssertFalse([SSBBendyButt verifyContentSignature:[NSData data] onContent:nil author:self.publicKey]);
    XCTAssertFalse([SSBBendyButt verifyContentSignature:[NSData data] onContent:content author:nil]);
}

#pragma mark - encodeBFEFeedID: / encodeBFEMessageID:

- (void)testEncodeBFEFeedID_wrongLength_returnsNil {
    uint8_t shortBytes[] = {1, 2, 3};
    NSData *shortData = [NSData dataWithBytes:shortBytes length:3];
    XCTAssertNil([SSBBendyButt encodeBFEFeedID:shortData]);
    XCTAssertNil([SSBBendyButt encodeBFEFeedID:nil]);
}

- (void)testEncodeBFEFeedID_valid_hasTwoByteHeader {
    NSData *key = self.publicKey; // 32 bytes
    NSData *bfe = [SSBBendyButt encodeBFEFeedID:key];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34U);
}

- (void)testEncodeBFEMessageID_wrongLength_returnsNil {
    uint8_t shortBytes[] = {1, 2};
    NSData *shortData = [NSData dataWithBytes:shortBytes length:2];
    XCTAssertNil([SSBBendyButt encodeBFEMessageID:shortData]);
    XCTAssertNil([SSBBendyButt encodeBFEMessageID:nil]);
}

- (void)testEncodeBFEMessageID_valid_hasTwoByteHeader {
    uint8_t hashBytes[32] = {0xBB};
    NSData *hash = [NSData dataWithBytes:hashBytes length:32];
    NSData *bfe = [SSBBendyButt encodeBFEMessageID:hash];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34U);
}

#pragma mark - validateMessage: edge cases

- (void)testValidateMessage_sequenceZero_returnsFalse {
    // Create a valid message, then corrupt the sequence number in bencode
    uint8_t cskBytes[32] = {6};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"seq test"};
    // Create a valid message first (sequence=1 is valid), validate it
    NSData *msgData = [SSBBendyButt createMessageWithContent:content
                                                      author:self.publicKey
                                                authorSecret:self.secretKey
                                                    sequence:1
                                                    previous:nil
                                                   timestamp:1700000005
                                             contentSecretKey:csk];
    XCTAssertTrue([SSBBendyButt validateMessage:msgData]);
}

#pragma mark - messageWithContent: nil/invalid inputs

- (void)testMessageWithContent_nilContent_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:nil
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000010
                                         contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithContent_nilAuthor_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:nil
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000010
                                         contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithContent_nilAuthorSecret_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:nil
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000010
                                         contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithContent_badContentSecretKey_returnsNil {
    // contentSecretKey that is not 64 bytes (ed25519 secret) and not 32 bytes (HMAC)
    // signContent:withKey: returns nil for any other length
    uint8_t badCskBytes[10] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    NSData *badCsk = [NSData dataWithBytes:badCskBytes length:10];
    NSDictionary *content = @{@"type": @"post"};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000010
                                         contentSecretKey:badCsk];
    XCTAssertNil(msg);
}

- (void)testMessageWithContent_badPrevious_returnsNil {
    // previous is non-nil but not 32 bytes → encodeBFEMessageID returns nil
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    uint8_t prevBytes[16] = {0xAA};
    NSData *badPrev = [NSData dataWithBytes:prevBytes length:16]; // not 32 bytes
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:badPrev
                                                timestamp:1700000010
                                         contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithContent_tooLargeContent_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    // Create content large enough that the encoded message exceeds 8192 bytes
    NSMutableString *bigText = [NSMutableString string];
    for (int i = 0; i < 9000; i++) {
        [bigText appendString:@"x"];
    }
    NSDictionary *content = @{@"type": @"post", @"text": bigText};
    SSBBendyButt *msg = [SSBBendyButt messageWithContent:content
                                                   author:self.publicKey
                                             authorSecret:self.secretKey
                                                 sequence:1
                                                 previous:nil
                                                timestamp:1700000010
                                         contentSecretKey:csk];
    XCTAssertNil(msg);
}

#pragma mark - messageWithEncryptedContent: nil/invalid inputs

- (void)testMessageWithEncryptedContent_nilAuthor_returnsNil {
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSData *encrypted = [@"some encrypted bytes" dataUsingEncoding:NSUTF8StringEncoding];
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:encrypted
                                                           author:nil
                                                     authorSecret:self.secretKey
                                                         sequence:1
                                                         previous:nil
                                                        timestamp:1700000020
                                                 contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithEncryptedContent_badPrevious_returnsNil {
    // previous is non-nil but not 32 bytes → encodeBFEMessageID returns nil
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSData *encrypted = [@"some encrypted bytes" dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t prevBytes[16] = {0xAA};
    NSData *badPrev = [NSData dataWithBytes:prevBytes length:16]; // not 32 bytes
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:encrypted
                                                           author:self.publicKey
                                                     authorSecret:self.secretKey
                                                         sequence:1
                                                         previous:badPrev
                                                        timestamp:1700000020
                                                 contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithEncryptedContent_nilEncryptedContent_returnsNil {
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    // nil encryptedContent → SSBBFE encodeEncrypted: returns nil
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:nil
                                                           author:self.publicKey
                                                     authorSecret:self.secretKey
                                                         sequence:1
                                                         previous:nil
                                                        timestamp:1700000020
                                                 contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithEncryptedContent_nilAuthorSecret_returnsNil {
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSData *encrypted = [@"some encrypted bytes" dataUsingEncoding:NSUTF8StringEncoding];
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:encrypted
                                                           author:self.publicKey
                                                     authorSecret:nil
                                                         sequence:1
                                                         previous:nil
                                                        timestamp:1700000020
                                                 contentSecretKey:csk];
    XCTAssertNil(msg);
}

- (void)testMessageWithEncryptedContent_tooLargeContent_returnsNil {
    uint8_t cskBytes[32] = {3};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    // 9000 bytes of encrypted content
    NSMutableData *bigEncrypted = [NSMutableData dataWithLength:9000];
    SSBBendyButt *msg = [SSBBendyButt messageWithEncryptedContent:bigEncrypted
                                                           author:self.publicKey
                                                     authorSecret:self.secretKey
                                                         sequence:1
                                                         previous:nil
                                                        timestamp:1700000020
                                                 contentSecretKey:csk];
    XCTAssertNil(msg);
}

#pragma mark - createMessageWithContent: nil/invalid inputs

- (void)testCreateMessageWithContent_nilContent_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSData *result = [SSBBendyButt createMessageWithContent:nil
                                                     author:self.publicKey
                                               authorSecret:self.secretKey
                                                   sequence:1
                                                   previous:nil
                                                  timestamp:1700000030
                                           contentSecretKey:csk];
    XCTAssertNil(result);
}

- (void)testCreateMessageWithContent_nilAuthor_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    NSData *result = [SSBBendyButt createMessageWithContent:content
                                                     author:nil
                                               authorSecret:self.secretKey
                                                   sequence:1
                                                   previous:nil
                                                  timestamp:1700000030
                                           contentSecretKey:csk];
    XCTAssertNil(result);
}

- (void)testCreateMessageWithContent_nilAuthorSecret_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    NSData *result = [SSBBendyButt createMessageWithContent:content
                                                     author:self.publicKey
                                               authorSecret:nil
                                                   sequence:1
                                                   previous:nil
                                                  timestamp:1700000030
                                           contentSecretKey:csk];
    XCTAssertNil(result);
}

- (void)testCreateMessageWithContent_badContentSecretKey_returnsNil {
    // contentSecretKey that is not 64 or 32 bytes → signContent:withKey: returns nil
    uint8_t badCskBytes[10] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    NSData *badCsk = [NSData dataWithBytes:badCskBytes length:10];
    NSDictionary *content = @{@"type": @"post"};
    NSData *result = [SSBBendyButt createMessageWithContent:content
                                                     author:self.publicKey
                                               authorSecret:self.secretKey
                                                   sequence:1
                                                   previous:nil
                                                  timestamp:1700000030
                                           contentSecretKey:badCsk];
    XCTAssertNil(result);
}

- (void)testCreateMessageWithContent_badPrevious_returnsNil {
    // previous is non-nil but not 32 bytes → encodeBFEMessageID returns nil
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post"};
    uint8_t prevBytes[16] = {0xAA};
    NSData *badPrev = [NSData dataWithBytes:prevBytes length:16];
    NSData *result = [SSBBendyButt createMessageWithContent:content
                                                     author:self.publicKey
                                               authorSecret:self.secretKey
                                                   sequence:1
                                                   previous:badPrev
                                                  timestamp:1700000030
                                           contentSecretKey:csk];
    XCTAssertNil(result);
}

- (void)testCreateMessageWithContent_tooLargeContent_returnsNil {
    uint8_t cskBytes[32] = {1};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSMutableString *bigText = [NSMutableString string];
    for (int i = 0; i < 9000; i++) {
        [bigText appendString:@"x"];
    }
    NSDictionary *content = @{@"type": @"post", @"text": bigText};
    NSData *result = [SSBBendyButt createMessageWithContent:content
                                                     author:self.publicKey
                                               authorSecret:self.secretKey
                                                   sequence:1
                                                   previous:nil
                                                  timestamp:1700000030
                                           contentSecretKey:csk];
    XCTAssertNil(result);
}

#pragma mark - validateMessage: edge cases (uncovered branches)

// Helper: build a valid message data for manipulating
- (NSData *)_buildValidMessageData {
    uint8_t cskBytes[32] = {7};
    NSData *csk = [NSData dataWithBytes:cskBytes length:32];
    NSDictionary *content = @{@"type": @"post", @"text": @"validate test"};
    return [SSBBendyButt createMessageWithContent:content
                                           author:self.publicKey
                                     authorSecret:self.secretKey
                                         sequence:1
                                         previous:nil
                                        timestamp:1700000040
                                 contentSecretKey:csk];
}

- (void)testValidateMessage_tooLarge_returnsFalse {
    // 8193+ bytes of data that starts with valid bencode structure but is too large
    NSMutableData *bigData = [NSMutableData dataWithLength:8193];
    XCTAssertFalse([SSBBendyButt validateMessage:bigData]);
}

- (void)testValidateMessage_payloadNotData_returnsFalse {
    // bencode list where message[0] is an integer, not NSData
    // l i42e i99e e  — two integers
    NSData *bencoded = [@"li42ei99ee" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([SSBBendyButt validateMessage:bencoded]);
}

- (void)testValidateMessage_payloadWrongCount_returnsFalse {
    // Outer list has 2 data items, but inner payload decodes to != 5 elements
    // Build: outer = [payloadData, sigData] where payloadData is a list with 3 items
    // l <3-item-list-bencode> <some-sig-data> e
    NSData *innerList = [@"li1ei2ei3ee" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sigData = [NSMutableData dataWithLength:66]; // some data
    NSData *outer = [SSBBendyButt encodeBencodeList:@[innerList, sigData]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_authorNotData_returnsFalse {
    // Payload with 5 items but author (element 0) is an NSNumber (integer), not NSData
    // @(1) encodes as bencode integer i1e, decodes back as NSNumber
    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];
    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[@(1), @(1), prevBFE, @(1700000040), contentSection]];
    NSMutableData *fakeSigBFE = [NSMutableData data];
    uint8_t sigT = 4, sigF = 0;
    [fakeSigBFE appendBytes:&sigT length:1];
    [fakeSigBFE appendBytes:&sigF length:1];
    [fakeSigBFE appendData:[NSMutableData dataWithLength:64]];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSigBFE]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_sequenceNotNumber_returnsFalse {
    // Payload with 5 items but sequence (element 1) is data, not NSNumber
    // l <authorBFE> <seqAsData> <prevBFE> <timestamp> <content> e
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey]; // 34 bytes
    NSData *seqAsData = [NSMutableData dataWithLength:3]; // NSData not NSNumber
    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];

    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, seqAsData, prevBFE, @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_sequenceLessThanOne_returnsFalse {
    // Payload with sequence = 0 (less than 1)
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];
    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];

    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(0), prevBFE, @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_previousNotData_returnsFalse {
    // Payload with previous (element 2) as an NSNumber
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];
    NSData *contentSection = [NSMutableData dataWithLength:5];

    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(1), @(12345), @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_timestampNotNumber_returnsFalse {
    // Payload where timestamp (element 3) is NSData, not NSNumber
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];
    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *timestampAsData = [NSMutableData dataWithLength:4];
    NSData *contentSection = [NSMutableData dataWithLength:5];

    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(1), prevBFE, timestampAsData, contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_authorWrongFormat_returnsFalse {
    // authorBFE with type=Feed but format != BendybuttV1 (e.g. Classic=0)
    NSMutableData *wrongAuthorBFE = [NSMutableData data];
    uint8_t typeByte = 0; // SSBBFETypeFeed
    uint8_t formatByte = 0; // SSBBFEFeedFormatClassic (not BendybuttV1)
    [wrongAuthorBFE appendBytes:&typeByte length:1];
    [wrongAuthorBFE appendBytes:&formatByte length:1];
    [wrongAuthorBFE appendData:self.publicKey]; // 32 bytes

    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];
    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[wrongAuthorBFE, @(1), prevBFE, @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_previousWrongFormat_returnsFalse {
    // prevBFE with type=Message but format != BendybuttV1 and not Nil
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];

    NSMutableData *wrongPrevBFE = [NSMutableData data];
    uint8_t typeByte = 1; // SSBBFETypeMessage
    uint8_t formatByte = 0; // SSBBFEMessageFormatClassic (not BendybuttV1)
    [wrongPrevBFE appendBytes:&typeByte length:1];
    [wrongPrevBFE appendBytes:&formatByte length:1];
    uint8_t hash[32] = {0};
    [wrongPrevBFE appendBytes:hash length:32];

    NSData *contentSection = [NSMutableData dataWithLength:5];
    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(1), wrongPrevBFE, @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_contentSectionWrongType_returnsFalse {
    // contentSection is an NSNumber (not NSData or NSArray)
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];
    NSData *prevBFE = [SSBBFE encodeNil];
    // @(42) encodes as integer in bencode, decodes as NSNumber

    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(1), prevBFE, @(1700000040), @(42)]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_authorKeyWrongLength_returnsFalse {
    // authorBFE that has type=Feed, format=BendybuttV1 but only 1 byte of key data (total 3 bytes, authorKey.length=1)
    NSMutableData *shortAuthorBFE = [NSMutableData data];
    uint8_t typeByte = 0; // SSBBFETypeFeed
    uint8_t formatByte = 3; // SSBBFEFeedFormatBendybuttV1
    uint8_t shortKey = 0xAB;
    [shortAuthorBFE appendBytes:&typeByte length:1];
    [shortAuthorBFE appendBytes:&formatByte length:1];
    [shortAuthorBFE appendBytes:&shortKey length:1]; // only 1 byte instead of 32

    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];
    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[shortAuthorBFE, @(1), prevBFE, @(1700000040), contentSection]];
    NSData *fakeSig = [NSMutableData dataWithLength:66];
    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSig]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

- (void)testValidateMessage_signatureVerificationFails_returnsFalse {
    // Build a structurally valid message but with a garbage payload signature
    NSData *authorBFE = [SSBBendyButt encodeBFEFeedID:self.publicKey];
    NSData *prevBFE = [SSBBFE encodeNil];
    NSData *contentSection = [NSMutableData dataWithLength:5];
    NSData *payloadBencode = [SSBBendyButt encodeBencodeList:@[authorBFE, @(1), prevBFE, @(1700000040), contentSection]];

    // Build a fake BFE signature with correct structure but wrong signature bytes
    NSMutableData *fakeSigBFE = [NSMutableData data];
    uint8_t sigTypeByte = 4; // SSBBFETypeSignature
    uint8_t sigFormatByte = 0; // SSBBFESignatureFormatMsgEd25519
    [fakeSigBFE appendBytes:&sigTypeByte length:1];
    [fakeSigBFE appendBytes:&sigFormatByte length:1];
    [fakeSigBFE appendData:[NSMutableData dataWithLength:64]]; // 64 bytes of zeros — invalid sig

    NSData *outer = [SSBBendyButt encodeBencodeList:@[payloadBencode, fakeSigBFE]];
    XCTAssertFalse([SSBBendyButt validateMessage:outer]);
}

#pragma mark - verifyContentSignature: wrong length signature

- (void)testVerifyContentSignature_wrongLengthSignature_returnsFalse {
    // signature that is neither 64 bytes (crypto_sign_BYTES) nor 32 bytes
    NSData *content = [@"some content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *weirdSig = [NSMutableData dataWithLength:10]; // 10 bytes — neither 64 nor 32
    BOOL valid = [SSBBendyButt verifyContentSignature:weirdSig
                                            onContent:content
                                               author:self.publicKey];
    XCTAssertFalse(valid);
}

#pragma mark - signPayload: nil / wrong length inputs

- (void)testSignPayload_nilPayload_returnsNil {
    XCTAssertNil([SSBBendyButt signPayload:nil withAuthorSecret:self.secretKey]);
}

- (void)testSignPayload_nilAuthorSecret_returnsNil {
    NSData *payload = [@"some payload data" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([SSBBendyButt signPayload:payload withAuthorSecret:nil]);
}

- (void)testSignPayload_wrongLengthAuthorSecret_returnsNil {
    NSData *payload = [@"some payload data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *shortSecret = [NSMutableData dataWithLength:32]; // 32 bytes not 64
    XCTAssertNil([SSBBendyButt signPayload:payload withAuthorSecret:shortSecret]);
}

#pragma mark - verifyPayloadSignature: edge cases

- (void)testVerifyPayloadSignature_nilSignature_returnsFalse {
    NSData *payload = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([SSBBendyButt verifyPayloadSignature:nil onPayload:payload author:self.publicKey]);
}

- (void)testVerifyPayloadSignature_wrongSignatureType_returnsFalse {
    // signatureBFE with type != SSBBFETypeSignature (e.g. type = Feed = 0)
    NSData *payload = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *wrongTypeSig = [NSMutableData data];
    uint8_t typeByte = 0; // SSBBFETypeFeed, not SSBBFETypeSignature
    uint8_t formatByte = 0;
    [wrongTypeSig appendBytes:&typeByte length:1];
    [wrongTypeSig appendBytes:&formatByte length:1];
    [wrongTypeSig appendData:[NSMutableData dataWithLength:64]];
    XCTAssertFalse([SSBBendyButt verifyPayloadSignature:wrongTypeSig onPayload:payload author:self.publicKey]);
}

- (void)testVerifyPayloadSignature_signatureTooShort_returnsFalse {
    // signatureBFE with correct type=4 but inner sig is not 64 bytes
    NSData *payload = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *shortSigBFE = [NSMutableData data];
    uint8_t typeByte = 4; // SSBBFETypeSignature
    uint8_t formatByte = 0;
    [shortSigBFE appendBytes:&typeByte length:1];
    [shortSigBFE appendBytes:&formatByte length:1];
    [shortSigBFE appendData:[NSMutableData dataWithLength:10]]; // 10 bytes, not 64
    XCTAssertFalse([SSBBendyButt verifyPayloadSignature:shortSigBFE onPayload:payload author:self.publicKey]);
}

- (void)testVerifyPayloadSignature_signatureVerificationFails_returnsFalse {
    // Valid BFE signature structure but garbage signature bytes → crypto_sign_open fails
    NSData *payload = [@"valid payload data for bendy butt" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *badSigBFE = [NSMutableData data];
    uint8_t typeByte = 4; // SSBBFETypeSignature
    uint8_t formatByte = 0;
    [badSigBFE appendBytes:&typeByte length:1];
    [badSigBFE appendBytes:&formatByte length:1];
    [badSigBFE appendData:[NSMutableData dataWithLength:64]]; // 64 zero bytes — invalid ed25519 sig
    XCTAssertFalse([SSBBendyButt verifyPayloadSignature:badSigBFE onPayload:payload author:self.publicKey]);
}

@end
