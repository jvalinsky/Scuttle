#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBamboo.h>

// TweetNaCl functions linked via SSBNetwork.framework.
extern int crypto_sign_ed25519_keypair(unsigned char *pk, unsigned char *sk);
extern int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen,
                               const unsigned char *m, unsigned long long mlen,
                               const unsigned char *sk);
#define BAMBOO_SIG_BYTES 64

static void BAMGenerateKeypair(NSData **outPK, NSData **outSK) {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    if (outPK) *outPK = [NSData dataWithBytes:pk length:32];
    if (outSK) *outSK = [NSData dataWithBytes:sk length:64];
}

// Bamboo seq=1 entry layout:
//   [0-31]   author (32 bytes)
//   [32-63]  log_id (32 bytes)
//   [64]     is_end_of_log (1 byte)
//   [65-72]  seq_number (8 bytes, big-endian uint64 = 1)
//   [73-104] payload_hash (32 bytes)
//   [105-112] payload_size (8 bytes, big-endian uint64)
//   [113-176] signature (64 bytes, signs bytes 0-112)
// Total: 177 bytes
static NSData *BAMBuildValidSeq1Entry(NSData *pubKey, NSData *secretKey) {
    NSMutableData *entry = [NSMutableData dataWithLength:177];
    uint8_t *bytes = entry.mutableBytes;

    // author (bytes 0-31)
    memcpy(bytes + 0, pubKey.bytes, 32);

    // log_id (bytes 32-63): fixed non-zero value for tests
    memset(bytes + 32, 0xAB, 32);

    // is_end_of_log (byte 64): 0 = not end
    bytes[64] = 0;

    // seq_number (bytes 65-72): 1, big-endian
    uint64_t seq = CFSwapInt64HostToBig(1);
    memcpy(bytes + 65, &seq, 8);

    // payload_hash (bytes 73-104): BLAKE2b-256 of "test payload"
    NSData *payloadData = [@"test payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payloadHash = [SSBBamboo hashData:payloadData];
    memcpy(bytes + 73, payloadHash.bytes, 32);

    // payload_size (bytes 105-112): size of "test payload", big-endian
    uint64_t payloadSize = CFSwapInt64HostToBig((uint64_t)payloadData.length);
    memcpy(bytes + 105, &payloadSize, 8);

    // Sign bytes 0-112 (the pre-signature portion)
    NSData *signedPart = [entry subdataWithRange:NSMakeRange(0, 113)];

    unsigned long long smLen = BAMBOO_SIG_BYTES + (unsigned long long)signedPart.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, signedPart.bytes, (unsigned long long)signedPart.length,
                        (const unsigned char *)secretKey.bytes);

    // First 64 bytes of sm are the Ed25519 signature
    memcpy(bytes + 113, sm, BAMBOO_SIG_BYTES);
    free(sm);

    return entry;
}

@interface SSBBambooTests : XCTestCase
@property (nonatomic, strong) NSData *publicKey;
@property (nonatomic, strong) NSData *secretKey;
@end

@implementation SSBBambooTests

- (void)setUp {
    [super setUp];
    BAMGenerateKeypair(&_publicKey, &_secretKey);
}

#pragma mark - lipmaaSequenceFor:

- (void)testLipmaa_seq1_returns1 {
    // seq <= 1 is a special case, returns 1
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:1], 1);
}

- (void)testLipmaa_seq2_returns1 {
    // 2 - largest(pow3 < 2) = 2 - 1 = 1
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:2], 1);
}

- (void)testLipmaa_seq3_returns2 {
    // 3 - 1 = 2 (pow3 strictly < 3 is 1)
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:3], 2);
}

- (void)testLipmaa_seq4_returns1 {
    // 4 - 3 = 1 (pow3 strictly < 4 is 3)
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:4], 1);
}

- (void)testLipmaa_seq5_returns2 {
    // 5 - 3 = 2 (pow3 strictly < 5 is 3)
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:5], 2);
}

- (void)testLipmaa_seq9_returns6 {
    // pow3 strictly < 9 is 3. 9 - 3 = 6
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:9], 6);
}

- (void)testLipmaa_seq10_returns1 {
    // pow3 strictly < 10 is 9. 10 - 9 = 1
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:10], 1);
}

- (void)testLipmaa_seq27_returns18 {
    // pow3 strictly < 27 is 9. 27 - 9 = 18
    XCTAssertEqual([SSBBamboo lipmaaSequenceFor:27], 18);
}

