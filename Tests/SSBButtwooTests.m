#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBButtwoo.h>
#import <SSBNetwork/SSBBIPF.h>
#import <SSBNetwork/SSBBFE.h>
#import <SSBNetwork/tweetnacl.h>
#define crypto_sign_BYTES 64

// blake3_256 exposed for known-answer testing.
extern int blake3_256(uint8_t out[32], const void *in, size_t inlen);

static void BTWGenerateKeypair(NSData **outPK, NSData **outSK) {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPK) *outPK = [NSData dataWithBytes:pk length:32];
    if (outSK) *outSK = [NSData dataWithBytes:sk length:64];
}

// Build a BFE author tag for Buttwoo: type=0x00 (Feed), format=0x04 (ButtwooV1), + 32-byte key
static NSData *BTWAuthorBFE(NSData *pubKey) {
    NSMutableData *bfe = [NSMutableData dataWithCapacity:34];
    uint8_t header[2] = {0x00, 0x04};
    [bfe appendBytes:header length:2];
    [bfe appendData:pubKey];
    return bfe;
}

// BFE nil: type=0x06 (Generic), format=0x02 (Nil)
static NSData *BTWNilBFE(void) {
    uint8_t bytes[] = {0x06, 0x02};
    return [NSData dataWithBytes:bytes length:2];
}

// BFE signature: type=0x04, format=0x00, + 64-byte signature
static NSData *BTWSignatureBFE(NSData *signature) {
    NSMutableData *bfe = [NSMutableData dataWithCapacity:66];
    uint8_t header[2] = {0x04, 0x00};
    [bfe appendBytes:header length:2];
    [bfe appendData:signature];
    return bfe;
}

// Construct a valid Buttwoo seq=1 message using BIPF wire encoding.
//   outer = BIPF list [payloadBytes, sigBFE]
//   payload = BIPF list [authorBFE, @1, prevBFE(nil), @0, contentData]
static NSData *BTWBuildValidSeq1Message(NSData *pubKey, NSData *secretKey) {
    NSData *authorBFE = BTWAuthorBFE(pubKey);
    NSData *prevBFE   = BTWNilBFE();
    NSData *content   = [@"test content" dataUsingEncoding:NSUTF8StringEncoding];

    // Encode payload list as BIPF
    NSArray *payloadList = @[authorBFE, @1, prevBFE, @0, content];
    NSData *payloadBytes = [SSBBIPF encodeList:payloadList];

    // Sign payloadBytes with Ed25519
    unsigned long long smLen = 64 + (unsigned long long)payloadBytes.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payloadBytes.bytes, (unsigned long long)payloadBytes.length,
                        (const unsigned char *)secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    NSData *sigBFE = BTWSignatureBFE(sig);

    // Encode outer list as BIPF: [payloadBytes, sigBFE]
    NSArray *outerList = @[payloadBytes, sigBFE];
    return [SSBBIPF encodeList:outerList];
}

@interface SSBButtwooTests : XCTestCase
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, strong) NSData *secretKey;
@end

@implementation SSBButtwooTests

- (void)setUp {
    [super setUp];
    NSData *publicKey = nil;
    NSData *secretKey = nil;
    BTWGenerateKeypair(&publicKey, &secretKey);
    self.publicKey = publicKey;
    self.secretKey = secretKey;
}

#pragma mark - BLAKE3 known-answer test

- (void)testBlake3_256_knownVector_buttwooInput {
    // BLAKE3-256 of zero author key (32 bytes) || seq=1 big-endian (8 bytes)
    // Computed by compiling blake3.c against a standalone driver; cross-check with
    // `python3 -c "import sys; sys.stdout.buffer.write(b'\x00'*32+(1).to_bytes(8,'big'))"| b3sum`
    static const uint8_t expected[32] = {
        0x3f, 0xf4, 0x09, 0x50, 0xdd, 0x84, 0x0e, 0xc9,
        0x05, 0x00, 0xc1, 0xa1, 0x91, 0xf8, 0x3d, 0x72,
        0xbc, 0x8f, 0x27, 0x12, 0xd3, 0x91, 0xdf, 0xe1,
        0x74, 0x07, 0x26, 0x1a, 0x5f, 0x2d, 0x46, 0x0c
    };
    uint8_t in[40] = {0};
    in[39] = 1; /* seq=1, big-endian */
    uint8_t out[32];
    int ret = blake3_256(out, in, 40);
    XCTAssertEqual(ret, 0);
    XCTAssertEqual(memcmp(out, expected, 32), 0,
                   @"BLAKE3 buttwoo 40-byte input vector mismatch");
}

