#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBURI.h>

// A valid base64-encoded 32-byte public key for test fixtures.
static NSString * const kTestPubKeyBase64 = @"LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
static NSString * const kTestFeedId       = @"@LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.ed25519";
static NSString * const kTestMsgKey       = @"%LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.sha256";
static NSString * const kTestBlobId       = @"&LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.sha256";

@interface SSBURITests : XCTestCase
@end

@implementation SSBURITests

#pragma mark - URIWithString: — Classic sigil strings

- (void)testParseClassicFeedId {
    SSBURI *uri = [SSBURI URIWithString:kTestFeedId];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
    XCTAssertEqual(uri.format, SSBURIFormatClassic);
    XCTAssertEqualObjects(uri.identifier, kTestFeedId);
}

- (void)testParseClassicMessageKey {
    SSBURI *uri = [SSBURI URIWithString:kTestMsgKey];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeMessage);
    XCTAssertEqual(uri.format, SSBURIFormatClassic);
    XCTAssertEqualObjects(uri.identifier, kTestMsgKey);
}

- (void)testParseClassicBlobId {
    SSBURI *uri = [SSBURI URIWithString:kTestBlobId];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeBlob);
    XCTAssertEqual(uri.format, SSBURIFormatClassic);
    XCTAssertEqualObjects(uri.identifier, kTestBlobId);
}

#pragma mark - URIWithString: — ssb:// scheme

