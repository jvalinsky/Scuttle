#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBButtwoo.h>
#import <SSBNetwork/SSBBencode.h>
#import <SSBNetwork/SSBBFE.h>
#import <CommonCrypto/CommonDigest.h>

// TweetNaCl functions linked via SSBNetwork.framework.
extern int crypto_sign_ed25519_keypair(unsigned char *pk, unsigned char *sk);
extern int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen,
                               const unsigned char *m, unsigned long long mlen,
                               const unsigned char *sk);
#define crypto_sign_BYTES 64

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

// Construct a valid Buttwoo seq=1 message.
//   outer = [payloadBytes, sigBFE]  (as bencode list)
//   payload = [authorBFE, @1, prevBFE(nil), @0, contentData]  (as bencode list)
static NSData *BTWBuildValidSeq1Message(NSData *pubKey, NSData *secretKey) {
    NSData *authorBFE = BTWAuthorBFE(pubKey);
    NSData *prevBFE   = BTWNilBFE();
    NSData *content   = [@"test content" dataUsingEncoding:NSUTF8StringEncoding];

    // Encode payload list
    NSArray *payloadList = @[authorBFE, @1, prevBFE, @0, content];
    NSData *payloadBytes = [SSBBencode encodeList:payloadList];

    // Sign payloadBytes with Ed25519
    unsigned long long smLen = 64 + (unsigned long long)payloadBytes.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payloadBytes.bytes, (unsigned long long)payloadBytes.length,
                        (const unsigned char *)secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    NSData *sigBFE = BTWSignatureBFE(sig);

    // Encode outer list: [payloadBytes, sigBFE]
    NSArray *outerList = @[payloadBytes, sigBFE];
    return [SSBBencode encodeList:outerList];
}

@interface SSBButtwooTests : XCTestCase
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, strong) NSData *secretKey;
@end

@implementation SSBButtwooTests

- (void)setUp {
    [super setUp];
    BTWGenerateKeypair(&_publicKey, &_secretKey);
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

- (void)testValidateMessage_notBencode {
    NSData *garbage = [@"this is not bencode" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([SSBButtwoo validateMessage:garbage]);
}

- (void)testValidateMessage_tooLarge {
    // > 8192 bytes
    NSData *big = [NSData dataWithLength:9000];
    XCTAssertFalse([SSBButtwoo validateMessage:big]);
}

- (void)testValidateMessage_outerListTooFewElements {
    // Outer list with only one element (needs 2)
    NSData *encoded = [SSBBencode encodeList:@[@"only one"]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_outerIsNotList {
    // Outer is a bencode integer, not list
    NSData *encoded = [SSBBencode encodeInteger:42];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_payloadNotList {
    // payload element is a plain string, not a bencode-encoded list
    NSData *fakePayload = [@"not a list" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *fakeSig = BTWSignatureBFE([NSData dataWithLength:64]);
    NSData *encoded = [SSBBencode encodeList:@[fakePayload, fakeSig]];
    XCTAssertFalse([SSBButtwoo validateMessage:encoded]);
}

- (void)testValidateMessage_payloadTooFewFields {
    // payload list has 3 elements instead of 5
    NSData *authorBFE = BTWAuthorBFE(self.publicKey);
    NSData *payloadBytes = [SSBBencode encodeList:@[authorBFE, @1, BTWNilBFE()]];
    NSData *fakeSig = BTWSignatureBFE([NSData dataWithLength:64]);
    NSData *encoded = [SSBBencode encodeList:@[payloadBytes, fakeSig]];
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

    NSData *payloadBytes = [SSBBencode encodeList:@[badAuthorBFE, @1, BTWNilBFE(), @0,
                                                    [@"c" dataUsingEncoding:NSUTF8StringEncoding]]];

    unsigned long long smLen = 64 + (unsigned long long)payloadBytes.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payloadBytes.bytes, (unsigned long long)payloadBytes.length,
                        (const unsigned char *)self.secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    NSData *encoded = [SSBBencode encodeList:@[payloadBytes, BTWSignatureBFE(sig)]];
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

    // Extract the 32-byte public key from our pubkey data
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

@end
