#import <XCTest/XCTest.h>
#import "SSBBFE.h"

@interface SSBBFETests : XCTestCase
@end

@implementation SSBBFETests

- (void)testFeedIDClassicEncoding {
    NSString *feedID = @"@6uS7fC1v5fS_yX3F5N2RjF4M_l6SjC1v5fS_yX3F5M0=.ed25519";
    NSData *bfe = [SSBBFE encodeFeedID:feedID format:SSBBFEFeedFormatClassic];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeFeed);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEFeedFormatClassic);
    
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    NSString *expectedSigil = @"@6uS7fC1v5fS_yX3F5N2RjF4M_l6SjC1v5fS_yX3F5M0.ed25519";
    XCTAssertEqualObjects(sigil, expectedSigil);
}

- (void)testMessageIDClassicEncoding {
    NSString *msgID = @"%7uS7fC1v5fS_yX3F5N2RjF4M_l6SjC1v5fS_yX3F5M0=.sha256";
    NSData *bfe = [SSBBFE encodeMessageID:msgID format:SSBBFEMessageFormatClassic];
    XCTAssertNotNil(bfe);
    XCTAssertEqual(bfe.length, 34);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[0], SSBBFETypeMessage);
    XCTAssertEqual(((uint8_t *)bfe.bytes)[1], SSBBFEMessageFormatClassic);
    
    NSString *sigil = [SSBBFE sigilStringFromBFE:bfe];
    NSString *expectedSigil = @"%7uS7fC1v5fS_yX3F5N2RjF4M_l6SjC1v5fS_yX3F5M0.sha256";
    XCTAssertEqualObjects(sigil, expectedSigil);
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