- (void)testBlake3_256_knownVector_emptyInput {
    // BLAKE3("") from the official test vectors:
    // https://github.com/BLAKE3-team/BLAKE3/blob/master/test_vectors/test_vectors.json
    // Expected (first 32 bytes): af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262
    static const uint8_t expected[32] = {
        0xaf, 0x13, 0x49, 0xb9, 0xf5, 0xf9, 0xa1, 0xa6,
        0xa0, 0x40, 0x4d, 0xea, 0x36, 0xdc, 0xc9, 0x49,
        0x9b, 0xcb, 0x25, 0xc9, 0xad, 0xc1, 0x12, 0xb7,
        0xcc, 0x9a, 0x93, 0xca, 0xe4, 0x1f, 0x32, 0x62
    };
    uint8_t out[32];
    int ret = blake3_256(out, NULL, 0);
    XCTAssertEqual(ret, 0);
    XCTAssertEqual(memcmp(out, expected, 32), 0, @"BLAKE3 empty-input vector mismatch");
}

#pragma mark - computeDeterministicKey:sequence:

- (void)testDeterministicKey_nilKey {
    NSData *key = [SSBButtwoo computeDeterministicKey:nil sequence:1];
    XCTAssertNil(key);
}

- (void)testDeterministicKey_wrongKeyLength {
    NSData *shortKey = [NSData dataWithBytes:"\x01\x02\x03" length:3];
    NSData *key = [SSBButtwoo computeDeterministicKey:shortKey sequence:1];
    XCTAssertNil(key);
}

- (void)testDeterministicKey_zeroSequence {
    NSData *key = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:0];
    XCTAssertNil(key);
}

- (void)testDeterministicKey_negativeSequence {
    NSData *key = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:-1];
    XCTAssertNil(key);
}

- (void)testDeterministicKey_validReturns32Bytes {
    NSData *key = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:1];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
}

- (void)testDeterministicKey_seq1VsSeq2Differ {
    NSData *k1 = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:1];
    NSData *k2 = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:2];
    XCTAssertNotEqualObjects(k1, k2);
}

- (void)testDeterministicKey_differentAuthorsProduceDifferentKeys {
    NSData *otherPK, *otherSK;
    BTWGenerateKeypair(&otherPK, &otherSK);
    NSData *k1 = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:1];
    NSData *k2 = [SSBButtwoo computeDeterministicKey:otherPK sequence:1];
    XCTAssertNotEqualObjects(k1, k2);
}

- (void)testDeterministicKey_deterministic {
    NSData *k1 = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:5];
    NSData *k2 = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:5];
    XCTAssertEqualObjects(k1, k2);
}

- (void)testDeterministicKey_largeSequence {
    NSData *key = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:1000000];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
}

#pragma mark - validateMessage: — invalid inputs

- (void)testValidateMessage_nil {
    XCTAssertFalse([SSBButtwoo validateMessage:nil]);
}

- (void)testValidateMessage_empty {
    XCTAssertFalse([SSBButtwoo validateMessage:[NSData data]]);
}