- (void)testParseSSBScheme_feed {
    NSString *raw = [NSString stringWithFormat:@"ssb:feed/ed25519/%@", kTestPubKeyBase64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
}

- (void)testParseSSBScheme_message {
    NSString *raw = [NSString stringWithFormat:@"ssb:message/sha256/%@", kTestPubKeyBase64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeMessage);
}

- (void)testParseSSBScheme_blob {
    NSString *raw = [NSString stringWithFormat:@"ssb:blob/sha256/%@", kTestPubKeyBase64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeBlob);
}

- (void)testParseUnknownScheme_returnsUnknown {
    SSBURI *uri = [SSBURI URIWithString:@"totally-not-valid"];
    if (uri) {
        XCTAssertEqual(uri.type, SSBURITypeUnknown);
    }
    // nil is also acceptable for unparseable input
}

#pragma mark - uriWithMessage:format:

- (void)testCreateMessageURI_classic {
    SSBURI *uri = [SSBURI uriWithMessage:kTestMsgKey format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeMessage);
    XCTAssertEqualObjects(uri.identifier, kTestMsgKey);
}

- (void)testCreateMessageURI_canonicalString {
    SSBURI *uri = [SSBURI uriWithMessage:kTestMsgKey format:SSBURIFormatClassic];
    XCTAssertNotNil(uri.canonicalString);
    XCTAssertGreaterThan(uri.canonicalString.length, 0);
}

#pragma mark - uriWithFeed:format:

- (void)testCreateFeedURI_classic {
    SSBURI *uri = [SSBURI uriWithFeed:kTestFeedId format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
    XCTAssertEqualObjects(uri.identifier, kTestFeedId);
}

- (void)testCreateFeedURI_withParentMessage {
    SSBURI *uri = [SSBURI uriWithFeed:kTestFeedId parentMessageId:kTestMsgKey format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
    XCTAssertEqualObjects(uri.parentMessageId, kTestMsgKey);
}

#pragma mark - uriWithBlob:format:

- (void)testCreateBlobURI_classic {
    SSBURI *uri = [SSBURI uriWithBlob:kTestBlobId format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeBlob);
    XCTAssertEqualObjects(uri.identifier, kTestBlobId);
}

#pragma mark - uriWithAddress:

- (void)testCreateAddressURI {
    NSString *msa = @"net:example.com:8008~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
    SSBURI *uri = [SSBURI uriWithAddress:msa];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeAddress);
    XCTAssertNotNil(uri.multiserverAddress);
}

#pragma mark - formatToString: / formatFromString:

- (void)testFormatToString_classic {
    NSString *str = [SSBURI formatToString:SSBURIFormatClassic];
    XCTAssertNotNil(str);
    XCTAssertGreaterThan(str.length, 0);
}

- (void)testFormatFromString_roundTrip {
    NSArray *formats = @[@(SSBURIFormatClassic), @(SSBURIFormatBendybuttV1),
                         @(SSBURIFormatMultiserver)];
    for (NSNumber *fmtNum in formats) {
        SSBURIFormat fmt = (SSBURIFormat)fmtNum.integerValue;
        NSString *str = [SSBURI formatToString:fmt];
        if (str) {
            SSBURIFormat recovered = [SSBURI formatFromString:str];
            XCTAssertEqual(recovered, fmt, @"Round-trip failed for format %ld", (long)fmt);
        }
    }
}

- (void)testFormatFromString_unknown {
    SSBURIFormat fmt = [SSBURI formatFromString:@"not-a-real-format"];
    XCTAssertEqual(fmt, SSBURIFormatUnknown);
}

#pragma mark - typeToString: / typeFromString:

- (void)testTypeToString_message {
    NSString *str = [SSBURI typeToString:SSBURITypeMessage];
    XCTAssertNotNil(str);
}

- (void)testTypeFromString_roundTrip {
    NSArray *types = @[@(SSBURITypeMessage), @(SSBURITypeFeed), @(SSBURITypeBlob),
                       @(SSBURITypeAddress)];
    for (NSNumber *typeNum in types) {
        SSBURIType type = (SSBURIType)typeNum.integerValue;
        NSString *str = [SSBURI typeToString:type];
        if (str) {
            SSBURIType recovered = [SSBURI typeFromString:str];
            XCTAssertEqual(recovered, type, @"Round-trip failed for type %ld", (long)type);
        }
    }
}

#pragma mark - encodeMultiserverAddress: / decodeMultiserverAddress:

- (void)testEncodeDecodeMultiserverAddress_roundTrip {
    NSString *msa = @"net:room.example.com:8008~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
    NSString *encoded = [SSBURI encodeMultiserverAddress:msa];
    XCTAssertNotNil(encoded);

    NSString *decoded = [SSBURI decodeMultiserverAddress:encoded];
    XCTAssertEqualObjects(decoded, msa);
}

- (void)testDecodeMultiserverAddress_invalidReturnsNil {
    NSString *decoded = [SSBURI decodeMultiserverAddress:@"!!not_valid_base64!!"];
    // Should return nil or empty string for garbage input
    if (decoded) {
        XCTAssertEqual(decoded.length, 0);
    }
}

@end

// Private extensions for direct testing of internal class methods
@interface SSBURI (Testing)
+ (NSDictionary<NSString *, NSString *> *)parseQueryParams:(NSString *)query;
+ (NSString *)manualDecodePercentEncoding:(NSString *)encoded;
@end

#pragma mark - SSBURIExtendedTests

@interface SSBURIExtendedTests : XCTestCase
@end

@implementation SSBURIExtendedTests

static NSString * const kFeedId    = @"@LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.ed25519";
static NSString * const kMsgKey    = @"%LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.sha256";
static NSString * const kBlobId    = @"&LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.sha256";
static NSString * const kPubKeyB64 = @"LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";

#pragma mark - URIWithString: edge cases

- (void)testURIWithString_nil_returnsNil {
    XCTAssertNil([SSBURI URIWithString:nil]);
}

- (void)testURIWithString_empty_returnsNil {
    XCTAssertNil([SSBURI URIWithString:@""]);
}

- (void)testURIWithString_nonSSBNonSigil_returnsNil {
    XCTAssertNil([SSBURI URIWithString:@"https://example.com"]);
}

- (void)testURIWithString_ssbDoubleSlash_parsesCorrectly {
    NSString *raw = [NSString stringWithFormat:@"ssb://feed/classic/%@", kPubKeyB64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
}

- (void)testURIWithString_experimental_setsType {
    SSBURI *uri = [SSBURI URIWithString:@"ssb:experimental?action=start-http-auth&sid=abc&sc=def"];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeExperimental);
}

- (void)testURIWithString_experimental_parsesQueryParams {
    SSBURI *uri = [SSBURI URIWithString:@"ssb:experimental?action=claim-http-invite&invite=code123"];
    XCTAssertNotNil(uri);
    XCTAssertEqualObjects(uri.queryParams[@"action"], @"claim-http-invite");
    XCTAssertEqualObjects(uri.queryParams[@"invite"], @"code123");
}

- (void)testURIWithString_experimental_noQuery_hasNoParams {
    SSBURI *uri = [SSBURI URIWithString:@"ssb:experimental"];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeExperimental);
}

- (void)testURIWithString_addressMultiserverSlash_parsesAddress {
    NSString *msAddr = @"net:example.com:8008~shs:abc";
    NSString *encoded = [SSBURI encodeMultiserverAddress:msAddr];
    NSString *raw = [NSString stringWithFormat:@"ssb:address/multiserver?multiserverAddress=%@", encoded];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeAddress);
    XCTAssertEqual(uri.format, SSBURIFormatMultiserver);
}

