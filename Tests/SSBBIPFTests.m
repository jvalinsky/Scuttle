#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBIPF.h>

@interface SSBBIPFTests : XCTestCase
@end

@implementation SSBBIPFTests

#pragma mark - String

- (void)testEncodeDecodeString_ascii {
    NSData *encoded = [SSBBIPF encodeString:@"hello"];
    XCTAssertNotNil(encoded);

    NSUInteger consumed = 0;
    NSString *decoded = [SSBBIPF decodeString:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @"hello");
    XCTAssertEqual(consumed, encoded.length);
}

- (void)testEncodeDecodeString_empty {
    NSData *encoded = [SSBBIPF encodeString:@""];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSString *decoded = [SSBBIPF decodeString:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @"");
}

- (void)testEncodeDecodeString_unicode {
    NSString *original = @"こんにちは";
    NSData *encoded = [SSBBIPF encodeString:original];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSString *decoded = [SSBBIPF decodeString:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, original);
}

#pragma mark - Bytes

- (void)testEncodeDecodeBytes_arbitrary {
    uint8_t bytes[] = {0x00, 0xFF, 0x7F, 0x80};
    NSData *original = [NSData dataWithBytes:bytes length:4];
    NSData *encoded = [SSBBIPF encodeBytes:original];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSData *decoded = [SSBBIPF decodeBytes:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testEncodeDecodeBytes_empty {
    NSData *encoded = [SSBBIPF encodeBytes:[NSData data]];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSData *decoded = [SSBBIPF decodeBytes:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, [NSData data]);
}

#pragma mark - Integer

- (void)testEncodeDecodeInteger_zero {
    NSData *encoded = [SSBBIPF encodeInteger:0];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeInteger:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @0);
}

- (void)testEncodeDecodeInteger_positive {
    NSData *encoded = [SSBBIPF encodeInteger:42];
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeInteger:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @42);
}

- (void)testEncodeDecodeInteger_negative {
    NSData *encoded = [SSBBIPF encodeInteger:-1];
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeInteger:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @(-1));
}

- (void)testEncodeDecodeInteger_largeValue {
    int64_t big = (int64_t)INT32_MAX + 1;
    NSData *encoded = [SSBBIPF encodeInteger:big];
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeInteger:encoded consumed:&consumed];
    XCTAssertEqual(decoded.longLongValue, big);
}

#pragma mark - Double

- (void)testEncodeDecodeDouble_pi {
    NSData *encoded = [SSBBIPF encodeDouble:M_PI];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeDouble:encoded consumed:&consumed];
    XCTAssertEqualWithAccuracy(decoded.doubleValue, M_PI, 1e-10);
}

- (void)testEncodeDecodeDouble_zero {
    NSData *encoded = [SSBBIPF encodeDouble:0.0];
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeDouble:encoded consumed:&consumed];
    XCTAssertEqualWithAccuracy(decoded.doubleValue, 0.0, 1e-10);
}

#pragma mark - Bool / Null

- (void)testEncodeDecodeTrue {
    NSData *encoded = [SSBBIPF encodeBool:YES];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeBool:encoded consumed:&consumed];
    XCTAssertTrue(decoded.boolValue);
}

- (void)testEncodeDecodeFalse {
    NSData *encoded = [SSBBIPF encodeBool:NO];
    NSUInteger consumed = 0;
    NSNumber *decoded = [SSBBIPF decodeBool:encoded consumed:&consumed];
    XCTAssertFalse(decoded.boolValue);
}

- (void)testEncodeDecodeNull {
    NSData *encoded = [SSBBIPF encodeNull];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decodeNull:encoded consumed:&consumed];
    XCTAssertNotNil(decoded);  // NSNull singleton
}

#pragma mark - List

- (void)testEncodeDecodeList_mixed {
    NSArray *original = @[@"hello", @42, @YES];
    NSData *encoded = [SSBBIPF encodeList:original];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSArray *decoded = [SSBBIPF decodeList:encoded consumed:&consumed];
    XCTAssertEqual(decoded.count, 3);
}

- (void)testEncodeDecodeList_empty {
    NSData *encoded = [SSBBIPF encodeList:@[]];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSArray *decoded = [SSBBIPF decodeList:encoded consumed:&consumed];
    XCTAssertEqual(decoded.count, 0);
}

- (void)testEncodeDecodeList_nested {
    NSArray *inner = @[@"a", @"b"];
    NSArray *outer = @[inner, @1];
    NSData *encoded = [SSBBIPF encodeList:outer];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSArray *decoded = [SSBBIPF decodeList:encoded consumed:&consumed];
    XCTAssertEqual(decoded.count, 2);
}

#pragma mark - Dictionary

- (void)testEncodeDecodeDictionary_simple {
    NSDictionary *original = @{@"key": @"value", @"num": @99};
    NSData *encoded = [SSBBIPF encodeDictionary:original];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSDictionary *decoded = [SSBBIPF decodeDictionary:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded[@"key"], @"value");
    XCTAssertEqualObjects(decoded[@"num"], @99);
}

- (void)testEncodeDecodeDictionary_empty {
    NSData *encoded = [SSBBIPF encodeDictionary:@{}];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    NSDictionary *decoded = [SSBBIPF decodeDictionary:encoded consumed:&consumed];
    XCTAssertEqual(decoded.count, 0);
}

#pragma mark - Generic encode:/decode: (round-trips)

- (void)testGenericEncode_string {
    NSData *encoded = [SSBBIPF encode:@"generic"];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decode:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @"generic");
}

- (void)testGenericEncode_number {
    NSData *encoded = [SSBBIPF encode:@7];
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decode:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, @7);
}

- (void)testGenericEncode_dictionary {
    NSDictionary *dict = @{@"type": @"post"};
    NSData *encoded = [SSBBIPF encode:dict];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decode:encoded consumed:&consumed];
    XCTAssertTrue([decoded isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(decoded[@"type"], @"post");
}

#pragma mark - Varint

- (void)testWriteReadVarint_singleByte {
    NSData *encoded = [SSBBIPF writeVarint:5];
    XCTAssertNotNil(encoded);
    uint64_t value = 0;
    [SSBBIPF readVarint:encoded offset:0 value:&value];
    XCTAssertEqual(value, (uint64_t)5);
}

- (void)testWriteReadVarint_multiByte {
    uint64_t big = 300;  // requires 2 bytes in varint
    NSData *encoded = [SSBBIPF writeVarint:big];
    uint64_t value = 0;
    [SSBBIPF readVarint:encoded offset:0 value:&value];
    XCTAssertEqual(value, big);
}

- (void)testWriteReadVarint_zero {
    NSData *encoded = [SSBBIPF writeVarint:0];
    uint64_t value = 0;
    [SSBBIPF readVarint:encoded offset:0 value:&value];
    XCTAssertEqual(value, (uint64_t)0);
}

#pragma mark - humanReadable:

- (void)testHumanReadable_returnsNonEmptyString {
    NSData *encoded = [SSBBIPF encodeString:@"readable"];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertNotNil(hr);
    XCTAssertGreaterThan(hr.length, 0);
}

@end
