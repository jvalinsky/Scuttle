#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBendyButt.h>

// TweetNaCl keypair function linked via SSBNetwork.framework.
extern int crypto_sign_ed25519_keypair(unsigned char *pk, unsigned char *sk);

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
    BBGenerateKeypair(&_publicKey, &_secretKey);
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

@end
