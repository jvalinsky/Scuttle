#import <XCTest/XCTest.h>
#import "SSBBFE.h"

@interface SSBBFETests : XCTestCase
@end

@implementation SSBBFETests

- (void)testFeedIDClassicEncoding {
    // Standard SSB feed ID with / and + (32 bytes base64 encoded)
    NSString *feedID = @"@6uS7fC1v5fS/yX3F5N2RjF4M/l6SjC1v5fS/yX3F5M0=.ed25519";
    NSData *bfe = [SSBBFE encodeFeedID:feedID format:SSBBFEFeedFormatClassic];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeFeed);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatClassic);
    
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    // Sigil should match the standard input exactly
    XCTAssertEqualObjects(sigil, feedID);
}

- (void)testMessageIDClassicEncoding {
    // Standard SSB message ID
    NSString *msgID = @"%7uS7fC1v5fS/yX3F5N2RjF4M/l6SjC1v5fS/yX3F5M0=.sha256";
    NSData *bfe = [SSBBFE encodeMessageID:msgID format:SSBBFEMessageFormatClassic];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeMessage);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatClassic);
    
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    // Sigil should match the standard input exactly
    XCTAssertEqualObjects(sigil, msgID);
}

- (void)testBendyButtFeedID {
    NSData *key = [[NSData alloc] initWithBase64EncodedString:@"6uS7fC1v5fS/yX3F5N2RjF4M/l6SjC1v5fS/yX3F5M0=" options:0];
    NSData *bfe = [SSBBFE encodeFeedID:key format:SSBBFEFeedFormatBendybuttV1];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeFeed);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatBendybuttV1);
    
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".bbfeed-v1"]);
}

- (void)testGenericString {
    NSString *testStr = @"hello world";
    NSData *bfe = [SSBBFE encodeGenericString:testStr];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeGeneric);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEGenericFormatString);
    
    id decoded = [SSBBFE decodeBFEData:bfe];
    XCTAssertEqualObjects(decoded, testStr);
}

- (void)testGenericBoolean {
    NSData *bfeTrue = [SSBBFE encodeBoolean:YES];
    XCTAssertEqualObjects([SSBBFE decodeBFEData:bfeTrue], @YES);
    
    NSData *bfeFalse = [SSBBFE encodeBoolean:NO];
    XCTAssertEqualObjects([SSBBFE decodeBFEData:bfeFalse], @NO);
}

- (void)testGenericNil {
    NSData *bfe = [SSBBFE encodeNil];
    XCTAssertEqualObjects([SSBBFE decodeBFEData:bfe], [NSNull null]);
}

- (void)testDetectMethods {
    NSData *bfe = [SSBBFE encodeNil];
    XCTAssertEqual([SSBBFE detectType:bfe], SSBBFETypeGeneric);
    XCTAssertEqual([SSBBFE detectFormat:bfe], SSBBFEGenericFormatNil);
}

- (void)testBase64URL {
    NSData *data = [@"hello+world/test==" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [SSBBFE base64URLEncodedStringFromData:data];
    XCTAssertFalse([encoded containsString:@"+"]);
    XCTAssertFalse([encoded containsString:@"/"]);
    XCTAssertFalse([encoded containsString:@"="]);

    NSData *decoded = [SSBBFE dataFromBase64URLEncodedString:encoded];
    XCTAssertEqualObjects(decoded, data);
}

@end

#pragma mark - Extended SSBBFE Tests

// 32-byte all-zero key
static NSData *BFEMakeKey32(void) {
    uint8_t bytes[32] = {0xAB};
    return [NSData dataWithBytes:bytes length:32];
}

@interface SSBBFEExtendedTests : XCTestCase
@end

@implementation SSBBFEExtendedTests

#pragma mark - encodeFeedID: string variants

- (void)testEncodeFeedID_stringWithoutSigil_decodes {
    // String without @ prefix goes to the else branch (line 24)
    NSData *key = BFEMakeKey32();
    NSString *b64 = [key base64EncodedStringWithOptions:0];
    NSData *bfe = [SSBBFE encodeFeedID:b64 format:SSBBFEFeedFormatClassic];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34U);
}

