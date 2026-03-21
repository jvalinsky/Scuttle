#import <XCTest/XCTest.h>
#import "SSBGitPackDecoder.h"
#import "SSBGitPackIDXParser.h"
#import "SSBGitObjectStore.h"
#import "SSBBlobStore.h"

static NSString *SSBGitDecoderFixtureDirectory(void) {
    return [[@__FILE__ stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Fixtures/Git"];
}

static NSData *SSBGitDecoderFixtureData(NSString *name) {
    NSString *path = [SSBGitDecoderFixtureDirectory() stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSCAssert(data != nil, @"Missing git fixture %@", path);
    return data;
}

static NSDictionary<NSString *, NSString *> *SSBGitDecoderManifest(void) {
    NSData *data = SSBGitDecoderFixtureData(@"manifest.json");
    NSDictionary<NSString *, NSString *> *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSCAssert([manifest isKindOfClass:[NSDictionary class]], @"Invalid git fixture manifest");
    return manifest;
}

static NSData *SSBGitExpectedFixtureBlob(NSInteger updatedLine) {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger idx = 1; idx <= 400; idx++) {
        if (idx == updatedLine) {
            [text appendFormat:@"alpha line %ld updated same same same same same same same same same same\n", (long)idx];
        } else {
            [text appendFormat:@"alpha line %ld same same same same same same same same same same\n", (long)idx];
        }
    }
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

static SSBGitObjectType SSBGitObjectTypeAtPackOffset(NSData *packData, uint64_t offset) {
    const uint8_t *bytes = packData.bytes;
    return (SSBGitObjectType)((bytes[offset] >> 4) & 0x7);
}

static SSBGitObjectStore *SSBGitObjectStoreWithFixturePack(NSString *packFixture,
                                                           NSString *idxFixture,
                                                           SSBBlobStore **outBlobStore) {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    SSBBlobStore *blobStore = [[SSBBlobStore alloc] initWithPath:[base stringByAppendingPathComponent:@"blobs"]];
    NSString *packBlobID = [blobStore addBlobWithData:SSBGitDecoderFixtureData(packFixture)];
    NSString *idxBlobID = [blobStore addBlobWithData:SSBGitDecoderFixtureData(idxFixture)];
    SSBGitObjectStore *objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:blobStore];
    [objectStore registerPackBlob:packBlobID idxBlob:idxBlobID];
    if (outBlobStore) {
        *outBlobStore = blobStore;
    }
    return objectStore;
}

// Expose internal method for direct testing
@interface SSBGitPackDecoder (TestApplyDelta)
- (nullable NSData *)applyDelta:(NSData *)delta toBase:(NSData *)base;
@end

@interface SSBGitPackDecoderTests : XCTestCase
@end

@implementation SSBGitPackDecoderTests

- (void)testInitializationWithInvalidData {
    NSData *shortData = [@"PACK" dataUsingEncoding:NSUTF8StringEncoding];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:shortData];
    XCTAssertNil(decoder, @"Should fail to initialize with short data");
}

- (void)testInitializationWithInvalidMagic {
    NSMutableData *badMagic = [NSMutableData dataWithLength:32];
    uint32_t *bytes = (uint32_t *)badMagic.mutableBytes;
    bytes[0] = NSSwapHostIntToBig(0x12345678);
    bytes[1] = NSSwapHostIntToBig(2);

    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:badMagic];
    XCTAssertNil(decoder, @"Should fail to initialize with bad magic");
}

- (void)testDecodesCommitTreeAndBlobFromCheckedInFixture {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitDecoderManifest();
    NSData *packData = SSBGitDecoderFixtureData(@"delta-ref.pack");
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:SSBGitDecoderFixtureData(@"delta-ref.idx")];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];

    SSBGitObject *commit = [decoder objectAtOffset:[parser offsetForHexString:manifest[@"commit_head"]]];
    SSBGitObject *tree = [decoder objectAtOffset:[parser offsetForHexString:manifest[@"tree_head"]]];
    SSBGitObject *blob = [decoder objectAtOffset:[parser offsetForHexString:manifest[@"blob_file1_updated"]]];

    XCTAssertEqual(commit.type, SSBGitObjectTypeCommit);
    XCTAssertTrue([[NSString alloc] initWithData:commit.data encoding:NSUTF8StringEncoding].length > 0);
    XCTAssertTrue([[[NSString alloc] initWithData:commit.data encoding:NSUTF8StringEncoding] containsString:@"second"]);

    XCTAssertEqual(tree.type, SSBGitObjectTypeTree);
    NSString *treeString = [[NSString alloc] initWithData:tree.data encoding:NSISOLatin1StringEncoding];
    XCTAssertTrue([treeString containsString:@"file.txt"]);
    XCTAssertTrue([treeString containsString:@"file2.txt"]);

    XCTAssertEqual(blob.type, SSBGitObjectTypeBlob);
    XCTAssertEqualObjects(blob.data, SSBGitExpectedFixtureBlob(200));
}