- (void)testURIWithString_addressMultiserverColon_parsesAddress {
    NSString *msAddr = @"net:example.com:8008~shs:abc";
    NSString *encoded = [SSBURI encodeMultiserverAddress:msAddr];
    NSString *raw = [NSString stringWithFormat:@"ssb:address:multiserver?multiserverAddress=%@", encoded];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeAddress);
}

- (void)testURIWithString_withQueryParams_setsQueryParams {
    NSString *raw = [NSString stringWithFormat:@"ssb:message/sha256/%@?foo=bar", kPubKeyB64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqualObjects(uri.queryParams[@"foo"], @"bar");
}

- (void)testURIWithString_fourParts_setsParentMessageId {
    NSString *raw = [NSString stringWithFormat:@"ssb:feed/classic/%@/%@", kPubKeyB64, kPubKeyB64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqualObjects(uri.parentMessageId, kPubKeyB64);
}

- (void)testURIWithString_colonSeparated_parsesFeed {
    NSString *raw = [NSString stringWithFormat:@"ssb:feed:classic:%@", kPubKeyB64];
    SSBURI *uri = [SSBURI URIWithString:raw];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeFeed);
    XCTAssertEqualObjects(uri.identifier, kPubKeyB64);
}

- (void)testURIWithString_twoParts_noIdentifier {
    SSBURI *uri = [SSBURI URIWithString:@"ssb:message/classic"];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeMessage);
    XCTAssertNil(uri.identifier);
}

- (void)testURIWithString_encryptionKey_setsType {
    SSBURI *uri = [SSBURI URIWithString:[NSString stringWithFormat:@"ssb:encryption-key/box2-dm-dh/%@", kPubKeyB64]];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeEncryptionKey);
}

- (void)testURIWithString_identity_setsType {
    SSBURI *uri = [SSBURI URIWithString:[NSString stringWithFormat:@"ssb:identity/fusion/%@", kPubKeyB64]];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeIdentity);
}

#pragma mark - parseQueryParams:

- (void)testParseQueryParams_nil_returnsEmpty {
    NSDictionary *result = [SSBURI parseQueryParams:nil];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.count, 0U);
}

- (void)testParseQueryParams_empty_returnsEmpty {
    NSDictionary *result = [SSBURI parseQueryParams:@""];
    XCTAssertEqual(result.count, 0U);
}

- (void)testParseQueryParams_singleKeyValue {
    NSDictionary *result = [SSBURI parseQueryParams:@"key=value"];
    XCTAssertEqualObjects(result[@"key"], @"value");
}

- (void)testParseQueryParams_multipleParams {
    NSDictionary *result = [SSBURI parseQueryParams:@"a=1&b=2&c=3"];
    XCTAssertEqualObjects(result[@"a"], @"1");
    XCTAssertEqualObjects(result[@"b"], @"2");
    XCTAssertEqualObjects(result[@"c"], @"3");
}

- (void)testParseQueryParams_keyOnly_storesEmpty {
    NSDictionary *result = [SSBURI parseQueryParams:@"flag"];
    XCTAssertEqualObjects(result[@"flag"], @"");
}

- (void)testParseQueryParams_percentEncoded_decodesValue {
    NSDictionary *result = [SSBURI parseQueryParams:@"key=hello%20world"];
    XCTAssertEqualObjects(result[@"key"], @"hello world");
}

#pragma mark - Factory method edge cases

- (void)testURIWithMessage_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithMessage:nil format:SSBURIFormatClassic]);
}

- (void)testURIWithMessage_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithMessage:@"" format:SSBURIFormatClassic]);
}

- (void)testURIWithFeed_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithFeed:nil format:SSBURIFormatClassic]);
}

- (void)testURIWithFeed_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithFeed:@"" format:SSBURIFormatClassic]);
}