- (void)testEncodeFeedID_atWithoutSuffix_decodes {
    // @prefix but no .ed25519 suffix → base64Part from line 17
    NSData *key = BFEMakeKey32();
    NSString *b64 = [key base64EncodedStringWithOptions:0];
    NSString *feedStr = [NSString stringWithFormat:@"@%@", b64];
    NSData *bfe = [SSBBFE encodeFeedID:feedStr format:SSBBFEFeedFormatBendybuttV1];
    XCTAssertNotNil(bfe);
}

- (void)testEncodeFeedID_wrongKeyLength_returnsNil {
    uint8_t _k1[] = {1,2,3}; NSData *shortKey = [NSData dataWithBytes:_k1 length:3];
    XCTAssertNil([SSBBFE encodeFeedID:shortKey format:SSBBFEFeedFormatClassic]);
}

- (void)testEncodeFeedID_nilInput_returnsNil {
    XCTAssertNil([SSBBFE encodeFeedID:nil format:SSBBFEFeedFormatClassic]);
}

- (void)testEncodeFeedID_gabbygroveV1 {
    NSData *key = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeFeedID:key format:SSBBFEFeedFormatGabbygroveV1];
    XCTAssertNotNil(bfe);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".ggfeed-v1"]);
}

- (void)testEncodeFeedID_bamboo {
    NSData *key = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeFeedID:key format:SSBBFEFeedFormatBamboo];
    XCTAssertNotNil(bfe);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".bamboo"]);
}

- (void)testEncodeFeedID_buttwooV1 {
    NSData *key = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeFeedID:key format:SSBBFEFeedFormatButtwooV1];
    XCTAssertNotNil(bfe);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".buttwoo-v1"]);
}

- (void)testEncodeFeedID_indexedV1 {
    NSData *key = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeFeedID:key format:SSBBFEFeedFormatIndexedV1];
    XCTAssertNotNil(bfe);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".indexedfeed-v1"]);
}

#pragma mark - encodeMessageID: variants

- (void)testEncodeMessageID_cloakedSuffix {
    NSData *hash = BFEMakeKey32();
    NSString *b64 = [hash base64EncodedStringWithOptions:0];
    NSString *msgStr = [NSString stringWithFormat:@"%%%@.cloaked", b64];
    NSData *bfe = [SSBBFE encodeMessageID:msgStr format:SSBBFEMessageFormatCloaked];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatCloaked);
}

- (void)testEncodeMessageID_withoutPercentPrefix {
    NSData *hash = BFEMakeKey32();
    NSString *b64 = [hash base64EncodedStringWithOptions:0];
    NSData *bfe = [SSBBFE encodeMessageID:b64 format:SSBBFEMessageFormatClassic];
    XCTAssertNotNil(bfe);
}

- (void)testEncodeMessageID_bambooFormat_64bytes {
    uint8_t hashBytes[64] = {0xCC};
    NSData *hash64 = [NSData dataWithBytes:hashBytes length:64];
    NSData *bfe = [SSBBFE encodeMessageID:hash64 format:SSBBFEMessageFormatBamboo];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 66U);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".bamboo"]);
}

- (void)testEncodeMessageID_wrongLength_returnsNil {
    uint8_t _k2[] = {1,2,3}; NSData *shortData = [NSData dataWithBytes:_k2 length:3];
    XCTAssertNil([SSBBFE encodeMessageID:shortData format:SSBBFEMessageFormatClassic]);
}

- (void)testEncodeMessageID_gabbygroveV1 {
    NSData *hash = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeMessageID:hash format:SSBBFEMessageFormatGabbygroveV1];
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".ggmsg-v1"]);
}

- (void)testEncodeMessageID_bendybuttV1 {
    NSData *hash = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeMessageID:hash format:SSBBFEMessageFormatBendybuttV1];
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".bbmsg-v1"]);
}

- (void)testEncodeMessageID_buttwooV1 {
    NSData *hash = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeMessageID:hash format:SSBBFEMessageFormatButtwooV1];
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".buttwoo-v1"]);
}