- (void)testValidateMessage_notBIPF {
    NSData *garbage = [@"this is not BIPF" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([SSBButtwoo validateMessage:garbage]);
}

- (void)testValidateMessage_tooLarge {
    // > 8192 bytes
    NSData *big = [NSMutableData dataWithLength:9000];
    XCTAssertFalse([SSBButtwoo validateMessage:big]);
}

- (void)testValidateMessage_outerListTooFewElements {
    // Outer BIPF list with only one element (needs 2)
    NSData *encoded = [SSBBIPF encodeList:@[@"only one"]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_outerIsNotList {
    // Outer is a BIPF integer, not a list
    NSData *encoded = [SSBBIPF encodeInteger:42];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_payloadNotList {
    // payload element is a plain string, not a BIPF-encoded list
    NSData *fakePayload = [@"not a list" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[fakePayload, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_payloadTooFewFields {
    // payload list has 3 elements instead of 5
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, BTWNilBFE()]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_badSignature {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    // Flip a byte in the signature
    NSMutableData *tampered = [msg mutableCopy];
    uint8_t *bytes = tampered.mutableBytes;
    bytes[tampered.length - 5] ^= 0xFF;
    XCTAssertFalse([SSBButtwoo validateMessage:tampered]);
}

- (void)testValidateMessage_wrongAuthorType {
    // Author BFE with wrong type byte (type=0x01 instead of 0x00)
    NSMutableData *badAuthorBFE = [NSMutableData dataWithCapacity:34];
    uint8_t header[2] = {0x01, 0x04}; // type=Message instead of Feed
    [badAuthorBFE appendBytes:header length:2];
    [badAuthorBFE appendData:self.publicKey];

    NSData *payloadBytes = [SSBBIPF encodeList:@[badAuthorBFE, @1, BTWNilBFE(), @0,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];

    unsigned long long smLen = 64 + (unsigned long long)payloadBytes.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payloadBytes.bytes, (unsigned long long)payloadBytes.length,
                        (const unsigned char *)self.secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, BTWSignatureBFE(sig)]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

#pragma mark - validateMessage: — valid message

- (void)testValidateMessage_validSeq1 {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    XCTAssertTrue([SSBButtwoo validateMessage:msg]);
}

- (void)testValidateMessage_validSeq1_alternateKeypair {
    NSData *otherPK, *otherSK;
    BTWGenerateKeypair(&otherPK, &otherSK);
    NSData *msg = BTWBuildValidSeq1Message(otherPK, otherSK);
    XCTAssertTrue([SSBButtwoo validateMessage:msg]);
}

#pragma mark - BIPF round-trip

- (void)testValidateMessage_BIPF_outerDecodesCorrectly {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);

    // Outer BIPF list should decode to [payloadBytes, sigBFE]
    NSUInteger consumed = 0;
    id outer = [SSBBIPF decode:msg consumed:&consumed];
    XCTAssertNotNil(outer);
    XCTAssertTrue([outer isKindOfClass:[NSArray class]]);
    XCTAssertEqual([(NSArray *)outer count], 2u);

    // First element (payload) should be NSData
    XCTAssertTrue([outer[0] isKindOfClass:[NSData class]]);

    // Inner payload should decode as a BIPF list with 5 fields
    NSUInteger payloadConsumed = 0;
    id inner = [SSBBIPF decode:outer[0] consumed:&payloadConsumed];
    XCTAssertNotNil(inner);
    XCTAssertTrue([inner isKindOfClass:[NSArray class]]);
    XCTAssertEqual([(NSArray *)inner count], 5u);
}

#pragma mark - computeMessageKey:

- (void)testComputeMessageKey_nil {
    XCTAssertNil([SSBButtwoo computeMessageKey:nil]);
}

- (void)testComputeMessageKey_empty {
    XCTAssertNil([SSBButtwoo computeMessageKey:[NSData data]]);
}

- (void)testComputeMessageKey_garbageInput {
    NSData *garbage = [@"not valid" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([SSBButtwoo computeMessageKey:garbage]);
}

- (void)testComputeMessageKey_validMessage_returns32Bytes {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSData *key = [SSBButtwoo computeMessageKey:msg];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
}

- (void)testComputeMessageKey_matchesDeterministicKey {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSData *keyFromMsg = [SSBButtwoo computeMessageKey:msg];

    NSData *expectedKey = [SSBButtwoo computeDeterministicKey:self.publicKey sequence:1];
    XCTAssertEqualObjects(keyFromMsg, expectedKey);
}

- (void)testComputeMessageKey_deterministic {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSData *k1 = [SSBButtwoo computeMessageKey:msg];
    NSData *k2 = [SSBButtwoo computeMessageKey:msg];
    XCTAssertEqualObjects(k1, k2);
}

#pragma mark - SSBFeedCodec Protocol Conformance

- (void)testFeedFormat {
    XCTAssertEqual([SSBButtwoo sharedCodec].feedFormat, SSBBFEFeedFormatButtwooV1);
}

- (void)testMessageFormat {
    XCTAssertEqual([SSBButtwoo sharedCodec].messageFormat, SSBBFEMessageFormatButtwooV1);
}

- (void)testVerifyMessageData_valid {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSError *error = nil;
    BOOL result = [[SSBButtwoo sharedCodec] verifyMessageData:msg error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testVerifyMessageData_invalid_setsError {
    NSData *badData = [@"not a buttwoo message" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL result = [[SSBButtwoo sharedCodec] verifyMessageData:badData error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testComputeMessageKeyFromData_valid {
    NSData *msg = BTWBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSError *error = nil;
    NSData *key = [[SSBButtwoo sharedCodec] computeMessageKeyFromData:msg error:&error];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
    XCTAssertNil(error);
}

- (void)testComputeMessageKeyFromData_invalid_setsError {
    NSData *badData = [NSData data];
    NSError *error = nil;
    NSData *key = [[SSBButtwoo sharedCodec] computeMessageKeyFromData:badData error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

- (void)testSharedCodec_returnsSameInstance {
    id<SSBFeedCodec> a = [SSBButtwoo sharedCodec];
    id<SSBFeedCodec> b = [SSBButtwoo sharedCodec];
    XCTAssertEqual(a, b);
}

// MARK: - validateMessage: author BFE edge cases

- (void)testValidateMessage_wrongAuthorFormat {
    // type=Feed (0x00) but format=Classic (0x01) not ButtwooV1 (0x04)
    NSMutableData *badAuthorBFE = [NSMutableData dataWithCapacity:34];
    uint8_t header[2] = {0x00, 0x01};
    [badAuthorBFE appendBytes:header length:2];
    [badAuthorBFE appendData:self.publicKey]; // 32 bytes → total 34

    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[badAuthorBFE, @1, BTWNilBFE(), @0, content]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_shortAuthorBFE {
    // type=Feed, format=ButtwooV1, but only 12 bytes total (not 34)
    NSMutableData *shortAuthorBFE = [NSMutableData dataWithCapacity:12];
    uint8_t header[2] = {0x00, 0x04};
    [shortAuthorBFE appendBytes:header length:2];
    uint8_t partial[10] = {0};
    [shortAuthorBFE appendBytes:partial length:10]; // 12 total, need 34

    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[shortAuthorBFE, @1, BTWNilBFE(), @0, content]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_wrongPrevBFEFormat {
    // previous BFE that is neither nil-BFE (0x06,0x02) nor ButtwooMsg-BFE (0x01,0x05)
    NSMutableData *wrongPrevBFE = [NSMutableData dataWithCapacity:34];
    uint8_t prevHeader[2] = {0x01, 0x00}; // Message type, ClassicMsg format
    [wrongPrevBFE appendBytes:prevHeader length:2];
    uint8_t hash[32] = {0};
    [wrongPrevBFE appendBytes:hash length:32]; // 34 bytes total

    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, wrongPrevBFE, @0, content]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

// MARK: - validateMessage: signature BFE edge cases

- (void)testValidateMessage_wrongSignatureBFEType {
    // Sig BFE type=Feed (0x00) instead of Signature (0x04)
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, BTWNilBFE(), @0, content]];

    NSMutableData *badSigBFE = [NSMutableData dataWithCapacity:66];
    uint8_t sigHeader[2] = {0x00, 0x00}; // wrong type
    [badSigBFE appendBytes:sigHeader length:2];
    [badSigBFE appendData:[NSMutableData dataWithLength:64]];

    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, badSigBFE]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_shortSignatureBFE {
    // Sig BFE type=Signature (0x04) but only 12 bytes, need ≥ 66
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, BTWNilBFE(), @0, content]];

    NSMutableData *shortSigBFE = [NSMutableData dataWithCapacity:12];
    uint8_t sigHeader[2] = {0x04, 0x00};
    [shortSigBFE appendBytes:sigHeader length:2];
    [shortSigBFE appendData:[NSMutableData dataWithLength:10]]; // 12 total, need ≥ 66

    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, shortSigBFE]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

// MARK: - computeMessageKey: edge cases

- (void)testComputeMessageKey_emptyOuterList {
    NSData *encoded = [SSBBIPF encodeList:@[]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

- (void)testComputeMessageKey_payloadIsInteger {
    // outer[0] is NSNumber, not NSData
    NSData *encoded = [SSBBIPF encodeList:@[@42]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

- (void)testComputeMessageKey_payloadListTooShort {
    // payload BIPF list has only 1 element (needs ≥ 2)
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *shortPayload = [SSBBIPF encodeList:@[authorBFE]];
    NSData *encoded = [SSBBIPF encodeList:@[shortPayload, [NSMutableData dataWithLength:66]]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

- (void)testComputeMessageKey_shortAuthorBFE {
    // authorBFE.length != 34 in payload
    NSMutableData *shortAuthorBFE = [NSMutableData dataWithCapacity:12];
    uint8_t header[2] = {0x00, 0x04};
    [shortAuthorBFE appendBytes:header length:2];
    uint8_t partial[10] = {0};
    [shortAuthorBFE appendBytes:partial length:10]; // 12, not 34

    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payload = [SSBBIPF encodeList:@[shortAuthorBFE, @1, BTWNilBFE(), @0, content]];
    NSData *encoded = [SSBBIPF encodeList:@[payload, [NSMutableData dataWithLength:66]]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

- (void)testComputeMessageKey_sequenceZero {
    // sequenceNum.integerValue < 1
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *content = [@"c" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payload = [SSBBIPF encodeList:@[authorBFE, @0, BTWNilBFE(), @0, content]];
    NSData *encoded = [SSBBIPF encodeList:@[payload, [NSMutableData dataWithLength:66]]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

// MARK: - validateMessage: payload element type checks

- (void)testValidateMessage_outerElementsNotNSData {
    // Outer list has 2 elements but both are NSNumber, not NSData
    NSData *encoded = [SSBBIPF encodeList:@[@42, @99]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_payloadAuthorNotNSData {
    // payload[0] is NSNumber, not NSData
    NSData *payloadBytes = [SSBBIPF encodeList:@[@42, @1, BTWNilBFE(), @0,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_sequenceNotNSNumber {
    // payload[1] is NSData, not NSNumber
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *notANumber = [@"1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, notANumber, BTWNilBFE(), @0,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_sequenceZero_inValidateMessage {
    // payload[1] is @0 (NSNumber but < 1)
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @0, BTWNilBFE(), @0,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_previousNotNSData {
    // payload[2] is NSNumber, not NSData
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, @42, @0,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_timestampNotNSNumber {
    // payload[3] is NSData, not NSNumber
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *notANumber = [@"0" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadBytes = [SSBBIPF encodeList:@[authorBFE, @1, BTWNilBFE(), notANumber,
                                                 [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payloadBytes, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

// MARK: - computeMessageKey: additional paths

- (void)testComputeMessageKey_tooLarge {
    // Message exceeding kMaxMessageSize (8192) should return nil
    NSData *big = [NSMutableData dataWithLength:8193];
    XCTAssertNil([SSBButtwoo computeMessageKey:big]);
}

- (void)testComputeMessageKey_payloadNotBIPFList {
    // outer[0] is NSData that decodes as BIPF integer, not list
    NSData *intPayload = [SSBBIPF encodeInteger:42]; // decodes to NSNumber
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[intPayload, fakeSig]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

- (void)testComputeMessageKey_sequenceNotNSNumber {
    // payload[1] is NSData, not NSNumber
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *notNum = [@"1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payload = [SSBBIPF encodeList:@[authorBFE, notNum, BTWNilBFE(), @0,
                                            [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];
    NSData *fakeSig = BTWSignatureBFE([NSMutableData dataWithLength:64]);
    NSData *encoded = [SSBBIPF encodeList:@[payload, fakeSig]];
    XCTAssertNil([SSBButtwoo computeMessageKey:encoded]);
}

@end
