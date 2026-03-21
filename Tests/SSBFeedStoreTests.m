#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBFeedCodecRegistry.h>
#import "SSBLogger.h"

@interface SSBFeedStoreTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *store;
@property (nonatomic, copy) NSString *dbPath;
@end

@interface MockFeedCodec : NSObject <SSBFeedCodec>
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end

@implementation MockFeedCodec
- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error { return YES; }
- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error { return [@"%mockkey.sha256" dataUsingEncoding:NSUTF8StringEncoding]; }
- (SSBBFEMessageFormat)messageFormat { return SSBBFEMessageFormatClassic; }
@end

@implementation SSBFeedStoreTests

- (void)setUp {
    [super setUp];
    NSString *tmp = NSTemporaryDirectory();
    self.dbPath = [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"test_feedstore_main_%@.db", [[NSUUID UUID] UUIDString]]];
    self.store = [[SSBFeedStore alloc] initWithPath:self.dbPath];
    [self.store wipeDatabase];
    
    MockFeedCodec *classicCodec = [[MockFeedCodec alloc] init];
    classicCodec.feedFormat = SSBBFEFeedFormatClassic;
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:classicCodec];

    MockFeedCodec *bambooCodec = [[MockFeedCodec alloc] init];
    bambooCodec.feedFormat = SSBBFEFeedFormatBamboo;
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:bambooCodec];
}

- (void)tearDown {
    [self.store wipeDatabase];
    self.store = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Following Tests

- (void)testIsFollowingDefault {
    NSString *testAuthor = @"testAuthor123";
    
    BOOL isFollowing = [self.store isFollowing:testAuthor];
    XCTAssertFalse(isFollowing, "New author should not be following");
}

- (void)testSetAndIsFollowing {
    NSString *testAuthor = @"testAuthorFollow";
    
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:1];
    
    XCTAssertTrue([self.store isFollowing:testAuthor], "Author should be marked as following");
    
    [self.store setFollowing:NO forAuthor:testAuthor atSequence:2];
    
    XCTAssertFalse([self.store isFollowing:testAuthor], "Author should not be marked as following");
}

- (void)testFollowingSequenceUpdate {
    NSString *testAuthor = @"testAuthorSeq";
    
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:5];
    XCTAssertTrue([self.store isFollowing:testAuthor], "Following state should update for contact rows");
}

#pragma mark - Blocking Tests

- (void)testIsBlockedDefault {
    NSString *testAuthor = @"testAuthorBlocked";
    
    BOOL isBlocked = [self.store isBlocked:testAuthor];
    XCTAssertFalse(isBlocked, "New author should not be blocked");
}

- (void)testSetAndIsBlocked {
    NSString *testAuthor = @"testAuthorBlock";
    
    [self.store setBlocked:YES forAuthor:testAuthor atSequence:1];
    
    XCTAssertTrue([self.store isBlocked:testAuthor], "Author should be marked as blocked");
    
    [self.store setBlocked:NO forAuthor:testAuthor atSequence:2];
    
    XCTAssertFalse([self.store isBlocked:testAuthor], "Author should not be blocked");
}

- (void)testBlockAndFollowIndependence {
    NSString *testAuthor = @"testAuthorBoth";
    
    [self.store setBlocked:YES forAuthor:testAuthor atSequence:1];
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:2];
    
    XCTAssertTrue([self.store isBlocked:testAuthor], "Author should be blocked");
    XCTAssertTrue([self.store isFollowing:testAuthor], "Author should also be following (can follow someone before blocking)");
}

#pragma mark - Display Name Tests

- (void)testSetDisplayName {
    NSString *testAuthor = @"testAuthorName";
    NSString *testName = @"Test Display Name";
    
    [self.store setDisplayName:testName image:nil forAuthor:testAuthor];
    XCTAssertEqualObjects([self.store displayNameForAuthor:testAuthor], testName, "Display name should persist in profiles table");
}

#pragma mark - Feed State Tests

- (void)testFeedStateForUnknownAuthor {
    NSString *unknownAuthor = @"unknownAuthor123456";
    
    SSBFeedState *state = [self.store feedStateForAuthor:unknownAuthor];
    
    XCTAssertNil(state, "Unknown author should have no feed state");
}

- (void)testLocalClock {
    NSDictionary *clock = [self.store localClock];
    
    XCTAssertNotNil(clock, "Local clock should not be nil");
    XCTAssert([clock isKindOfClass:[NSDictionary class]], "Local clock should be a dictionary");
}

#pragma mark - Quarantine Tests

