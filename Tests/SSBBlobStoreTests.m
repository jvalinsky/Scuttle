#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBCommonCryptoCompat.h>
#import <SSBNetwork/SSBMuxRPCSession.h>

@interface MockMuxRPCSession : SSBMuxRPCSession
@property (nonatomic, copy) void (^sendRequestBlock)(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error));
@end

@implementation MockMuxRPCSession
- (void)sendRequest:(NSArray *)name args:(NSArray *)args type:(NSString *)type completion:(void (^)(id _Nullable response, NSError * _Nullable error))completion {
    if (self.sendRequestBlock) {
        self.sendRequestBlock(name, args, type, completion);
    }
}
@end

@interface MockEncodingFailString : NSString
@end

@implementation MockEncodingFailString
- (NSUInteger)length { return 4; }
- (unichar)characterAtIndex:(NSUInteger)index { return 'a'; }
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding { return nil; }
@end

/// Computes SHA-256 of data and returns the canonical SSB blob ID: &<base64>.sha256
static NSString *BlobIDForData(NSData *data) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *b64 = [hashData base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"&%@.sha256", b64];
}

@interface SSBBlobStoreTests : XCTestCase
@property (nonatomic, strong) SSBBlobStore *store;
@property (nonatomic, copy) NSString *blobsDir;
@end

// Expose a test-init so we can point at a temp directory instead of the shared store.
@interface SSBBlobStore (TestInit)
- (instancetype)initWithDirectory:(NSString *)directory;
@end

@implementation SSBBlobStoreTests

- (void)setUp {
    [super setUp];
    // Use a unique temp directory per test.
    NSString *tmp = NSTemporaryDirectory();
    self.blobsDir = [tmp stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"test_blobs_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.blobsDir
                                withIntermediateDirectories:YES attributes:nil error:nil];

    // If SSBBlobStore provides initWithDirectory:, use it; otherwise fall back to sharedStore.
    if ([SSBBlobStore instancesRespondToSelector:@selector(initWithDirectory:)]) {
        self.store = [[SSBBlobStore alloc] initWithDirectory:self.blobsDir];
    } else {
        // Shared store – wipe before and after to avoid cross-test contamination.
        self.store = [SSBBlobStore sharedStore];
        [self.store wipeBlobs];
    }
    XCTAssertNotNil(self.store);
}

- (void)tearDown {
    [self.store wipeBlobs];
    [[NSFileManager defaultManager] removeItemAtPath:self.blobsDir error:nil];
    [super tearDown];
}

#pragma mark - storeBlob:forBlobID:

- (void)testStoreBlob_validHash_returnsLocalPath {
    NSData *data = [@"hello blob" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);

    NSString *path = [self.store storeBlob:data forBlobID:blobId];
    XCTAssertNotNil(path, @"storeBlob: must return a path on valid hash");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path],
                  @"Blob file must exist on disk");
}

- (void)testStoreBlob_hashMismatch_returnsNil {
    NSData *data = [@"some bytes" dataUsingEncoding:NSUTF8StringEncoding];
    // A blob ID whose hash does NOT match the data
    NSString *wrongId = @"&AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=.sha256";

    NSString *path = [self.store storeBlob:data forBlobID:wrongId];
    XCTAssertNil(path, @"storeBlob: must return nil when the hash does not match");
}

- (void)testStoreBlob_idempotent {
    NSData *data = [@"idempotent blob" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);

    NSString *path1 = [self.store storeBlob:data forBlobID:blobId];
    NSString *path2 = [self.store storeBlob:data forBlobID:blobId];
    XCTAssertEqualObjects(path1, path2, @"Storing the same blob twice must return the same path");
}

#pragma mark - hasBlob:

- (void)testHasBlob_notStored_returnsNo {
    XCTAssertFalse([self.store hasBlob:@"&AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=.sha256"]);
}

- (void)testHasBlob_afterStore_returnsYes {
    NSData *data = [@"blobexists" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);
    [self.store storeBlob:data forBlobID:blobId];

    XCTAssertTrue([self.store hasBlob:blobId]);
}

#pragma mark - localPathForBlobID:

- (void)testLocalPath_notStored_returnsNil {
    NSString *path = [self.store localPathForBlobID:@"&nothere.sha256"];
    XCTAssertNil(path);
}

