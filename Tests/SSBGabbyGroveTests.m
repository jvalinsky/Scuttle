#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBGabbyGrove.h>
#import <CommonCrypto/CommonCrypto.h>

// TweetNaCl Ed25519 functions linked via SSBNetwork.framework.
extern int crypto_sign_ed25519_keypair(unsigned char *pk, unsigned char *sk);
extern int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen,
                               const unsigned char *m, unsigned long long mlen,
                               const unsigned char *sk);
extern int crypto_sign_open(unsigned char *m, unsigned long long *mlen,
                            const unsigned char *sm, unsigned long long smlen,
                            const unsigned char *pk);

static void GGGenerateKeypair(NSData **outPK, NSData **outSK) {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPK) *outPK = [NSData dataWithBytes:pk length:32];
    if (outSK) *outSK = [NSData dataWithBytes:sk length:64];
}

// Append a protobuf length-delimited field (wire type 2) to buf.
static void GGAppendBytesField(NSMutableData *buf, int fieldNum, const void *bytes, NSUInteger len) {
    uint64_t tag = ((uint64_t)fieldNum << 3) | 2;
    [SSBGabbyGrove appendVarint:tag toData:buf];
    [SSBGabbyGrove appendVarint:(uint64_t)len toData:buf];
    if (len > 0) [buf appendBytes:bytes length:len];
}

// Append a protobuf varint field (wire type 0) to buf.
static void GGAppendVarintField(NSMutableData *buf, int fieldNum, uint64_t value) {
    uint64_t tag = ((uint64_t)fieldNum << 3) | 0;
    [SSBGabbyGrove appendVarint:tag toData:buf];
    [SSBGabbyGrove appendVarint:value toData:buf];
}

// Build a minimal valid seq=1 GabbyGrove message signed with the given keypair.
// Fields included: 1 (author), 2 (sequence=1), 5 (contentHash), 6 (content), 8 (signature).
static NSData *GGBuildValidSeq1Message(NSData *pubKey, NSData *secretKey) {
    NSMutableData *payload = [NSMutableData data];

    // Field 1: author (32-byte Ed25519 pubkey)
    GGAppendBytesField(payload, 1, pubKey.bytes, 32);

    // Field 2: sequence = 1
    GGAppendVarintField(payload, 2, 1);

    // Field 5: contentHash (32 bytes, arbitrary for test)
    uint8_t contentHash[32];
    memset(contentHash, 0xCC, 32);
    GGAppendBytesField(payload, 5, contentHash, 32);

    // Field 6: content (some bytes)
    uint8_t content[] = {0x01, 0x02, 0x03};
    GGAppendBytesField(payload, 6, content, 3);

    // Field 7: is_end_of_feed = 0
    GGAppendVarintField(payload, 7, 0);

    // Sign fields 1-7 using Ed25519
    unsigned long long smLen = 64 + (unsigned long long)payload.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payload.bytes, (unsigned long long)payload.length,
                        (const unsigned char *)secretKey.bytes);

    // The first 64 bytes of sm are the signature
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    // Field 8: signature (64 bytes)
    GGAppendBytesField(payload, 8, sig.bytes, 64);

    return [payload copy];
}

@interface SSBGabbyGroveTests : XCTestCase
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, strong) NSData *secretKey;
@end

@implementation SSBGabbyGroveTests

- (void)setUp {
    [super setUp];
    GGGenerateKeypair(&_publicKey, &_secretKey);
}

#pragma mark - Varint Encoding

- (void)testAppendVarint_zero {
    NSMutableData *buf = [NSMutableData data];
    [SSBGabbyGrove appendVarint:0 toData:buf];
    XCTAssertEqual(buf.length, 1u);
    XCTAssertEqual(((const uint8_t *)buf.bytes)[0], 0x00);
}

- (void)testAppendVarint_smallValue {
    NSMutableData *buf = [NSMutableData data];
    [SSBGabbyGrove appendVarint:42 toData:buf];
    XCTAssertEqual(buf.length, 1u);
    XCTAssertEqual(((const uint8_t *)buf.bytes)[0], 42);
}

- (void)testAppendVarint_twoByteValue {
    // 128 requires 2 bytes: 0x80 0x01
    NSMutableData *buf = [NSMutableData data];
    [SSBGabbyGrove appendVarint:128 toData:buf];
    XCTAssertEqual(buf.length, 2u);
    const uint8_t *b = buf.bytes;
    XCTAssertEqual(b[0], 0x80);
    XCTAssertEqual(b[1], 0x01);
}