- (void)testQuarantineWithTangles {
    SSBMessage *missingPrev = [[SSBMessage alloc] init];
    missingPrev.author = @"@test.ed25519";
    missingPrev.sequence = 2;
    missingPrev.key = @"%testMsg2.sha256";
    missingPrev.previousKey = @"%testMsg1.sha256";
    missingPrev.contentType = @"post";
    missingPrev.content = @{ @"type": @"post", @"text": @"hello", @"tangles": @{
        @"thread": @{ @"root": [NSNull null], @"previous": @[ @"%thread1.sha256" ] }
    }};
    missingPrev.valueJSON = [NSJSONSerialization dataWithJSONObject:missingPrev.content options:0 error:nil];
    
    // Add out of order, it should go to quarantine and look at tangles
    [self.store appendMessage:missingPrev error:nil];
    
    // Check missing deps logic
    // We can't access missing deps directly but we can verify it was quarantined
    SSBFeedState *state = [self.store feedStateForAuthor:@"@test.ed25519"];
    XCTAssertNil(state);
}

#pragma mark - Bamboo and Format Tests

- (void)testMessagesForFeedFormat {
    SSBMessage *bambooMsg = [[SSBMessage alloc] init];
    bambooMsg.author = @"@bamboo123.ed25519";
    bambooMsg.sequence = 1;
    bambooMsg.key = @"%bambookey.sha256";
    bambooMsg.contentType = @"post";
    bambooMsg.content = @{ @"type": @"post" };
    bambooMsg.valueJSON = [NSData dataWithBytes:"bamboodata" length:10];
    bambooMsg.feedFormat = SSBBFEFeedFormatBamboo;
    
    [self.store appendMessage:bambooMsg error:nil];
    
    NSArray *bambooMsgs = [self.store messagesForFeedFormat:SSBBFEFeedFormatBamboo limit:10];
    XCTAssertEqual(bambooMsgs.count, 1);
    
    SSBBambooProof *proof = [self.store generateBambooProofForAuthor:@"@bamboo123.ed25519" sequence:1];
    XCTAssertNotNil(proof);
    
    // Test lipmaaMessageForAuthor
    SSBMessage *lipmaa = [self.store lipmaaMessageForAuthor:@"@bamboo123.ed25519" sequence:1 format:SSBBFEFeedFormatBamboo];
    XCTAssertNil(lipmaa); // Root has no lipmaa
}

- (void)testTombstone {
    SSBMessage *tombstone = [[SSBMessage alloc] init];
    tombstone.author = @"@meta.ed25519";
    tombstone.sequence = 1;
    tombstone.key = @"%tombstone.sha256";
    tombstone.contentType = @"metafeed/tombstone";
    tombstone.content = @{ @"type": @"metafeed/tombstone", @"subfeed": @"ssb:feed/bendybutt-v1/tombstoned-subfeed" };
    tombstone.valueJSON = [NSJSONSerialization dataWithJSONObject:tombstone.content options:0 error:nil];
    
    NSError *error = nil;
    BOOL ok = [self.store appendMessage:tombstone error:&error];
    XCTAssertTrue(ok, @"Tombstone append failed: %@", error);
    
    XCTAssertTrue([self.store isTombstoned:@"ssb:feed/bendybutt-v1/tombstoned-subfeed"]);
    XCTAssertFalse([self.store isTombstoned:@"ssb:feed/bendybutt-v1/alive-subfeed"]);
}

- (void)testDeviceFeedIDs {
    SSBMessage *addDerived = [[SSBMessage alloc] init];
    addDerived.author = @"@meta.ed25519";
    addDerived.sequence = 1; // Use sequence 1 to avoid quarantine in isolated store
    addDerived.key = @"%derived.sha256";
    addDerived.contentType = @"metafeed/add/derived";
    addDerived.content = @{ @"type": @"metafeed/add/derived", @"subfeed": @"ssb:feed/classic/device1" };
    addDerived.valueJSON = [NSJSONSerialization dataWithJSONObject:addDerived.content options:0 error:nil];
    
    NSError *error = nil;
    BOOL ok = [self.store appendMessage:addDerived error:&error];
    XCTAssertTrue(ok, @"Device feed append failed: %@", error);
    
    NSArray *devices = [self.store deviceFeedIDsForMetafeedID:@"@meta.ed25519"];
    XCTAssertEqual(devices.count, 1);
    XCTAssertEqualObjects(devices.firstObject, @"ssb:feed/classic/device1");
}

- (void)testStorageStatistics {
    NSDictionary *stats = [self.store storageStatistics];
    XCTAssertNotNil(stats);
    XCTAssert([stats isKindOfClass:[NSDictionary class]]);
}

@end
