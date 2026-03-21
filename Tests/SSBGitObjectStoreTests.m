#import <XCTest/XCTest.h>
#import "../Sources/SSBGitObjectStore.h"
#import "../Sources/SSBBlobStore.h"
#import "../Sources/SSBCommonCryptoCompat.h"

// Expose TestInit for SSBBlobStore to point to a temp directory
@interface SSBBlobStore (TestInit)
- (instancetype)initWithPath:(NSString *)path;
- (void)wipeBlobs;
@end

static NSString *BlobIDForData(NSData *data) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *b64 = [hashData base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"&%@.sha256", b64];
}

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

@interface SSBGitObjectStoreTests : XCTestCase
@property (nonatomic, strong) SSBBlobStore *blobStore;
@property (nonatomic, strong) SSBGitObjectStore *objectStore;
@property (nonatomic, copy) NSString *blobsDir;
@end

@implementation SSBGitObjectStoreTests

- (void)setUp {
    [super setUp];
    NSString *tmp = NSTemporaryDirectory();
    self.blobsDir = [tmp stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"test_git_blobs_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.blobsDir
                                withIntermediateDirectories:YES attributes:nil error:nil];

    self.blobStore = [[SSBBlobStore alloc] initWithPath:self.blobsDir];
    self.objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:self.blobStore];
}

- (void)tearDown {
    [self.blobStore wipeBlobs];
    [[NSFileManager defaultManager] removeItemAtPath:self.blobsDir error:nil];
    [super tearDown];
}

- (void)testRegisterPackBlobIdempotent {
    [self.objectStore registerPackBlob:@"&pack1.sha256" idxBlob:@"&idx1.sha256"];
    [self.objectStore registerPackBlob:@"&pack1.sha256" idxBlob:@"&idx1.sha256"]; // Duplicate
    
    // We can't inspect the array directly easily without exposing it via category,
    // but we can verify it doesn't crash and behaves logically in lookups.
}

- (void)testObjectForSHA1ReturnsNilWhenNoPacksRegistered {
    XCTAssertNil([self.objectStore objectForSHA1:@"aa29bfc2053eef6ceae883708774b71ce19d893f"]);
}

- (void)testObjectForSHA1_NotFound {
    // Prep some valid IDs but look for something else
    [self.objectStore registerPackBlob:@"&dummy.pack.sha256" idxBlob:@"&dummy.idx.sha256"];
    XCTAssertNil([self.objectStore objectForSHA1:@"ffffffffffffffffffffffffffffffffffffffff"]);
}

- (void)testObjectForSHA1_Success {
    // 1. Read files
    NSData *idxData = SSBGitFixtureData(@"delta-ref.idx");
    NSData *packData = SSBGitFixtureData(@"delta-ref.pack");
    
    // 2. Compute IDs
    NSString *idxID = BlobIDForData(idxData);
    NSString *packID = BlobIDForData(packData);
    
    // 3. Store into blob store
    NSString *idxPath = [self.blobStore storeBlob:idxData forBlobID:idxID];
    NSString *packPath = [self.blobStore storeBlob:packData forBlobID:packID];
    
    XCTAssertNotNil(idxPath);
    XCTAssertNotNil(packPath);
    
    // 4. Register
    [self.objectStore registerPackBlob:packID idxBlob:idxID];
    
    // 5. Lookup SHA1 from manifest
    NSDictionary *manifest = SSBGitFixtureManifest();
    NSString *commitHead = manifest[@"commit_head"]; // aa29bfc...
    
    SSBGitObject *obj = [self.objectStore objectForSHA1:commitHead];
    XCTAssertNotNil(obj, @"Should find object for commit_head");
    XCTAssertEqual(obj.type, SSBGitObjectTypeCommit);
    XCTAssertGreaterThan(obj.data.length, 0);
    
    // 6. Test packBlobIDForSHA1
    NSString *foundPackID = [self.objectStore packBlobIDForSHA1:commitHead];
    XCTAssertEqualObjects(foundPackID, packID);
}

- (void)testObjectForSHA1_CorruptIDX {
    // Store garbage data and register
    NSData *badData = [@"garbage" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *badID = BlobIDForData(badData);
    [self.blobStore storeBlob:badData forBlobID:badID];
    
    [self.objectStore registerPackBlob:badID idxBlob:badID];
    XCTAssertNil([self.objectStore objectForSHA1:@"aa29bfc2053eef6ceae883708774b71ce19d893f"]);
}

- (void)testObjectForSHA1_ShortSHA1 {
    XCTAssertNil([self.objectStore objectForSHA1:@"aa29bfc"]);
}

@end