- (void)testAppendVarint_largeValue {
    NSMutableData *buf = [NSMutableData data];
    [SSBGabbyGrove appendVarint:300 toData:buf]; // 300 = 0xAC 0x02
    XCTAssertEqual(buf.length, 2u);
    const uint8_t *b = buf.bytes;
    XCTAssertEqual(b[0], 0xAC);
    XCTAssertEqual(b[1], 0x02);
}

- (void)testDecodeVarint_zero {
    uint8_t bytes[] = {0x00};
    NSUInteger offset = 0;
    uint64_t value = [SSBGabbyGrove decodeVarintFrom:bytes length:1 offset:&offset];
    XCTAssertEqual(value, 0u);
    XCTAssertEqual(offset, 1u);
}

- (void)testDecodeVarint_smallValue {
    uint8_t bytes[] = {42};
    NSUInteger offset = 0;
    uint64_t value = [SSBGabbyGrove decodeVarintFrom:bytes length:1 offset:&offset];
    XCTAssertEqual(value, 42u);
    XCTAssertEqual(offset, 1u);
}

- (void)testDecodeVarint_twoBytes {
    // 0x80 0x01 = 128
    uint8_t bytes[] = {0x80, 0x01};
    NSUInteger offset = 0;
    uint64_t value = [SSBGabbyGrove decodeVarintFrom:bytes length:2 offset:&offset];
    XCTAssertEqual(value, 128u);
    XCTAssertEqual(offset, 2u);
}

- (void)testDecodeVarint_roundTrip {
    for (uint64_t original in @[@0, @1, @127, @128, @300, @16383, @16384]) {
        NSMutableData *buf = [NSMutableData data];
        [SSBGabbyGrove appendVarint:original.unsignedLongLongValue toData:buf];
        NSUInteger offset = 0;
        uint64_t decoded = [SSBGabbyGrove decodeVarintFrom:buf.bytes
                                                    length:buf.length
                                                    offset:&offset];
        XCTAssertEqual(decoded, original.unsignedLongLongValue,
                       @"Round-trip failed for value %llu", original.unsignedLongLongValue);
        XCTAssertEqual(offset, buf.length, @"Offset should advance past entire varint");
    }
}

- (void)testDecodeVarint_truncated_returnsZeroAndDoesNotAdvance {
    // Partial varint: 0x80 requires another byte but none provided
    uint8_t bytes[] = {0x80};
    NSUInteger offset = 0;
    uint64_t value = [SSBGabbyGrove decodeVarintFrom:bytes length:1 offset:&offset];
    // Should return 0 and not advance offset (truncated)
    XCTAssertEqual(value, 0u);
    XCTAssertEqual(offset, 0u);
}

- (void)testDecodeVarint_offsetAdvancesCorrectly {
    // Two consecutive varints: [42, 128]
    NSMutableData *buf = [NSMutableData data];
    [SSBGabbyGrove appendVarint:42 toData:buf];
    [SSBGabbyGrove appendVarint:128 toData:buf];

    NSUInteger offset = 0;
    uint64_t v1 = [SSBGabbyGrove decodeVarintFrom:buf.bytes length:buf.length offset:&offset];
    XCTAssertEqual(v1, 42u);
    uint64_t v2 = [SSBGabbyGrove decodeVarintFrom:buf.bytes length:buf.length offset:&offset];
    XCTAssertEqual(v2, 128u);
    XCTAssertEqual(offset, buf.length);
}

#pragma mark - BLAKE2b-256

- (void)testBlake2b256_nilReturnsNil {
    // Passing nil data — method should handle gracefully
    NSData *result = [SSBGabbyGrove blake2b256:[NSData data]];
    XCTAssertNotNil(result); // empty data is valid; BLAKE2b-256 of empty is a known constant
}

- (void)testBlake2b256_emptyData {
    NSData *empty = [NSData data];
    NSData *result = [SSBGabbyGrove blake2b256:empty];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 32u);
}

- (void)testBlake2b256_knownInput {
    // BLAKE2b-256("") known constant per RFC 7693 test vectors
    uint8_t expected[32] = {
        0x0e,0x57,0x51,0xc0,0x26,0xe5,0x43,0xb2,
        0xe8,0xab,0x2e,0xb0,0x60,0x99,0xda,0xa1,
        0xd1,0xe5,0xdf,0x47,0x77,0x8f,0x77,0x87,
        0xfa,0xab,0x45,0xcd,0xf1,0x2f,0xe3,0xa8
    };
    NSData *result = [SSBGabbyGrove blake2b256:[NSData data]];
    NSData *expectedData = [NSData dataWithBytes:expected length:32];
    XCTAssertEqualObjects(result, expectedData);
}