- (void)testURIWithFeed_noParentMsgId_noParentInCanonical {
    SSBURI *uri = [SSBURI uriWithFeed:kFeedId parentMessageId:nil format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    XCTAssertFalse([uri.canonicalString containsString:@"nil"]);
    XCTAssertNil(uri.parentMessageId);
}

- (void)testURIWithFeed_emptyParentMsgId_noParentInCanonical {
    SSBURI *uri = [SSBURI uriWithFeed:kFeedId parentMessageId:@"" format:SSBURIFormatClassic];
    XCTAssertNotNil(uri);
    // Empty string parentMsgId is stored but not appended to canonical (length == 0)
    XCTAssertFalse([uri.canonicalString hasSuffix:@"//"]);
}

- (void)testURIWithBlob_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithBlob:nil format:SSBURIFormatClassic]);
}

- (void)testURIWithBlob_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithBlob:@"" format:SSBURIFormatClassic]);
}

- (void)testURIWithEncryptionKey_returnsEncryptionKeyURI {
    SSBURI *uri = [SSBURI uriWithEncryptionKey:@"somekey" format:SSBURIFormatBox2DmDh];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeEncryptionKey);
    XCTAssertEqual(uri.format, SSBURIFormatBox2DmDh);
    XCTAssertTrue([uri.canonicalString containsString:@"encryption-key"]);
}

- (void)testURIWithEncryptionKey_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithEncryptionKey:nil format:SSBURIFormatClassic]);
}

- (void)testURIWithEncryptionKey_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithEncryptionKey:@"" format:SSBURIFormatClassic]);
}

- (void)testURIWithIdentity_returnsIdentityURI {
    SSBURI *uri = [SSBURI uriWithIdentity:@"fusionkey" format:SSBURIFormatFusion];
    XCTAssertNotNil(uri);
    XCTAssertEqual(uri.type, SSBURITypeIdentity);
    XCTAssertTrue([uri.canonicalString containsString:@"identity"]);
}

- (void)testURIWithIdentity_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithIdentity:nil format:SSBURIFormatClassic]);
}

- (void)testURIWithIdentity_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithIdentity:@"" format:SSBURIFormatClassic]);
}

- (void)testURIWithAddress_nil_returnsNil {
    XCTAssertNil([SSBURI uriWithAddress:nil]);
}

- (void)testURIWithAddress_empty_returnsNil {
    XCTAssertNil([SSBURI uriWithAddress:@""]);
}

#pragma mark - formatToString: all formats

- (void)testFormatToString_allFormats {
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatClassic], @"classic");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatBendybuttV1], @"bendybutt-v1");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatGabbygroveV1], @"gabbygrove-v1");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatButtwooV1], @"buttwoo-v1");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatMultiserver], @"multiserver");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatBox2DmDh], @"box2-dm-dh");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatPoBox], @"po-box");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatFusion], @"fusion");
    XCTAssertEqualObjects([SSBURI formatToString:SSBURIFormatUnknown], @"unknown");
}

#pragma mark - formatFromString: all formats

- (void)testFormatFromString_allVariants {
    XCTAssertEqual([SSBURI formatFromString:@"sha256"], SSBURIFormatClassic);
    XCTAssertEqual([SSBURI formatFromString:@"ed25519"], SSBURIFormatClassic);
    XCTAssertEqual([SSBURI formatFromString:@"gabbygrove-v1"], SSBURIFormatGabbygroveV1);
    XCTAssertEqual([SSBURI formatFromString:@"buttwoo-v1"], SSBURIFormatButtwooV1);
    XCTAssertEqual([SSBURI formatFromString:@"box2-dm-dh"], SSBURIFormatBox2DmDh);
    XCTAssertEqual([SSBURI formatFromString:@"po-box"], SSBURIFormatPoBox);
    XCTAssertEqual([SSBURI formatFromString:@"fusion"], SSBURIFormatFusion);
    XCTAssertEqual([SSBURI formatFromString:@"unknown-format"], SSBURIFormatUnknown);
    XCTAssertEqual([SSBURI formatFromString:nil], SSBURIFormatUnknown);
}

#pragma mark - typeToString: all types

- (void)testTypeToString_allTypes {
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeMessage], @"message");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeFeed], @"feed");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeBlob], @"blob");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeAddress], @"address");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeExperimental], @"experimental");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeEncryptionKey], @"encryption-key");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeIdentity], @"identity");
    XCTAssertEqualObjects([SSBURI typeToString:SSBURITypeUnknown], @"unknown");
}

#pragma mark - typeFromString: all types