- (void)testLocalPath_afterStore_returnsPath {
    NSData *data = [@"path test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);
    [self.store storeBlob:data forBlobID:blobId];

    NSString *path = [self.store localPathForBlobID:blobId];
    XCTAssertNotNil(path);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
}

#pragma mark - totalStorageSize

- (void)testTotalStorageSize_zero_whenEmpty {
    NSUInteger size = [self.store totalStorageSize];
    XCTAssertEqual(size, 0);
}

- (void)testTotalStorageSize_increasesAfterStore {
    NSData *data = [@"size test content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);
    [self.store storeBlob:data forBlobID:blobId];

    NSUInteger size = [self.store totalStorageSize];
    XCTAssertGreaterThan(size, 0);
}

- (void)testTotalStorageSize_matchesStoredDataLength {
    NSData *data = [@"exactly this many bytes" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);
    [self.store storeBlob:data forBlobID:blobId];

    NSUInteger size = [self.store totalStorageSize];
    XCTAssertEqual(size, data.length);
}

#pragma mark - wipeBlobs

- (void)testWipeBlobs_removesAllBlobs {
    NSData *data = [@"will be wiped" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(data);
    [self.store storeBlob:data forBlobID:blobId];

    [self.store wipeBlobs];

    XCTAssertFalse([self.store hasBlob:blobId]);
    XCTAssertEqual([self.store totalStorageSize], (NSUInteger)0);
}

#pragma mark - blobsDirectory

- (void)testBlobsDirectory_returnsNonNilPath {
    NSString *dir = [self.store blobsDirectory];
    XCTAssertNotNil(dir);
    XCTAssertGreaterThan(dir.length, 0);
}

#pragma mark - fetchBlob:session:completion:

- (void)testFetchBlob_success {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Fetch completion"];
    NSData *chunk1 = [@"mock blob " dataUsingEncoding:NSUTF8StringEncoding];
    NSString *chunk2 = @"content";
    
    NSMutableData *fullData = [NSMutableData dataWithData:chunk1];
    [fullData appendData:[chunk2 dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *blobId = BlobIDForData(fullData);
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        XCTAssertEqualObjects(name, (@[@"blobs", @"get"]));
        XCTAssertEqualObjects(args, @[blobId]);
        XCTAssertEqualObjects(type, @"source");
        
        completion(chunk1, nil); // NSData chunk
        completion(chunk2, nil); // NSString chunk
        completion(@[@"fallback"], nil); // Fallback chunk
        completion(nil, nil);     // End of stream
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNotNil(path);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertTrue([self.store hasBlob:blobId]);
}

- (void)testFetchBlob_failure {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Fetch completion"];
    NSString *blobId = @"&AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=.sha256";
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        NSError *error = [NSError errorWithDomain:@"SSBMuxRPCSession" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Network error"}];
        completion(nil, error);
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNil(path);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testFetchBlob_hashMismatch {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Fetch completion"];
    NSString *blobId = @"&wronghashwronghashwronghashwronghash.sha256";
    NSData *badData = [@"bad data" dataUsingEncoding:NSUTF8StringEncoding];
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        completion(badData, nil); // Send bad chunk
        completion(nil, nil);     // End of stream
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNil(path);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, @"SSBBlobStore");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testFetchBlob_alreadyExists {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Fetch completion"];
    NSData *blobData = [@"existing blob content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(blobData);
    
    [self.store storeBlob:blobData forBlobID:blobId];
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        XCTFail(@"sendRequest should not be called if blob already exists");
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNotNil(path);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testFetchBlob_multipleConcurrent {
    XCTestExpectation *expect1 = [self expectationWithDescription:@"Fetch 1 completion"];
    XCTestExpectation *expect2 = [self expectationWithDescription:@"Fetch 2 completion"];
    NSData *blobData = [@"concurrent content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(blobData);
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    __block void (^holdCompletion)(id _Nullable response, NSError * _Nullable error) = nil;
    
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        holdCompletion = completion;
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNotNil(path);
        [expect1 fulfill];
    }];
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNotNil(path);
        [expect2 fulfill];
    }];
    
    XCTAssertNotNil(holdCompletion);
    holdCompletion(blobData, nil);
    holdCompletion(nil, nil);
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testFetchBlob_encodingFail {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Fetch completion"];
    NSData *blobData = [@"aaaa" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *blobId = BlobIDForData(blobData);
    
    MockMuxRPCSession *mockSession = [[MockMuxRPCSession alloc] init];
    mockSession.sendRequestBlock = ^(NSArray *name, NSArray *args, NSString *type, void (^completion)(id _Nullable response, NSError * _Nullable error)) {
        MockEncodingFailString *badString = [[MockEncodingFailString alloc] init];
        completion(badString, nil); // Should skip appending data
        completion(nil, nil);        // End of stream
    };
    
    [self.store fetchBlob:blobId session:mockSession completion:^(NSString *path, NSError *error) {
        XCTAssertNil(path);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