- (void)testEncodeMessageID_indexedV1 {
    NSData *hash = BFEMakeKey32();
    NSData *bfe = [SSBBFE encodeMessageID:hash format:SSBBFEMessageFormatIndexedV1];
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertTrue([sigil hasSuffix:@".indexedmsg-v1"]);
}

#pragma mark - encodeBlobID:

- (void)testEncodeBlobID_withAmpersandString {
    NSData *hash = BFEMakeKey32();
    NSString *b64 = [hash base64EncodedStringWithOptions:0];
    NSString *blobStr = [NSString stringWithFormat:@"&%@.sha256", b64];
    NSData *bfe = [SSBBFE encodeBlobID:blobStr];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeBlob);
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertEqualObjects(sigil, blobStr);
}

- (void)testEncodeBlobID_withData {
    NSData *bfe = [SSBBFE encodeBlobID:BFEMakeKey32()];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34U);
}

- (void)testEncodeBlobID_withAmpersandNoSuffix {
    NSData *hash = BFEMakeKey32();
    NSString *b64 = [hash base64EncodedStringWithOptions:0];
    NSString *blobStr = [NSString stringWithFormat:@"&%@", b64];
    NSData *bfe = [SSBBFE encodeBlobID:blobStr];
    XCTAssertNotNil(bfe);
}

- (void)testEncodeBlobID_wrongLength_returnsNil {
    uint8_t _k3[] = {1,2}; NSData *shortData = [NSData dataWithBytes:_k3 length:2];
    XCTAssertNil([SSBBFE encodeBlobID:shortData]);
}

#pragma mark - encodeEncryptionKey:

- (void)testEncodeEncryptionKey_valid {
    NSData *bfe = [SSBBFE encodeEncryptionKey:BFEMakeKey32() format:SSBBFEEncryptionKeyFormatBox2DmDh];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeEncryptionKey);
    XCTAssertEqual(bfe.length, 34U);
}

- (void)testEncodeEncryptionKey_wrongLength_returnsNil {
    uint8_t _k4[] = {1,2,3}; NSData *shortData = [NSData dataWithBytes:_k4 length:3];
    XCTAssertNil([SSBBFE encodeEncryptionKey:shortData format:SSBBFEEncryptionKeyFormatBox2DmDh]);
    XCTAssertNil([SSBBFE encodeEncryptionKey:nil format:SSBBFEEncryptionKeyFormatBox2DmDh]);
}

#pragma mark - encodeSignature:

- (void)testEncodeSignature_valid {
    uint8_t sigBytes[64] = {0xDD};
    NSData *sig = [NSData dataWithBytes:sigBytes length:64];
    NSData *bfe = [SSBBFE encodeSignature:sig];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeSignature);
    XCTAssertEqual(bfe.length, 66U);
}

- (void)testEncodeSignature_wrongLength_returnsNil {
    NSData *shortData = BFEMakeKey32(); // 32 bytes, not 64
    XCTAssertNil([SSBBFE encodeSignature:shortData]);
    XCTAssertNil([SSBBFE encodeSignature:nil]);
}

#pragma mark - encodeEncrypted:

- (void)testEncodeEncrypted_valid {
    NSData *ct = [@"ciphertext" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bfe = [SSBBFE encodeEncrypted:ct format:SSBBFEEncryptedFormatBox1];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeEncrypted);
}

- (void)testEncodeEncrypted_empty_returnsNil {
    XCTAssertNil([SSBBFE encodeEncrypted:[NSData data] format:SSBBFEEncryptedFormatBox1]);
    XCTAssertNil([SSBBFE encodeEncrypted:nil format:SSBBFEEncryptedFormatBox1]);
}

#pragma mark - encodeGenericBytes:

- (void)testEncodeGenericBytes_valid {
    NSData *bytes = [@"raw" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bfe = [SSBBFE encodeGenericBytes:bytes];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEGenericFormatBytes);
    id decoded = [SSBBFE decodeBFEData:bfe];
    XCTAssertEqualObjects(decoded, bytes);
}

- (void)testEncodeGenericBytes_nil_returnsNil {
    XCTAssertNil([SSBBFE encodeGenericBytes:nil]);
}