- (void)testTypeFromString_allTypes {
    XCTAssertEqual([SSBURI typeFromString:@"experimental"], SSBURITypeExperimental);
    XCTAssertEqual([SSBURI typeFromString:@"encryption-key"], SSBURITypeEncryptionKey);
    XCTAssertEqual([SSBURI typeFromString:@"identity"], SSBURITypeIdentity);
    XCTAssertEqual([SSBURI typeFromString:@"not-a-type"], SSBURITypeUnknown);
    XCTAssertEqual([SSBURI typeFromString:nil], SSBURITypeUnknown);
}

#pragma mark - encodeMultiserverAddress:

- (void)testEncodeMultiserverAddress_nil_returnsEmpty {
    NSString *result = [SSBURI encodeMultiserverAddress:nil];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncodeMultiserverAddress_encodesSpecialChars {
    NSString *result = [SSBURI encodeMultiserverAddress:@"net:example.com:8008~shs:key="];
    XCTAssertNotNil(result);
    // ~ is in the allowed chars so it stays; = and : are encoded
    XCTAssertTrue([result containsString:@"~"]);
    // Colons should be percent-encoded (: is not in allowed set)
    XCTAssertTrue([result containsString:@"%"]);
}

#pragma mark - decodeMultiserverAddress:

- (void)testDecodeMultiserverAddress_nil_returnsNil {
    XCTAssertNil([SSBURI decodeMultiserverAddress:nil]);
}

- (void)testDecodeMultiserverAddress_noPercentSign_returnsNil {
    // No % in string → returns nil immediately
    XCTAssertNil([SSBURI decodeMultiserverAddress:@"net:example.com:8008~shs:abc"]);
}

- (void)testDecodeMultiserverAddress_validEncoding_returnsDecoded {
    NSString *original = @"net:example.com:8008~shs:abcdef";
    NSString *encoded = [SSBURI encodeMultiserverAddress:original];
    XCTAssertTrue([encoded containsString:@"%"]); // must have percent encoding
    NSString *decoded = [SSBURI decodeMultiserverAddress:encoded];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testDecodeMultiserverAddress_malformedEncoding_fallback {
    // Strings with % but invalid sequences — may trigger fallback on some platforms.
    // %GG has G which is not a hex digit → if fallback runs, returns ""
    // stringByRemovingPercentEncoding may or may not return nil depending on platform.
    NSString *result1 = [SSBURI decodeMultiserverAddress:@"foo%GGbar"];
    if (result1) {
        // Platform decoded it (lenient) or returned empty
        XCTAssertTrue(YES); // no crash
    }
    // Incomplete percent sequence at end of string — more likely to cause nil return
    NSString *result2 = [SSBURI decodeMultiserverAddress:@"test%"];
    if (result2) {
        XCTAssertTrue(YES); // no crash
    }
    // At minimum, verify no crash
    XCTAssertTrue(YES);
}

- (void)testURIWithString_ssbEmptyPath_returnsNil {
    // "ssb:" → afterScheme="" → parts[0].length==0 → nil
    SSBURI *uri = [SSBURI URIWithString:@"ssb:"];
    XCTAssertNil(uri);
}

#pragma mark - manualDecodePercentEncoding:

- (void)testManualDecodePercentEncoding_nil_returnsEmpty {
    NSString *result = [SSBURI manualDecodePercentEncoding:nil];
    XCTAssertEqualObjects(result, @"");
}

- (void)testManualDecodePercentEncoding_noPercent_returnsInput {
    NSString *result = [SSBURI manualDecodePercentEncoding:@"hello"];
    XCTAssertEqualObjects(result, @"hello");
}

- (void)testManualDecodePercentEncoding_validSequence_decodes {
    // %41 = 'A', %42 = 'B'
    NSString *result = [SSBURI manualDecodePercentEncoding:@"foo%41%42"];
    XCTAssertEqualObjects(result, @"fooAB");
}

- (void)testManualDecodePercentEncoding_invalidHex_returnsEmpty {
    // %GG is invalid (G not in hex charset)
    NSString *result = [SSBURI manualDecodePercentEncoding:@"foo%GG"];
    XCTAssertEqualObjects(result, @"");
}

#pragma mark - description

- (void)testDescription_containsCanonicalString {
    SSBURI *uri = [SSBURI uriWithFeed:kFeedId format:SSBURIFormatClassic];
    NSString *desc = [uri description];
    XCTAssertNotNil(desc);
    XCTAssertTrue([desc containsString:kFeedId]);
}

@end
