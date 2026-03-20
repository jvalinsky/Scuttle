#import <XCTest/XCTest.h>
#import "SSBGitPackIDXParser.h"

static NSString *SSBGitFixtureDirectory(void) {
    return [[@__FILE__ stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Fixtures/Git"];
}

static NSData *SSBGitFixtureData(NSString *name) {
    NSString *path = [SSBGitFixtureDirectory() stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSCAssert(data != nil, @"Missing git fixture %@", path);
    return data;
}

static NSDictionary<NSString *, NSString *> *SSBGitFixtureManifest(void) {
    NSData *data = SSBGitFixtureData(@"manifest.json");
    NSDictionary<NSString *, NSString *> *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSCAssert([manifest isKindOfClass:[NSDictionary class]], @"Invalid git fixture manifest");
    return manifest;
}

static NSData *SSBGitSHA1DataFromHexString(NSString *hexString) {
    NSMutableData *data = [NSMutableData dataWithCapacity:20];
    for (NSUInteger i = 0; i < hexString.length; i += 2) {
        unsigned value = 0;
        [[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

static void SSBGitAppendBigUInt32(NSMutableData *data, uint32_t value) {
    uint32_t big = NSSwapHostIntToBig(value);
    [data appendBytes:&big length:sizeof(big)];
}

static void SSBGitAppendBigUInt64(NSMutableData *data, uint64_t value) {
    uint64_t big = NSSwapHostLongLongToBig(value);
    [data appendBytes:&big length:sizeof(big)];
}

static NSData *SSBGitBuildIDXFixture(NSArray<NSDictionary<NSString *, id> *> *entries) {
    NSArray<NSDictionary<NSString *, id> *> *sortedEntries = [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> *lhs, NSDictionary<NSString *,id> *rhs) {
        return [lhs[@"sha"] compare:rhs[@"sha"]];
    }];

    NSMutableArray<NSNumber *> *fanoutCounts = [NSMutableArray arrayWithCapacity:256];
    for (NSUInteger i = 0; i < 256; i++) {
        [fanoutCounts addObject:@0];
    }

    for (NSDictionary<NSString *, id> *entry in sortedEntries) {
        NSString *sha = entry[@"sha"];
        unsigned firstByte = 0;
        [[NSScanner scannerWithString:[sha substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&firstByte];
        for (NSUInteger idx = firstByte; idx < 256; idx++) {
            fanoutCounts[idx] = @([fanoutCounts[idx] unsignedIntValue] + 1);
        }
    }

    NSMutableData *data = [NSMutableData data];
    SSBGitAppendBigUInt32(data, 0xff744f63);
    SSBGitAppendBigUInt32(data, 2);

    for (NSNumber *count in fanoutCounts) {
        SSBGitAppendBigUInt32(data, count.unsignedIntValue);
    }

    for (NSDictionary<NSString *, id> *entry in sortedEntries) {
        [data appendData:SSBGitSHA1DataFromHexString(entry[@"sha"])];
    }

    for (__unused NSDictionary<NSString *, id> *entry in sortedEntries) {
        SSBGitAppendBigUInt32(data, 0);
    }

    NSMutableArray<NSNumber *> *largeOffsets = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *entry in sortedEntries) {
        uint64_t offset = [entry[@"offset"] unsignedLongLongValue];
        if (offset > 0x7fffffffULL) {
            uint32_t largeIndex = (uint32_t)largeOffsets.count;
            [largeOffsets addObject:@(offset)];
            SSBGitAppendBigUInt32(data, 0x80000000U | largeIndex);
        } else {
            SSBGitAppendBigUInt32(data, (uint32_t)offset);
        }
    }

    for (NSNumber *offset in largeOffsets) {
        SSBGitAppendBigUInt64(data, offset.unsignedLongLongValue);
    }

    [data appendData:[NSMutableData dataWithLength:40]];
    return data;
}

@interface SSBGitPackIDXParserTests : XCTestCase
@end

@implementation SSBGitPackIDXParserTests

- (void)testInitializationWithInvalidData {
    NSData *shortData = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:shortData];
    XCTAssertNil(parser, @"Should fail to initialize with short data");
}

- (void)testInitializationWithInvalidMagic {
    NSMutableData *badMagic = [NSMutableData dataWithLength:1032 + 40];
    uint32_t *bytes = (uint32_t *)badMagic.mutableBytes;
    bytes[0] = NSSwapHostIntToBig(0x12345678);
    bytes[1] = NSSwapHostIntToBig(2);

    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:badMagic];
    XCTAssertNil(parser, @"Should fail to initialize with bad magic");
}

- (void)testLookupOffsetsFromCheckedInFixture {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitFixtureManifest();
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:SSBGitFixtureData(@"delta-ref.idx")];

    XCTAssertNotNil(parser);
    XCTAssertGreaterThan([parser offsetForHexString:manifest[@"commit_head"]], 0ULL);
    XCTAssertGreaterThan([parser offsetForHexString:manifest[@"commit_previous"]], 0ULL);
    XCTAssertGreaterThan([parser offsetForHexString:manifest[@"tree_head"]], 0ULL);
    XCTAssertGreaterThan([parser offsetForHexString:manifest[@"blob_file1_updated"]], 0ULL);
    XCTAssertEqual([parser offsetForHexString:@"ffffffffffffffffffffffffffffffffffffffff"], 0ULL);
}

- (void)testLookupHonorsFanoutBoundaries {
    NSData *data = SSBGitBuildIDXFixture(@[
        @{ @"sha": @"00aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", @"offset": @(11) },
        @{ @"sha": @"7fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", @"offset": @(22) },
        @{ @"sha": @"ffcccccccccccccccccccccccccccccccccccccc", @"offset": @(33) }
    ]);
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:data];

    XCTAssertEqual([parser offsetForHexString:@"00aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], 11ULL);
    XCTAssertEqual([parser offsetForHexString:@"7fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"], 22ULL);
    XCTAssertEqual([parser offsetForHexString:@"ffcccccccccccccccccccccccccccccccccccccc"], 33ULL);
    XCTAssertEqual([parser offsetForHexString:@"01dddddddddddddddddddddddddddddddddddddd"], 0ULL);
}

- (void)testLookupSupportsLargeOffsetTable {
    uint64_t largeOffset = 0x100000001ULL;
    NSData *data = SSBGitBuildIDXFixture(@[
        @{ @"sha": @"10aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", @"offset": @(largeOffset) }
    ]);
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:data];

    XCTAssertNotNil(parser);
    XCTAssertEqual([parser offsetForHexString:@"10aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], largeOffset);
}

- (void)testLookupRejectsOutOfBoundsLargeOffsetTable {
    NSMutableData *data = [SSBGitBuildIDXFixture(@[
        @{ @"sha": @"20aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", @"offset": @(0x100000001ULL) }
    ]) mutableCopy];
    [data setLength:data.length - 1];

    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:data];
    XCTAssertNotNil(parser);
    XCTAssertEqual([parser offsetForHexString:@"20aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], 0ULL);
}

@end