- (void)testEncodeGenericString_nil_returnsNil {
    XCTAssertNil([SSBBFE encodeGenericString:nil]);
}

#pragma mark - encodeIdentityPoBox: / encodeIdentityGroup:

- (void)testEncodeIdentityPoBox_valid {
    NSData *bfe = [SSBBFE encodeIdentityPoBox:BFEMakeKey32()];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeIdentity);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEIdentityFormatPoBox);
    id decoded = [SSBBFE decodeBFEData:bfe];
    XCTAssertNotNil(decoded);
}

- (void)testEncodeIdentityPoBox_wrongLength_returnsNil {
    uint8_t _k5[] = {1}; NSData *shortData = [NSData dataWithBytes:_k5 length:1];
    XCTAssertNil([SSBBFE encodeIdentityPoBox:shortData]);
    XCTAssertNil([SSBBFE encodeIdentityPoBox:nil]);
}

- (void)testEncodeIdentityGroup_valid {
    NSData *bfe = [SSBBFE encodeIdentityGroup:BFEMakeKey32()];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEIdentityFormatGroup);
}

- (void)testEncodeIdentityGroup_wrongLength_returnsNil {
    XCTAssertNil([SSBBFE encodeIdentityGroup:nil]);
}

#pragma mark - sigilStringFromBFE: edge cases

- (void)testSigilStringFromBFE_nil_returnsNil {
    XCTAssertNil([SSBBFE sigilStringFromBFE:nil]);
}

- (void)testSigilStringFromBFE_tooShort_returnsNil {
    uint8_t _k6[] = {0x00}; NSData *oneByte = [NSData dataWithBytes:_k6 length:1];
    XCTAssertNil([SSBBFE sigilStringFromBFE:oneByte]);
}

- (void)testSigilStringFromBFE_unknownType_returnsBase64 {
    // Unknown type byte (0xFF) → default case returns base64
    NSData *key = BFEMakeKey32();
    NSMutableData *bfe = [NSMutableData data];
    uint8_t typeByte = 0xFF, fmtByte = 0x00;
    [bfe appendBytes:&typeByte length:1];
    [bfe appendBytes:&fmtByte length:1];
    [bfe appendData:key];
    NSString *result = [SSBBFE sigilStringFromBFE:bfe];
    XCTAssertNotNil(result);
}

#pragma mark - bfeDataFromSigilString:

- (void)testBfeDataFromSigilString_feedClassic {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.ed25519", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeFeed);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatClassic);
}

- (void)testBfeDataFromSigilString_feedGabbygrove {
    NSData *key = BFEMakeKey32();
    NSString *urlSafe = [[key base64EncodedStringWithOptions:0]
                         stringByReplacingOccurrencesOfString:@"=" withString:@""];
    NSString *sigil = [NSString stringWithFormat:@"@%@.ggfeed-v1", urlSafe];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatGabbygroveV1);
}

- (void)testBfeDataFromSigilString_feedBamboo {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.bamboo", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatBamboo);
}

- (void)testBfeDataFromSigilString_feedBendybutt {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.bbfeed-v1", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatBendybuttV1);
}

- (void)testBfeDataFromSigilString_feedButtwoo {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.buttwoo-v1", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatButtwooV1);
}

- (void)testBfeDataFromSigilString_feedIndexed {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.indexedfeed-v1", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatIndexedV1);
}

- (void)testBfeDataFromSigilString_feedUnknownSuffix {
    NSData *key = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"@%@.unknown", [key base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], 0); // Unknown → format 0
}

- (void)testBfeDataFromSigilString_messageClassic {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.sha256", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeMessage);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatClassic);
}

- (void)testBfeDataFromSigilString_messageGabbygrove {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.ggmsg-v1", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatGabbygroveV1);
}

- (void)testBfeDataFromSigilString_messageCloaked {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.cloaked", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatCloaked);
}

- (void)testBfeDataFromSigilString_messageBamboo {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.bamboo", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatBamboo);
}

- (void)testBfeDataFromSigilString_messageBendybutt {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.bbmsg-v1", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatBendybuttV1);
}

