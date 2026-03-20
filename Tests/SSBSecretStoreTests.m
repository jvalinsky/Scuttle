#import <XCTest/XCTest.h>
#import "SSBSecretStore.h"

@interface SSBSecretStoreTests : XCTestCase
@end

@implementation SSBSecretStoreTests

- (void)tearDown {
    [super tearDown];
}

- (void)testFileSecretStoreRoundTripsData {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    SSBFileSecretStore *store = [[SSBFileSecretStore alloc] initWithBaseDirectory:tempRoot];

    NSData *payload = [@"secret-payload" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([store saveData:payload forKey:@"identity.secret"]);

    NSData *loaded = [store loadDataForKey:@"identity.secret"];
    XCTAssertEqualObjects(loaded, payload);

    XCTAssertTrue([store deleteDataForKey:@"identity.secret"]);
    XCTAssertNil([store loadDataForKey:@"identity.secret"]);
    XCTAssertTrue([store clearAll]);
}

- (void)testFileSecretStoreWritesPrivatePermissions {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    SSBFileSecretStore *store = [[SSBFileSecretStore alloc] initWithBaseDirectory:tempRoot];

    XCTAssertTrue([store saveData:[@"x" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"permissions.test"]);

    NSString *path = [tempRoot stringByAppendingPathComponent:@"permissions.test"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *permissions = attributes[NSFilePosixPermissions];

    XCTAssertEqual(permissions.unsignedShortValue, (unsigned short)0600);
    XCTAssertTrue([store clearAll]);
}

- (void)testAppleKeychainSecretStoreRoundTripsAndClears {
    SSBAppleKeychainSecretStore *store = [[SSBAppleKeychainSecretStore alloc] init];
    NSString *key = [NSString stringWithFormat:@"coverage.keychain.%@", NSUUID.UUID.UUIDString];
    NSData *payload = [@"keychain-secret" dataUsingEncoding:NSUTF8StringEncoding];

    BOOL saved = [store saveData:payload forKey:key];
    if (!saved) {
        XCTSkip(@"Keychain writes are unavailable in this environment");
    }

    NSData *loaded = [store loadDataForKey:key];
    XCTAssertEqualObjects(loaded, payload);

    XCTAssertTrue([store deleteDataForKey:key]);
}

- (void)testPublicIDFromSecretValidation {
    XCTAssertNil(SSBPublicIDFromSecret([@"short" dataUsingEncoding:NSUTF8StringEncoding]));

    NSMutableData *secret = [NSMutableData dataWithLength:64];
    uint8_t *bytes = secret.mutableBytes;
    for (NSUInteger i = 0; i < 64; i++) {
        bytes[i] = (uint8_t)i;
    }
    NSString *publicID = SSBPublicIDFromSecret(secret);
    XCTAssertTrue([publicID hasPrefix:@"@"]);
    XCTAssertTrue([publicID hasSuffix:@".ed25519"]);
}

- (void)testIdentitySecretWrapperRoundTrip {
    NSData *secret = [[NSUUID UUID].UUIDString dataUsingEncoding:NSUTF8StringEncoding];
    if (!SSBSaveIdentitySecret(secret)) {
        XCTSkip(@"Shared secret store is not writable in this environment");
    }
    XCTAssertEqualObjects(SSBLoadIdentitySecret(), secret);
    XCTAssertTrue(SSBDeleteIdentitySecret());
}

- (void)testPublishedMessageCountWrapperHandlesBinaryAndLegacyString {
    (void)SSBLoadPublishedMessageCount();

    XCTAssertTrue(SSBSavePublishedMessageCount(42));
    XCTAssertEqual(SSBLoadPublishedMessageCount(), 42);

    id<SSBSecretStore> store = SSBSharedSecretStore();
    NSData *legacy = [@"17" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([store saveData:legacy forKey:@"ssb_published_count"]);
    XCTAssertEqual(SSBLoadPublishedMessageCount(), 17);
}

- (void)testMetafeedSeedRootAndAnnouncedWrappers {
    NSData *seed = [[NSUUID UUID].UUIDString dataUsingEncoding:NSUTF8StringEncoding];
    if (!SSBSaveMetafeedSeed(seed)) {
        XCTSkip(@"Shared secret store is not writable in this environment");
    }
    XCTAssertEqualObjects(SSBLoadMetafeedSeed(), seed);
    XCTAssertTrue(SSBDeleteMetafeedSeed());

    NSString *rootID = [NSString stringWithFormat:@"@%@.ed25519", NSUUID.UUID.UUIDString];
    XCTAssertTrue(SSBSaveMetafeedRootID(rootID));
    XCTAssertEqualObjects(SSBLoadMetafeedRootID(), rootID);
    XCTAssertTrue(SSBDeleteMetafeedRootID());

    XCTAssertTrue(SSBSaveMetafeedAnnounced(YES));
    XCTAssertTrue(SSBLoadMetafeedAnnounced());
    XCTAssertTrue(SSBDeleteMetafeedAnnounced());
}

- (void)testCreateDefaultSecretStoreReturnsStore {
    id<SSBSecretStore> store = SSBCreateDefaultSecretStore();
    XCTAssertNotNil(store);
    XCTAssertTrue([store respondsToSelector:@selector(loadDataForKey:)]);
}

@end
