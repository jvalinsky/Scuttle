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