- (void)testLipmaa_positiveForAll {
    // All lipmaa values should be >= 1 and < seq
    for (NSInteger seq = 1; seq <= 100; seq++) {
        NSInteger lipmaa = [SSBBamboo lipmaaSequenceFor:seq];
        XCTAssertGreaterThanOrEqual(lipmaa, 1, @"lipmaa(%ld) should be >= 1", (long)seq);
        XCTAssertLessThanOrEqual(lipmaa, seq, @"lipmaa(%ld) should be <= seq", (long)seq);
    }
}

#pragma mark - hashData:

- (void)testHashData_nil {
    // nil returns nil
    XCTAssertNil([SSBBamboo hashData:nil]);
}

- (void)testHashData_emptyData_returns32Bytes {
    NSData *result = [SSBBamboo hashData:[NSData data]];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 32u);
}

- (void)testHashData_knownBLAKE2b256 {
    // BLAKE2b-256("") known constant per RFC 7693 test vectors
    uint8_t expected[32] = {
        0x0e,0x57,0x51,0xc0,0x26,0xe5,0x43,0xb2,
        0xe8,0xab,0x2e,0xb0,0x60,0x99,0xda,0xa1,
        0xd1,0xe5,0xdf,0x47,0x77,0x8f,0x77,0x87,
        0xfa,0xab,0x45,0xcd,0xf1,0x2f,0xe3,0xa8
    };
    NSData *result = [SSBBamboo hashData:[NSData data]];
    XCTAssertEqualObjects(result, [NSData dataWithBytes:expected length:32]);
}