- (void)testDecodesOfsDeltaFromCheckedInFixture {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitDecoderManifest();
    NSData *packData = SSBGitDecoderFixtureData(@"delta-ofs.pack");
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:SSBGitDecoderFixtureData(@"delta-ofs.idx")];
    uint64_t offset = [parser offsetForHexString:manifest[@"blob_file2_updated"]];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];

    XCTAssertEqual(SSBGitObjectTypeAtPackOffset(packData, offset), SSBGitObjectTypeOfsDelta);

    SSBGitObject *blob = [decoder objectAtOffset:offset];
    XCTAssertEqual(blob.type, SSBGitObjectTypeBlob);
    XCTAssertEqualObjects(blob.data, SSBGitExpectedFixtureBlob(300));
}

- (void)testObjectAtOffset_outOfBounds_returnsNil {
    // offset >= _length triggers the early guard in objectAtOffset:recursionDepth:
    NSData *packData = SSBGitDecoderFixtureData(@"delta-ref.pack");
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];
    XCTAssertNil([decoder objectAtOffset:packData.length]);
    XCTAssertNil([decoder objectAtOffset:UINT64_MAX]);
}

- (void)testObjectAtOffset_corruptedZlibData_returnsNil {
    // Build a minimal PACK with a blob object header (type=3, size=1) followed
    // by garbage bytes. inflate() returns Z_DATA_ERROR → decompressDataAtOffset:
    // returns nil → objectAtOffset: returns nil (covers lines 156-157).
    NSMutableData *pack = [NSMutableData data];
    // Header: "PACK" magic, version=2, objectCount=1
    uint8_t header[] = { 'P','A','C','K', 0,0,0,2, 0,0,0,1 };
    [pack appendBytes:header length:sizeof(header)];
    // Object: type=blob (3), size=1, no MSB continuation → byte 0x31
    uint8_t objHeader = 0x31;
    [pack appendBytes:&objHeader length:1];
    // Corrupted zlib data (not a valid zlib stream)
    uint8_t garbage[] = { 0xFF, 0xFE, 0xFD, 0xFC };
    [pack appendBytes:garbage length:sizeof(garbage)];
    // 20-byte trailer (checksum placeholder)
    [pack appendData:[NSMutableData dataWithLength:20]];

    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:pack];
    XCTAssertNotNil(decoder);
    XCTAssertNil([decoder objectAtOffset:12]);
}

- (void)testApplyDelta_zeroByte_returnsNil {
    // Build a decoder to call the internal method on.
    NSData *packData = SSBGitDecoderFixtureData(@"delta-ref.pack");
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];
    // base has 5 bytes
    NSData *base = [NSData dataWithBytes:"\x01\x02\x03\x04\x05" length:5];
    // delta: sourceSize=5 (varint 0x05), targetSize=5 (0x05), command=0x00 (invalid → nil)
    uint8_t deltaBytes[] = { 0x05, 0x05, 0x00 };
    NSData *delta = [NSData dataWithBytes:deltaBytes length:sizeof(deltaBytes)];
    XCTAssertNil([decoder applyDelta:delta toBase:base]);
}

- (void)testRefDeltaRequiresObjectStoreAndResolvesWithRegisteredFixturePack {
    NSDictionary<NSString *, NSString *> *manifest = SSBGitDecoderManifest();
    NSData *packData = SSBGitDecoderFixtureData(@"delta-ref.pack");
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:SSBGitDecoderFixtureData(@"delta-ref.idx")];
    uint64_t offset = [parser offsetForHexString:manifest[@"blob_file2_updated"]];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:packData];

    XCTAssertEqual(SSBGitObjectTypeAtPackOffset(packData, offset), SSBGitObjectTypeRefDelta);
    XCTAssertNil([decoder objectAtOffset:offset]);

    SSBBlobStore *blobStore = nil;
    SSBGitObjectStore *objectStore = SSBGitObjectStoreWithFixturePack(@"delta-ref.pack", @"delta-ref.idx", &blobStore);
    decoder.objectStore = objectStore;
    SSBGitObject *blob = [decoder objectAtOffset:offset];

    XCTAssertEqual(blob.type, SSBGitObjectTypeBlob);
    XCTAssertEqualObjects(blob.data, SSBGitExpectedFixtureBlob(300));
    [blobStore wipeBlobs];
}

@end