- (void)testBlake2b256_deterministicForSameInput {
    NSData *input = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *r1 = [SSBGabbyGrove blake2b256:input];
    NSData *r2 = [SSBGabbyGrove blake2b256:input];
    XCTAssertEqualObjects(r1, r2);
}

- (void)testBlake2b256_differentInputsDifferentOutputs {
    NSData *a = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"world" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotEqualObjects([SSBGabbyGrove blake2b256:a], [SSBGabbyGrove blake2b256:b]);
}

#pragma mark - validateMessage: — invalid inputs

- (void)testValidateMessage_nil {
    XCTAssertFalse([SSBGabbyGrove validateMessage:nil]);
}

- (void)testValidateMessage_empty {
    XCTAssertFalse([SSBGabbyGrove validateMessage:[NSData data]]);
}

- (void)testValidateMessage_tooShort {
    NSData *tiny = [NSData dataWithBytes:"ab" length:2];
    XCTAssertFalse([SSBGabbyGrove validateMessage:tiny]);
}

- (void)testValidateMessage_truncatedProtobuf {
    // Provide a partial field tag with no content
    NSMutableData *partial = [NSMutableData data];
    GGAppendBytesField(partial, 1, NULL, 0); // author field with 0 length
    XCTAssertFalse([SSBGabbyGrove validateMessage:partial]);
}

- (void)testValidateMessage_missingSignature {
    // Build payload without field 8
    NSMutableData *payload = [NSMutableData data];
    GGAppendBytesField(payload, 1, self.publicKey.bytes, 32);
    GGAppendVarintField(payload, 2, 1);
    uint8_t contentHash[32] = {0};
    GGAppendBytesField(payload, 5, contentHash, 32);
    // No field 8
    XCTAssertFalse([SSBGabbyGrove validateMessage:payload]);
}

- (void)testValidateMessage_wrongSignature {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    // Flip the last byte (in the signature field)
    NSMutableData *tampered = [msg mutableCopy];
    uint8_t *bytes = tampered.mutableBytes;
    bytes[tampered.length - 1] ^= 0xFF;
    XCTAssertFalse([SSBGabbyGrove validateMessage:tampered]);
}

- (void)testValidateMessage_randomData {
    uint8_t random[100];
    for (int i = 0; i < 100; i++) random[i] = (uint8_t)(arc4random() & 0xFF);
    NSData *randomData = [NSData dataWithBytes:random length:100];
    XCTAssertFalse([SSBGabbyGrove validateMessage:randomData]);
}

#pragma mark - validateMessage: — valid message

- (void)testValidateMessage_validSeq1 {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    XCTAssertTrue([SSBGabbyGrove validateMessage:msg]);
}

- (void)testValidateMessage_validSeq1_differentKeypair {
    NSData *otherPK, *otherSK;
    GGGenerateKeypair(&otherPK, &otherSK);
    NSData *msg = GGBuildValidSeq1Message(otherPK, otherSK);
    XCTAssertTrue([SSBGabbyGrove validateMessage:msg]);
}

- (void)testValidateMessage_wrongAuthorKey {
    // Sign with secretKey but claim authorship via a different pubkey
    NSData *otherPK, *otherSK;
    GGGenerateKeypair(&otherPK, &otherSK);

    NSMutableData *payload = [NSMutableData data];
    GGAppendBytesField(payload, 1, otherPK.bytes, 32);  // different author
    GGAppendVarintField(payload, 2, 1);
    uint8_t contentHash[32] = {0};
    GGAppendBytesField(payload, 5, contentHash, 32);

    // Sign with self.secretKey (mismatch)
    unsigned long long smLen = 64 + (unsigned long long)payload.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payload.bytes, (unsigned long long)payload.length,
                        (const unsigned char *)self.secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);

    GGAppendBytesField(payload, 8, sig.bytes, 64);
    XCTAssertFalse([SSBGabbyGrove validateMessage:payload]);
}