- (void)testHashData_deterministic {
    NSData *input = [@"deterministic" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects([SSBBamboo hashData:input], [SSBBamboo hashData:input]);
}

- (void)testHashData_differentInputsDifferentHashes {
    NSData *a = [@"a" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"b" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotEqualObjects([SSBBamboo hashData:a], [SSBBamboo hashData:b]);
}

#pragma mark - validateEntry: — invalid inputs

- (void)testValidateEntry_nil {
    XCTAssertFalse([SSBBamboo validateEntry:nil]);
}

- (void)testValidateEntry_empty {
    XCTAssertFalse([SSBBamboo validateEntry:[NSData data]]);
}

- (void)testValidateEntry_tooShort {
    // Minimum seq=1 is 177 bytes; test with 176
    NSData *short_ = [NSData dataWithLength:176];
    XCTAssertFalse([SSBBamboo validateEntry:short_]);
}

- (void)testValidateEntry_minimumSize_allZeros {
    // 177 zero bytes is structurally present but invalid (seq=0)
    NSData *zeros = [NSData dataWithLength:177];
    XCTAssertFalse([SSBBamboo validateEntry:zeros]);
}

- (void)testValidateEntry_invalidIsEndByte {
    NSData *valid = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSMutableData *tampered = [valid mutableCopy];
    ((uint8_t *)tampered.mutableBytes)[64] = 0x05; // Invalid: only 0 or 1 allowed
    XCTAssertFalse([SSBBamboo validateEntry:tampered]);
}

- (void)testValidateEntry_badSignature {
    NSData *valid = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSMutableData *tampered = [valid mutableCopy];
    // Flip a byte in the signature portion (bytes 113-176)
    ((uint8_t *)tampered.mutableBytes)[150] ^= 0xFF;
    XCTAssertFalse([SSBBamboo validateEntry:tampered]);
}

- (void)testValidateEntry_tamperedPayloadHash {
    NSData *valid = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSMutableData *tampered = [valid mutableCopy];
    // Flip a byte in the payload_hash portion (bytes 73-104)
    ((uint8_t *)tampered.mutableBytes)[80] ^= 0xFF;
    XCTAssertFalse([SSBBamboo validateEntry:tampered]);
}

- (void)testValidateEntry_tamperedAuthor {
    NSData *valid = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSMutableData *tampered = [valid mutableCopy];
    // Flip a byte in the author portion (bytes 0-31)
    ((uint8_t *)tampered.mutableBytes)[0] ^= 0xFF;
    XCTAssertFalse([SSBBamboo validateEntry:tampered]);
}

#pragma mark - validateEntry: — valid entry

- (void)testValidateEntry_validSeq1 {
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    XCTAssertTrue([SSBBamboo validateEntry:entry]);
}

- (void)testValidateEntry_validSeq1_differentKeypair {
    NSData *otherPK, *otherSK;
    BAMGenerateKeypair(&otherPK, &otherSK);
    NSData *entry = BAMBuildValidSeq1Entry(otherPK, otherSK);
    XCTAssertTrue([SSBBamboo validateEntry:entry]);
}

- (void)testValidateEntry_isEnd1_valid {
    // is_end_of_log = 1 is valid
    NSMutableData *entry = [BAMBuildValidSeq1Entry(self.publicKey, self.secretKey) mutableCopy];
    // We need to rebuild with is_end=1 to get a valid signature
    uint8_t *bytes = entry.mutableBytes;
    bytes[64] = 1;

    // Re-sign since we changed the payload
    NSData *newSignedPart = [entry subdataWithRange:NSMakeRange(0, 113)];
    unsigned long long smLen = BAMBOO_SIG_BYTES + (unsigned long long)newSignedPart.length;
    uint8_t *sm = (uint8_t *)malloc((size_t)smLen);
    unsigned long long actualSmLen = 0;
    crypto_sign_ed25519(sm, &actualSmLen, newSignedPart.bytes, (unsigned long long)newSignedPart.length,
                        (const unsigned char *)self.secretKey.bytes);
    memcpy(bytes + 113, sm, BAMBOO_SIG_BYTES);
    free(sm);

    XCTAssertTrue([SSBBamboo validateEntry:entry]);
}

#pragma mark - computeEntryID:

- (void)testComputeEntryID_nil {
    XCTAssertNil([SSBBamboo computeEntryID:nil]);
}

- (void)testComputeEntryID_empty {
    XCTAssertNil([SSBBamboo computeEntryID:[NSData data]]);
}

- (void)testComputeEntryID_tooShort {
    XCTAssertNil([SSBBamboo computeEntryID:[NSData dataWithLength:176]]);
}

- (void)testComputeEntryID_validEntry_returns32Bytes {
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSData *entryID = [SSBBamboo computeEntryID:entry];
    XCTAssertNotNil(entryID);
    // Entry ID = BLAKE2b-256(full entry bytes) = 32 bytes
    XCTAssertEqual(entryID.length, 32u);
}

- (void)testComputeEntryID_deterministic {
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSData *id1 = [SSBBamboo computeEntryID:entry];
    NSData *id2 = [SSBBamboo computeEntryID:entry];
    XCTAssertEqualObjects(id1, id2);
}

- (void)testComputeEntryID_differentEntriesHaveDifferentIDs {
    NSData *e1 = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);

    NSData *otherPK, *otherSK;
    BAMGenerateKeypair(&otherPK, &otherSK);
    NSData *e2 = BAMBuildValidSeq1Entry(otherPK, otherSK);

    XCTAssertNotEqualObjects([SSBBamboo computeEntryID:e1], [SSBBamboo computeEntryID:e2]);
}

- (void)testComputeEntryID_structure {
    // Entry ID = BLAKE2b-256(full entry bytes)
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSData *entryID = [SSBBamboo computeEntryID:entry];
    NSData *expectedHash = [SSBBamboo hashData:entry];
    XCTAssertEqualObjects(entryID, expectedHash);
}

#pragma mark - SSBFeedCodec Protocol Conformance

- (void)testFeedFormat {
    XCTAssertEqual([SSBBamboo sharedCodec].feedFormat, SSBBFEFeedFormatBamboo);
}

- (void)testMessageFormat {
    XCTAssertEqual([SSBBamboo sharedCodec].messageFormat, SSBBFEMessageFormatBamboo);
}

- (void)testVerifyMessageData_valid {
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSError *error = nil;
    BOOL result = [[SSBBamboo sharedCodec] verifyMessageData:entry error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testVerifyMessageData_invalid_setsError {
    NSData *badData = [@"not a bamboo entry" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL result = [[SSBBamboo sharedCodec] verifyMessageData:badData error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testComputeMessageKeyFromData_valid {
    NSData *entry = BAMBuildValidSeq1Entry(self.publicKey, self.secretKey);
    NSError *error = nil;
    NSData *key = [[SSBBamboo sharedCodec] computeMessageKeyFromData:entry error:&error];
    XCTAssertNotNil(key);
    XCTAssertEqual(key.length, 32u);
    XCTAssertNil(error);
}

- (void)testComputeMessageKeyFromData_invalid_setsError {
    NSData *badData = [NSData data];
    NSError *error = nil;
    NSData *key = [[SSBBamboo sharedCodec] computeMessageKeyFromData:badData error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

- (void)testSharedCodec_returnsSameInstance {
    id<SSBFeedCodec> a = [SSBBamboo sharedCodec];
    id<SSBFeedCodec> b = [SSBBamboo sharedCodec];
    XCTAssertEqual(a, b);
}

@end
