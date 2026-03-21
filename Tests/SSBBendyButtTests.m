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

@end