// Build a seq=1 message with an extra unknown fixed-width field injected before the signature.
// wireType 1 = 64-bit fixed (byteCount=8), wireType 5 = 32-bit fixed (byteCount=4).
- (NSData *)buildSeq1MessageWithUnknownField:(int)fieldNumber
                                    wireType:(int)wireType
                                   byteCount:(NSUInteger)byteCount {
    NSMutableData *payload = [NSMutableData data];
    GGAppendBytesField(payload, 1, self.publicKey.bytes, 32);
    GGAppendVarintField(payload, 2, 1);
    uint8_t contentHash[32];
    memset(contentHash, 0xAB, 32);
    GGAppendBytesField(payload, 5, contentHash, 32);

    uint64_t tag = ((uint64_t)fieldNumber << 3) | wireType;
    [SSBGabbyGrove appendVarint:tag toData:payload];
    uint8_t fixedBytes[8] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE};
    [payload appendBytes:fixedBytes length:byteCount];

    unsigned long long smLen = 64 + (unsigned long long)payload.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, payload.bytes, (unsigned long long)payload.length,
                        (const unsigned char *)self.secretKey.bytes);
    NSData *sig = [NSData dataWithBytes:sm length:64];
    free(sm);
    GGAppendBytesField(payload, 8, sig.bytes, 64);
    return [payload copy];
}

- (void)testValidateMessage_unknownFixed64Field_isSkipped {
    // wire type 1 (64-bit fixed) before the signature should be skipped, not rejected
    NSData *msg = [self buildSeq1MessageWithUnknownField:99 wireType:1 byteCount:8];
    XCTAssertTrue([SSBGabbyGrove validateMessage:msg]);
}

- (void)testValidateMessage_unknownFixed32Field_isSkipped {
    // wire type 5 (32-bit fixed) before the signature should be skipped, not rejected
    NSData *msg = [self buildSeq1MessageWithUnknownField:100 wireType:5 byteCount:4];
    XCTAssertTrue([SSBGabbyGrove validateMessage:msg]);
}

#pragma mark - computeMessageKey:

- (void)testComputeMessageKey_nil {
    XCTAssertNil([SSBGabbyGrove computeMessageKey:nil]);
}

- (void)testComputeMessageKey_empty {
    XCTAssertNil([SSBGabbyGrove computeMessageKey:[NSData data]]);
}

- (void)testComputeMessageKey_validMessage {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSData *key = [SSBGabbyGrove computeMessageKey:msg];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
}

- (void)testComputeMessageKey_deterministic {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSData *k1 = [SSBGabbyGrove computeMessageKey:msg];
    NSData *k2 = [SSBGabbyGrove computeMessageKey:msg];
    XCTAssertEqualObjects(k1, k2);
}

- (void)testComputeMessageKey_differentMessagesHaveDifferentKeys {
    NSData *msg1 = GGBuildValidSeq1Message(self.publicKey, self.secretKey);

    NSData *otherPK, *otherSK;
    GGGenerateKeypair(&otherPK, &otherSK);
    NSData *msg2 = GGBuildValidSeq1Message(otherPK, otherSK);

    XCTAssertNotEqualObjects([SSBGabbyGrove computeMessageKey:msg1],
                             [SSBGabbyGrove computeMessageKey:msg2]);
}

#pragma mark - SSBFeedCodec Protocol Conformance

- (void)testFeedFormat {
    XCTAssertEqual([SSBGabbyGrove sharedCodec].feedFormat, SSBBFEFeedFormatGabbygroveV1);
}

- (void)testMessageFormat {
    XCTAssertEqual([SSBGabbyGrove sharedCodec].messageFormat, SSBBFEMessageFormatGabbygroveV1);
}

- (void)testVerifyMessageData_valid {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSError *error = nil;
    BOOL result = [[SSBGabbyGrove sharedCodec] verifyMessageData:msg error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testVerifyMessageData_invalid_setsError {
    NSData *badData = [@"not a gabbygrove message" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL result = [[SSBGabbyGrove sharedCodec] verifyMessageData:badData error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testComputeMessageKeyFromData_valid {
    NSData *msg = GGBuildValidSeq1Message(self.publicKey, self.secretKey);
    NSError *error = nil;
    NSData *key = [[SSBGabbyGrove sharedCodec] computeMessageKeyFromData:msg error:&error];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
    XCTAssertNil(error);
}

- (void)testComputeMessageKeyFromData_empty_setsError {
    NSError *error = nil;
    NSData *key = [[SSBGabbyGrove sharedCodec] computeMessageKeyFromData:[NSData data] error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

- (void)testSharedCodec_returnsSameInstance {
    id<SSBFeedCodec> a = [SSBGabbyGrove sharedCodec];
    id<SSBFeedCodec> b = [SSBGabbyGrove sharedCodec];
    XCTAssertEqual(a, b);
}

@end
