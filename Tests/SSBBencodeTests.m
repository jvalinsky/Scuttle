#import <XCTest/XCTest.h>
#import "SSBBencode.h"

@interface SSBBencodeTests : XCTestCase
@end

@implementation SSBBencodeTests

#pragma mark - Helper

- (NSData *)dataFromASCII:(NSString *)ascii {
    return [ascii dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)asciiFromData:(NSData *)data {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - encodeInteger:

- (void)testEncodeInteger_zero_isI0e {
    NSData *result = [SSBBencode encodeInteger:0];
    XCTAssertEqualObjects([self asciiFromData:result], @"i0e");
}

- (void)testEncodeInteger_positive_isCorrect {
    NSData *result = [SSBBencode encodeInteger:42];
    XCTAssertEqualObjects([self asciiFromData:result], @"i42e");
}

- (void)testEncodeInteger_negative_isCorrect {
    NSData *result = [SSBBencode encodeInteger:-7];
    XCTAssertEqualObjects([self asciiFromData:result], @"i-7e");
}

- (void)testEncodeInteger_large_isCorrect {
    NSData *result = [SSBBencode encodeInteger:1000000];
    XCTAssertEqualObjects([self asciiFromData:result], @"i1000000e");
}

#pragma mark - encodeString:

- (void)testEncodeString_hello_is5colonHello {
    NSData *result = [SSBBencode encodeString:@"hello"];
    XCTAssertEqualObjects([self asciiFromData:result], @"5:hello");
}

- (void)testEncodeString_empty_is0colon {
    NSData *result = [SSBBencode encodeString:@""];
    XCTAssertEqualObjects([self asciiFromData:result], @"0:");
}

- (void)testEncodeString_unicode_encodesUTF8Bytes {
    // "café" is 5 UTF-8 bytes (c-a-f-é where é is 2 bytes)
    NSData *result = [SSBBencode encodeString:@"café"];
    XCTAssertNotNil(result);
    // Should start with the length in bytes
    NSString *str = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
    XCTAssertTrue([str hasPrefix:@"5:"], @"café is 5 UTF-8 bytes: %@", str);
}

#pragma mark - encodeData:

- (void)testEncodeData_twoBytes_is2colonXX {
    uint8_t bytes[] = {0xAB, 0xCD};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    NSData *result = [SSBBencode encodeData:data];
    XCTAssertNotNil(result);
    // First 2 bytes are "2:"
    NSString *prefix = [[NSString alloc] initWithData:[result subdataWithRange:NSMakeRange(0, 2)] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(prefix, @"2:");
    XCTAssertEqual(result.length, 4U); // "2:" + 2 bytes
}

- (void)testEncodeData_empty_is0colon {
    NSData *result = [SSBBencode encodeData:[NSData data]];
    XCTAssertEqualObjects([self asciiFromData:result], @"0:");
}

#pragma mark - encodeList:

- (void)testEncodeList_emptyList_isLe {
    NSData *result = [SSBBencode encodeList:@[]];
    XCTAssertEqualObjects([self asciiFromData:result], @"le");
}

- (void)testEncodeList_oneInteger_isLi42ee {
    NSData *result = [SSBBencode encodeList:@[@42]];
    XCTAssertEqualObjects([self asciiFromData:result], @"li42ee");
}

- (void)testEncodeList_oneString_isCorrect {
    NSData *result = [SSBBencode encodeList:@[@"foo"]];
    XCTAssertEqualObjects([self asciiFromData:result], @"l3:fooe");
}

- (void)testEncodeList_mixedTypes_isCorrect {
    NSData *result = [SSBBencode encodeList:@[@"hi", @5]];
    XCTAssertEqualObjects([self asciiFromData:result], @"l2:hii5ee");
}

- (void)testEncodeList_nestedList_isCorrect {
    NSData *result = [SSBBencode encodeList:@[@[@"a"]]];
    XCTAssertEqualObjects([self asciiFromData:result], @"ll1:aee");
}

- (void)testEncodeList_withNSData_isCorrect {
    NSData *inner = [self dataFromASCII:@"xy"];
    NSData *result = [SSBBencode encodeList:@[inner]];
    XCTAssertEqualObjects([self asciiFromData:result], @"l2:xye");
}

- (void)testEncodeList_withNSNull_encodesZeroByteString {
    NSData *result = [SSBBencode encodeList:@[[NSNull null]]];
    XCTAssertEqualObjects([self asciiFromData:result], @"l0:e");
}

#pragma mark - encodeDict:

- (void)testEncodeDict_empty_isDe {
    NSData *result = [SSBBencode encodeDict:@{}];
    XCTAssertEqualObjects([self asciiFromData:result], @"de");
}

- (void)testEncodeDict_singleEntry_isCorrect {
    NSData *result = [SSBBencode encodeDict:@{@"k": @"v"}];
    XCTAssertEqualObjects([self asciiFromData:result], @"d1:k1:ve");
}

- (void)testEncodeDict_sortedKeys_isLexicographic {
    // Keys must come out sorted: "a" before "b"
    NSDictionary *dict = @{@"b": @"2", @"a": @"1"};
    NSData *result = [SSBBencode encodeDict:dict];
    XCTAssertEqualObjects([self asciiFromData:result], @"d1:a1:11:b1:2e");
}

- (void)testEncodeDict_integerValue_isCorrect {
    NSData *result = [SSBBencode encodeDict:@{@"n": @42}];
    XCTAssertEqualObjects([self asciiFromData:result], @"d1:ni42ee");
}

#pragma mark - decode:offset:

- (void)testDecodeInteger_positive {
    NSData *data = [self dataFromASCII:@"i42e"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, @42);
    XCTAssertEqual(offset, 4U);
}

- (void)testDecodeInteger_negative {
    NSData *data = [self dataFromASCII:@"i-7e"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, @(-7));
}

- (void)testDecodeInteger_zero {
    NSData *data = [self dataFromASCII:@"i0e"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, @0);
}

- (void)testDecodeInteger_missingE_returnsNil {
    NSData *data = [self dataFromASCII:@"i42"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecodeByteString_simple {
    NSData *data = [self dataFromASCII:@"5:hello"];
    NSUInteger offset = 0;
    NSData *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, [self dataFromASCII:@"hello"]);
    XCTAssertEqual(offset, 7U);
}

- (void)testDecodeByteString_empty {
    NSData *data = [self dataFromASCII:@"0:"];
    NSUInteger offset = 0;
    NSData *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, [NSData data]);
}

- (void)testDecodeByteString_missingColon_returnsNil {
    NSData *data = [self dataFromASCII:@"3abc"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecodeByteString_truncated_returnsNil {
    NSData *data = [self dataFromASCII:@"10:hi"];  // claims 10 bytes but only 2 follow
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecodeList_empty {
    NSData *data = [self dataFromASCII:@"le"];
    NSUInteger offset = 0;
    NSArray *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testDecodeList_oneItem {
    NSData *data = [self dataFromASCII:@"l3:fooe"];
    NSUInteger offset = 0;
    NSArray *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqual(result.count, 1U);
    XCTAssertEqualObjects(result[0], [self dataFromASCII:@"foo"]);
}

- (void)testDecodeList_unterminated_returnsNil {
    NSData *data = [self dataFromASCII:@"l3:foo"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecodeDict_empty {
    NSData *data = [self dataFromASCII:@"de"];
    NSUInteger offset = 0;
    NSDictionary *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result, @{});
}

- (void)testDecodeDict_oneEntry {
    NSData *data = [self dataFromASCII:@"d1:k1:ve"];
    NSUInteger offset = 0;
    NSDictionary *result = [SSBBencode decode:data offset:&offset];
    XCTAssertEqualObjects(result[@"k"], [self dataFromASCII:@"v"]);
}

- (void)testDecodeDict_unterminated_returnsNil {
    NSData *data = [self dataFromASCII:@"d1:k1:v"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecode_nilData_returnsNil {
    NSUInteger offset = 0;
    id result = [SSBBencode decode:nil offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecode_offsetAtEnd_returnsNil {
    NSData *data = [self dataFromASCII:@"i1e"];
    NSUInteger offset = data.length;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecode_unknownPrefix_returnsNil {
    // 'z' is not a valid bencode type indicator
    NSData *data = [self dataFromASCII:@"z"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

#pragma mark - nil input guards

- (void)testEncodeString_nil_returnsNil {
    NSData *result = [SSBBencode encodeString:(NSString * _Nonnull)nil];
    XCTAssertNil(result);
}

- (void)testEncodeData_nil_returnsNil {
    NSData *result = [SSBBencode encodeData:(NSData * _Nonnull)nil];
    XCTAssertNil(result);
}

- (void)testEncodeList_nil_returnsNil {
    NSData *result = [SSBBencode encodeList:(NSArray * _Nonnull)nil];
    XCTAssertNil(result);
}

- (void)testEncodeDict_nil_returnsNil {
    NSData *result = [SSBBencode encodeDict:(NSDictionary * _Nonnull)nil];
    XCTAssertNil(result);
}

#pragma mark - _encodeItem edge cases

- (void)testEncodeList_withUnencodableItem_returnsNil {
    // NSDate is not a supported bencode type — list encoding should return nil
    NSDate *date = [NSDate date];
    NSData *result = [SSBBencode encodeList:@[date]];
    XCTAssertNil(result);
}

- (void)testEncodeDict_withUnencodableValue_returnsNil {
    // NSDate value is unsupported — dict encoding should return nil
    NSDate *date = [NSDate date];
    NSData *result = [SSBBencode encodeDict:@{@"key": date}];
    XCTAssertNil(result);
}

- (void)testEncodeList_withFloatNSNumber_encodesAsString {
    // A float NSNumber hits the fallback "encode as string value" path
    NSNumber *floatNum = @(3.14f);
    NSData *result = [SSBBencode encodeList:@[floatNum]];
    XCTAssertNotNil(result);
}

#pragma mark - decode edge cases

- (void)testDecodeDict_withIntegerKey_returnsNil {
    // Dict key must be a byte string; an integer key (i42e) is invalid → returns nil
    NSData *data = [self dataFromASCII:@"di42e1:ve"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

- (void)testDecode_nullOffset_returnsNil {
    NSData *data = [self dataFromASCII:@"i1e"];
    id result = [SSBBencode decode:data offset:NULL];
    XCTAssertNil(result);
}

- (void)testDecodeDict_invalidValue_returnsNil {
    // Key is present but the value uses an unknown prefix 'z' → decode returns nil
    NSData *data = [self dataFromASCII:@"d1:kze"];
    NSUInteger offset = 0;
    id result = [SSBBencode decode:data offset:&offset];
    XCTAssertNil(result);
}

#pragma mark - Round-trip tests

- (void)testRoundTrip_integer {
    NSData *encoded = [SSBBencode encodeInteger:12345];
    NSUInteger offset = 0;
    id decoded = [SSBBencode decode:encoded offset:&offset];
    XCTAssertEqualObjects(decoded, @12345);
}

- (void)testRoundTrip_string {
    NSData *encoded = [SSBBencode encodeString:@"bencode"];
    NSUInteger offset = 0;
    NSData *decoded = [SSBBencode decode:encoded offset:&offset];
    NSString *str = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"bencode");
}

- (void)testRoundTrip_list {
    NSData *encoded = [SSBBencode encodeList:@[@"a", @1, @"b"]];
    NSUInteger offset = 0;
    NSArray *decoded = [SSBBencode decode:encoded offset:&offset];
    XCTAssertEqual(decoded.count, 3U);
}

- (void)testRoundTrip_nestedList {
    NSData *encoded = [SSBBencode encodeList:@[@[@"x", @"y"]]];
    NSUInteger offset = 0;
    NSArray *outer = [SSBBencode decode:encoded offset:&offset];
    XCTAssertEqual(outer.count, 1U);
    XCTAssertTrue([outer[0] isKindOfClass:[NSArray class]]);
    XCTAssertEqual([(NSArray *)outer[0] count], 2U);
}

@end