- (void)testBfeDataFromSigilString_messageButtwoo {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.buttwoo-v1", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatButtwooV1);
}

- (void)testBfeDataFromSigilString_messageIndexed {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.indexedmsg-v1", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatIndexedV1);
}

- (void)testBfeDataFromSigilString_messageUnknownSuffix {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"%%%@.unknown", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], 0);
}

- (void)testBfeDataFromSigilString_blob {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"&%@.sha256", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeBlob);
}

- (void)testBfeDataFromSigilString_nil_returnsNil {
    XCTAssertNil([SSBBFE bfeDataFromSigilString:nil]);
}

- (void)testBfeDataFromSigilString_tooShort_returnsNil {
    XCTAssertNil([SSBBFE bfeDataFromSigilString:@"@"]);
}

- (void)testBfeDataFromSigilString_unknownSigil_returnsNil {
    NSData *hash = BFEMakeKey32();
    NSString *sigil = [NSString stringWithFormat:@"#%@.sha256", [hash base64EncodedStringWithOptions:0]];
    NSData *bfe = [SSBBFE bfeDataFromSigilString:sigil];
    XCTAssertNil(bfe);
}

#pragma mark - decode:type:format:

- (void)testDecodeWithOutParams_nil_returnsNil {
    SSBBFEType t;
    NSInteger f;
    XCTAssertNil([SSBBFE decode:nil type:&t format:&f]);
}

- (void)testDecodeWithOutParams_setsTypeAndFormat {
    NSData *bfe = [SSBBFE encodeNil];
    SSBBFEType t;
    NSInteger f;
    id result = [SSBBFE decode:bfe type:&t format:&f];
    XCTAssertEqualObjects(result, [NSNull null]);
    XCTAssertEqual(t, SSBBFETypeGeneric);
    XCTAssertEqual(f, SSBBFEGenericFormatNil);
}

- (void)testDecodeWithOutParams_booleanZeroLength_returnsNo {
    // Boolean with no data byte after type/format → returns @NO
    NSMutableData *bfe = [NSMutableData data];
    uint8_t t = (uint8_t)SSBBFETypeGeneric;
    uint8_t f = (uint8_t)SSBBFEGenericFormatBoolean;
    [bfe appendBytes:&t length:1];
    [bfe appendBytes:&f length:1];
    // no data byte
    id result = [SSBBFE decodeBFEData:bfe];
    XCTAssertEqualObjects(result, @NO);
}

#pragma mark - detectType / detectFormat edge cases

- (void)testDetectType_nil_returnsNegative {
    SSBBFEType t = [SSBBFE detectType:nil];
    XCTAssertEqual(t, (SSBBFEType)-1);
}

- (void)testDetectFormat_nil_returnsNegative {
    XCTAssertEqual([SSBBFE detectFormat:nil], -1);
}

- (void)testDetectFormat_oneByte_returnsNegative {
    uint8_t _k7[] = {0x01}; NSData *one = [NSData dataWithBytes:_k7 length:1];
    XCTAssertEqual([SSBBFE detectFormat:one], -1);
}

#pragma mark - base64 edge cases

- (void)testBase64URLEncoded_nil_returnsNil {
    XCTAssertNil([SSBBFE base64URLEncodedStringFromData:nil]);
}

- (void)testDataFromBase64URLEncoded_nil_returnsNil {
    XCTAssertNil([SSBBFE dataFromBase64URLEncodedString:nil]);
}

- (void)testDataFromBase64URLEncoded_empty_returnsNil {
    XCTAssertNil([SSBBFE dataFromBase64URLEncodedString:@""]);
}

- (void)testDataFromBase64URLEncoded_standardBase64Fallback {
    // Input with + and = (standard base64, not URL-safe) — triggers fallback decode on line 563
    NSData *original = BFEMakeKey32();
    NSString *standard = [original base64EncodedStringWithOptions:0];
    // First pass will convert + to - and / to _ then try to decode
    // In this case it should still decode correctly
    NSData *decoded = [SSBBFE dataFromBase64URLEncodedString:standard];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.length, 32U);
}

@end
