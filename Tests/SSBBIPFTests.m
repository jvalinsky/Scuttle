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

- (void)testHumanReadable_nilReturnsEmpty {
    NSString *hr = [SSBBIPF humanReadable:nil];
    XCTAssertEqualObjects(hr, @"");
}

- (void)testHumanReadable_emptyDataReturnsEmpty {
    NSString *hr = [SSBBIPF humanReadable:[NSData data]];
    XCTAssertEqualObjects(hr, @"");
}

- (void)testHumanReadable_boolTrue {
    NSData *encoded = [SSBBIPF encodeBool:YES];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertEqualObjects(hr, @"true");
}

- (void)testHumanReadable_boolFalse {
    // In this BIPF implementation, false encodes as length=0 which is decoded as NSNull (same as null)
    NSData *encoded = [SSBBIPF encodeBool:NO];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertEqualObjects(hr, @"null");
}

- (void)testHumanReadable_null {
    NSData *encoded = [SSBBIPF encodeNull];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertEqualObjects(hr, @"null");
}

- (void)testHumanReadable_bytes {
    uint8_t b[] = {0x01, 0x02};
    NSData *payload = [NSData dataWithBytes:b length:2];
    NSData *encoded = [SSBBIPF encodeBytes:payload];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertNotNil(hr);
    // Should contain '#' delimiters
    XCTAssertTrue([hr hasPrefix:@"#"]);
}

- (void)testHumanReadable_integer {
    NSData *encoded = [SSBBIPF encodeInteger:42];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertEqualObjects(hr, @"42");
}

- (void)testHumanReadable_double {
    NSData *encoded = [SSBBIPF encodeDouble:1.5];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertNotNil(hr);
    XCTAssertGreaterThan(hr.length, 0);
}

- (void)testHumanReadable_list {
    NSData *encoded = [SSBBIPF encodeList:@[@"a", @1]];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertTrue([hr hasPrefix:@"["]);
    XCTAssertTrue([hr hasSuffix:@"]"]);
}

- (void)testHumanReadable_dict {
    NSDictionary *dict = @{@"k": @"v"};
    NSData *encoded = [SSBBIPF encodeDictionary:dict];
    NSString *hr = [SSBBIPF humanReadable:encoded];
    XCTAssertTrue([hr hasPrefix:@"{"]);
    XCTAssertTrue([hr hasSuffix:@"}"]);
}

#pragma mark - Generic encode: edge cases

- (void)testGenericEncode_nsdata_encodesAsBytes {
    uint8_t b[] = {0xAB, 0xCD};
    NSData *data = [NSData dataWithBytes:b length:2];
    NSData *encoded = [SSBBIPF encode:data];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decode:encoded consumed:&consumed];
    XCTAssertEqualObjects(decoded, data);
}

- (void)testGenericEncode_floatNSNumber_encodesAsDouble {
    NSNumber *floatNum = @(3.14f);
    NSData *encoded = [SSBBIPF encode:floatNum];
    XCTAssertNotNil(encoded);
}

- (void)testGenericEncode_boolYES_encodesAsBool {
    NSData *encoded = [SSBBIPF encode:@YES];
    XCTAssertNotNil(encoded);
    NSUInteger consumed = 0;
    id decoded = [SSBBIPF decode:encoded consumed:&consumed];
    XCTAssertTrue([decoded boolValue]);
}

- (void)testGenericEncode_nsNull_encodesAsNull {
    NSData *encoded = [SSBBIPF encode:[NSNull null]];
    XCTAssertNotNil(encoded);
}

- (void)testGenericEncode_nil_encodesAsNull {
    NSData *encoded = [SSBBIPF encode:nil];
    XCTAssertNotNil(encoded);
}

- (void)testGenericEncode_unknownType_returnsNil {
    // NSDate is not a supported BIPF type
    NSData *encoded = [SSBBIPF encode:[NSDate date]];
    XCTAssertNil(encoded);
}

#pragma mark - Generic decode: edge cases

- (void)testGenericDecode_extendedType_returnsNil {
    // Craft a tag with type bits = 7 (SSBBIPFTypeExtended) to hit the default case
    // Tag byte: type=7 (0b111), length=0 → tag = (0 << 3) | 7 = 0x07
    uint8_t tagByte = 0x07;
    NSData *data = [NSData dataWithBytes:&tagByte length:1];
    NSUInteger consumed = 0;
    id result = [SSBBIPF decode:data consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeString_wrongType_returnsNil {
    // Encode an integer, then try to decode it as a string
    NSData *encoded = [SSBBIPF encodeInteger:42];
    NSUInteger consumed = 0;
    NSString *result = [SSBBIPF decodeString:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeBytes_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSData *result = [SSBBIPF decodeBytes:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeInteger_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSNumber *result = [SSBBIPF decodeInteger:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeDouble_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSNumber *result = [SSBBIPF decodeDouble:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeBool_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSNumber *result = [SSBBIPF decodeBool:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeNull_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeInteger:1];
    NSUInteger consumed = 0;
    id result = [SSBBIPF decodeNull:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeList_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSArray *result = [SSBBIPF decodeList:encoded consumed:&consumed];
    XCTAssertNil(result);
}

- (void)testDecodeDictionary_wrongType_returnsNil {
    NSData *encoded = [SSBBIPF encodeString:@"oops"];
    NSUInteger consumed = 0;
    NSDictionary *result = [SSBBIPF decodeDictionary:encoded consumed:&consumed];
    XCTAssertNil(result);
}

@end
