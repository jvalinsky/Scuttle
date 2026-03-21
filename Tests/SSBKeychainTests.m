#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBKeychain.h>
#import "SSBSecretStore.h"

@interface SSBKeychainTests : XCTestCase
@end

@implementation SSBKeychainTests

- (void)tearDown {
    // Best-effort cleanup of any values written during tests.
    [SSBKeychain deleteNetworkKey];
    [SSBKeychain deleteMetafeedSeed];
    [SSBKeychain deleteMetafeedRootID];
    [SSBKeychain deleteMetafeedAnnounced];
    [super tearDown];
}

#pragma mark - Identity secret

- (void)testIdentitySecretRoundTrip {
    NSData *secret = [NSMutableData dataWithLength:64];
    BOOL saved = [SSBKeychain saveIdentitySecret:secret];
    if (!saved) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    NSData *loaded = [SSBKeychain loadIdentitySecret];
    XCTAssertEqualObjects(loaded, secret);
    XCTAssertTrue([SSBKeychain deleteIdentitySecret]);
    XCTAssertNil([SSBKeychain loadIdentitySecret]);
}

#pragma mark - Network key

- (void)testNetworkKeyRoundTrip {
    NSData *netKey = [NSMutableData dataWithLength:32];
    BOOL saved = [SSBKeychain saveNetworkKey:netKey];
    if (!saved) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    NSData *loaded = [SSBKeychain loadNetworkKey];
    XCTAssertEqualObjects(loaded, netKey);
    XCTAssertTrue([SSBKeychain deleteNetworkKey]);
    XCTAssertNil([SSBKeychain loadNetworkKey]);
}

#pragma mark - Published message count

- (void)testPublishedMessageCount_default_returnsNonNegative {
    NSInteger count = [SSBKeychain loadPublishedMessageCount];
    XCTAssertGreaterThanOrEqual(count, 0);
}

- (void)testPublishedMessageCount_saveAndLoad {
    BOOL ok = [SSBKeychain savePublishedMessageCount:99];
    if (!ok) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    NSInteger count = [SSBKeychain loadPublishedMessageCount];
    XCTAssertEqual(count, 99);
    [SSBKeychain savePublishedMessageCount:0];
}

#pragma mark - clearAll

- (void)testClearAll_doesNotCrash {
    XCTAssertNoThrow([SSBKeychain clearAll]);
}

#pragma mark - Metafeed seed

- (void)testMetafeedSeedRoundTrip {
    NSData *seed = [NSMutableData dataWithLength:32];
    BOOL saved = [SSBKeychain saveMetafeedSeed:seed];
    if (!saved) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    XCTAssertEqualObjects([SSBKeychain loadMetafeedSeed], seed);
    XCTAssertTrue([SSBKeychain deleteMetafeedSeed]);
    XCTAssertNil([SSBKeychain loadMetafeedSeed]);
}

#pragma mark - Metafeed root ID

- (void)testMetafeedRootIDRoundTrip {
    NSString *rootID = @"@testroot.bbfeed-v1";
    BOOL ok = [SSBKeychain saveMetafeedRootID:rootID];
    if (!ok) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    XCTAssertEqualObjects([SSBKeychain loadMetafeedRootID], rootID);
    XCTAssertTrue([SSBKeychain deleteMetafeedRootID]);
    XCTAssertNil([SSBKeychain loadMetafeedRootID]);
}

#pragma mark - Metafeed announced

- (void)testMetafeedAnnounced_saveAndLoad {
    BOOL ok = [SSBKeychain saveMetafeedAnnounced:YES];
    if (!ok) { XCTSkip(@"Secret store writes unavailable in this environment"); }
    XCTAssertTrue([SSBKeychain loadMetafeedAnnounced]);
    XCTAssertTrue([SSBKeychain deleteMetafeedAnnounced]);
    XCTAssertFalse([SSBKeychain loadMetafeedAnnounced]);
}

#pragma mark - publicIDFromSecret

- (void)testPublicIDFromSecret_shortInput_returnsNil {
    XCTAssertNil([SSBKeychain publicIDFromSecret:[@"short" dataUsingEncoding:NSUTF8StringEncoding]]);
}

- (void)testPublicIDFromSecret_validLength_returnsAtPrefixedID {
    NSData *secret = [NSMutableData dataWithLength:64];
    NSString *pubID = [SSBKeychain publicIDFromSecret:secret];
    XCTAssertNotNil(pubID);
    XCTAssertTrue([pubID hasPrefix:@"@"]);
    XCTAssertTrue([pubID hasSuffix:@".ed25519"]);
}

@end
