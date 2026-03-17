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
