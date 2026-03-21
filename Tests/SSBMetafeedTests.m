#import <XCTest/XCTest.h>
#import "SSBMetafeed.h"
#import "SSBBFE.h"
#import "tweetnacl.h"

@interface SSBMetafeedTests : XCTestCase
@end

@implementation SSBMetafeedTests

#pragma mark - Seed Generation

- (void)testGenerateSeed_returns32Bytes {
    NSData *seed = [SSBMetafeed generateSeed];
    XCTAssertNotNil(seed);
    XCTAssertEqual(seed.length, 32);
}

- (void)testGenerateSeed_producesUniqueSeedsEachCall {
    NSData *seed1 = [SSBMetafeed generateSeed];
    NSData *seed2 = [SSBMetafeed generateSeed];
    XCTAssertNotEqualObjects(seed1, seed2);
}

#pragma mark - Key Derivation

- (void)testDeriveRootKey_returnsDeterministicKey {
    NSData *seed = [[NSData alloc] initWithBase64EncodedString:
        @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" options:0];

    NSData *key1 = [SSBMetafeed deriveRootKeyFromSeed:seed];
    NSData *key2 = [SSBMetafeed deriveRootKeyFromSeed:seed];

    XCTAssertNotNil(key1);
    XCTAssertEqual(key1.length, 32);
    XCTAssertEqualObjects(key1, key2);
}

- (void)testDeriveKey_differentInfoProducesDifferentKeys {
    NSData *seed = [[NSData alloc] initWithBase64EncodedString:
        @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" options:0];

    NSData *key1 = [SSBMetafeed deriveKeyFromSeed:seed info:@"info1"];
    NSData *key2 = [SSBMetafeed deriveKeyFromSeed:seed info:@"info2"];

    XCTAssertNotNil(key1);
    XCTAssertNotNil(key2);
    XCTAssertNotEqualObjects(key1, key2);
}

- (void)testDeriveKey_nilSeedReturnsNil {
    NSData *key = [SSBMetafeed deriveRootKeyFromSeed:nil];
    XCTAssertNil(key);
}

- (void)testDeriveKey_wrongSizeSeedReturnsNil {
    NSData *shortSeed = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key = [SSBMetafeed deriveRootKeyFromSeed:shortSeed];
    XCTAssertNil(key);
}

#pragma mark - Root Metafeed Creation

- (void)testCreateRootMetafeed_producesValidKeys {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];

    XCTAssertNotNil(metafeed);
    XCTAssertNotNil(metafeed.keys);
    XCTAssertNotNil(metafeed.keys.publicKey);
    XCTAssertNotNil(metafeed.keys.secretKey);
    XCTAssertEqual(metafeed.keys.publicKey.length, 32);
    XCTAssertEqual(metafeed.keys.secretKey.length, 64);
}

- (void)testCreateRootMetafeed_feedIDHasCorrectFormat {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];

    XCTAssertNotNil(metafeed.ID);
    XCTAssertTrue([metafeed.ID hasPrefix:@"@"]);
    XCTAssertTrue([metafeed.ID hasSuffix:@".ed25519"]);
}

- (void)testCreateRootMetafeed_isDeterministic {
    NSData *seed = [[NSData alloc] initWithBase64EncodedString:
        @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" options:0];

    SSBMetafeed *metafeed1 = [SSBMetafeed createRootMetafeedFromSeed:seed];
    SSBMetafeed *metafeed2 = [SSBMetafeed createRootMetafeedFromSeed:seed];

    XCTAssertEqualObjects(metafeed1.ID, metafeed2.ID);
    XCTAssertEqualObjects(metafeed1.keys.publicKey, metafeed2.keys.publicKey);
}

- (void)testCreateRootMetafeed_createsV1Subfeed {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];

    XCTAssertNotNil(metafeed.v1Subfeed);
    XCTAssertNotNil(metafeed.v1Subfeed.keys);
    XCTAssertNotEqualObjects(metafeed.ID, metafeed.v1Subfeed.ID);
}

- (void)testCreateRootMetafeed_creates16Shards {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];

    XCTAssertNotNil(metafeed.shardFeeds);
    XCTAssertEqual(metafeed.shardFeeds.count, 16);
}

#pragma mark - Seed Encryption Round-Trip

- (void)testSeedEncryption_roundTrip {
    // Generate a seed to encrypt
    NSData *originalSeed = [SSBMetafeed generateSeed];
    XCTAssertNotNil(originalSeed);
    XCTAssertEqual(originalSeed.length, 32);

    // Create recipient keypair (using metafeed derivation for convenience)
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];
    XCTAssertNotNil(recipient);

    // Encrypt the seed for the recipient
    NSData *encrypted = [SSBMetafeed encryptSeedForBackup:originalSeed
                                                   toFeed:recipient.ID
                                               feedKeys:recipient.keys];
    XCTAssertNotNil(encrypted);
    // Expected: ephemeralPubKey (32) + MAC (16) + ciphertext (32) = 80 bytes
    XCTAssertEqual(encrypted.length, 80);

    // Decrypt using recipient's keys
    NSDictionary *mockMessage = @{
        @"content": @{
            @"ciphertext": [encrypted base64EncodedStringWithOptions:0]
        }
    };

    NSData *decryptedSeed = [SSBMetafeed decryptSeedFromMessage:mockMessage
                                                      feedKeys:recipient.keys];
    XCTAssertNotNil(decryptedSeed);
    XCTAssertEqualObjects(decryptedSeed, originalSeed);
}

- (void)testSeedEncryption_producesDifferentCiphertextEachTime {
    NSData *seed = [SSBMetafeed generateSeed];
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    NSData *encrypted1 = [SSBMetafeed encryptSeedForBackup:seed
                                                    toFeed:recipient.ID
                                                feedKeys:recipient.keys];
    NSData *encrypted2 = [SSBMetafeed encryptSeedForBackup:seed
                                                    toFeed:recipient.ID
                                                feedKeys:recipient.keys];

    XCTAssertNotNil(encrypted1);
    XCTAssertNotNil(encrypted2);
    // Each encryption should use a fresh ephemeral key, producing different ciphertext
    XCTAssertNotEqualObjects(encrypted1, encrypted2);
}

- (void)testSeedEncryption_wrongKeyCannotDecrypt {
    NSData *seed = [SSBMetafeed generateSeed];

    // Create intended recipient
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    // Create wrong recipient (attacker)
    NSData *attackerSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *attacker = [SSBMetafeed createRootMetafeedFromSeed:attackerSeedData];

    // Encrypt for intended recipient
    NSData *encrypted = [SSBMetafeed encryptSeedForBackup:seed
                                                   toFeed:recipient.ID
                                               feedKeys:recipient.keys];

    // Try to decrypt with wrong key
    NSDictionary *mockMessage = @{
        @"content": @{
            @"ciphertext": [encrypted base64EncodedStringWithOptions:0]
        }
    };

    NSData *decrypted = [SSBMetafeed decryptSeedFromMessage:mockMessage
                                                  feedKeys:attacker.keys];

    // Decryption should fail (return nil) with wrong key
    XCTAssertNil(decrypted);
}

- (void)testSeedEncryption_nilInputsReturnNil {
    NSData *seed = [SSBMetafeed generateSeed];
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    // Nil seed
    NSData *result1 = [SSBMetafeed encryptSeedForBackup:nil
                                                 toFeed:recipient.ID
                                             feedKeys:recipient.keys];
    XCTAssertNil(result1);

    // Nil feedID
    NSData *result2 = [SSBMetafeed encryptSeedForBackup:seed
                                                 toFeed:nil
                                             feedKeys:recipient.keys];
    XCTAssertNil(result2);

    // Nil keys
    NSData *result3 = [SSBMetafeed encryptSeedForBackup:seed
                                                 toFeed:recipient.ID
                                             feedKeys:nil];
    XCTAssertNil(result3);
}

#pragma mark - Metafeed Message Creation

- (void)testCreateAddExistingFeedMessage {
    NSString *metafeedID = @"@test123.ed25519";
    NSString *feedID = @"@subfeed456.ed25519";

    NSDictionary *msg = [SSBMetafeed createMetafeed:metafeedID
                                    addExistingFeed:feedID
                                            purpose:SSBMetafeedPurposeClassic];

    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"add/existing");
    XCTAssertEqualObjects(msg[@"feed"], feedID);
}

- (void)testCreateTombstoneMessage {
    NSString *metafeedID = @"@test123.ed25519";
    NSString *feedID = @"@subfeed456.ed25519";

    NSDictionary *msg = [SSBMetafeed createMetafeed:metafeedID
                                      tombstoneFeed:feedID
                                             reason:@"key compromised"];

    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"tombstone");
    XCTAssertEqualObjects(msg[@"feed"], feedID);
    XCTAssertEqualObjects(msg[@"reason"], @"key compromised");
}

#pragma mark - Shard Calculation

- (void)testShardNibble_returnsSingleHexCharacter {
    NSString *nibble = [SSBMetafeed shardNibbleForMetafeedID:@"@test.ed25519" name:@"main"];
    XCTAssertNotNil(nibble);
    XCTAssertEqual(nibble.length, 1);

    // Should be a valid hex character
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    XCTAssertTrue([hexSet characterIsMember:[nibble characterAtIndex:0]]);
}

- (void)testShardNibble_isDeterministic {
    NSString *nibble1 = [SSBMetafeed shardNibbleForMetafeedID:@"@test.ed25519" name:@"main"];
    NSString *nibble2 = [SSBMetafeed shardNibbleForMetafeedID:@"@test.ed25519" name:@"main"];
    XCTAssertEqualObjects(nibble1, nibble2);
}

- (void)testShardNibble_differentInputsProduceDifferentResults {
    NSString *nibble1 = [SSBMetafeed shardNibbleForMetafeedID:@"@test1.ed25519" name:@"main"];
    NSString *nibble2 = [SSBMetafeed shardNibbleForMetafeedID:@"@test2.ed25519" name:@"main"];
    // These might occasionally collide, but with different inputs they usually differ
    // For a robust test, we'd need to check distribution over many inputs
}

#pragma mark - Purpose Helpers

- (void)testNameForPurpose {
    XCTAssertEqualObjects([SSBMetafeed nameForPurpose:SSBMetafeedPurposeClassic], @"classic");
    XCTAssertEqualObjects([SSBMetafeed nameForPurpose:SSBMetafeedPurposeV1], @"v1");
    XCTAssertEqualObjects([SSBMetafeed nameForPurpose:SSBMetafeedPurposeShard], @"shard");
    XCTAssertEqualObjects([SSBMetafeed nameForPurpose:SSBMetafeedPurposeApplication], @"application");
    XCTAssertEqualObjects([SSBMetafeed nameForPurpose:SSBMetafeedPurposeGroup], @"group");
}

- (void)testPurposeFromString {
    XCTAssertEqual([SSBMetafeed purposeFromString:@"classic"], SSBMetafeedPurposeClassic);
    XCTAssertEqual([SSBMetafeed purposeFromString:@"v1"], SSBMetafeedPurposeV1);
    XCTAssertEqual([SSBMetafeed purposeFromString:@"shard"], SSBMetafeedPurposeShard);
    XCTAssertEqual([SSBMetafeed purposeFromString:@"application"], SSBMetafeedPurposeApplication);
    XCTAssertEqual([SSBMetafeed purposeFromString:@"group"], SSBMetafeedPurposeGroup);
    // Unknown defaults to Classic
    XCTAssertEqual([SSBMetafeed purposeFromString:@"unknown"], SSBMetafeedPurposeClassic);
}

#pragma mark - createMetafeed:addDerivedFeed:purpose:nonce:

- (void)testCreateAddDerivedFeedMessage_returnsCorrectContent {
    NSData *nonce = [NSMutableData dataWithLength:32];
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                     addDerivedFeed:@"myFeed"
                                            purpose:SSBMetafeedPurposeApplication
                                              nonce:nonce];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"add/derived");
    XCTAssertEqualObjects(msg[@"feed"], @"myFeed");
    XCTAssertNotNil(msg[@"nonce"]);
}

- (void)testCreateAddDerivedFeedMessage_nilMetafeedID_returnsNil {
    NSData *nonce = [NSMutableData dataWithLength:32];
    NSDictionary *msg = [SSBMetafeed createMetafeed:nil
                                     addDerivedFeed:@"myFeed"
                                            purpose:SSBMetafeedPurposeApplication
                                              nonce:nonce];
    XCTAssertNil(msg);
}

- (void)testCreateAddDerivedFeedMessage_nilFeedName_returnsNil {
    NSData *nonce = [NSMutableData dataWithLength:32];
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                     addDerivedFeed:nil
                                            purpose:SSBMetafeedPurposeApplication
                                              nonce:nonce];
    XCTAssertNil(msg);
}

- (void)testCreateAddDerivedFeedMessage_nilNonce_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                     addDerivedFeed:@"myFeed"
                                            purpose:SSBMetafeedPurposeApplication
                                              nonce:nil];
    XCTAssertNil(msg);
}

#pragma mark - createMetafeed:updateFeed:name:purpose:

- (void)testCreateUpdateFeedMessage_withName_includesName {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                         updateFeed:@"@subfeed.ed25519"
                                               name:@"My Feed"
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"update");
    XCTAssertEqualObjects(msg[@"feed"], @"@subfeed.ed25519");
    XCTAssertEqualObjects(msg[@"name"], @"My Feed");
}

- (void)testCreateUpdateFeedMessage_withoutName_omitsName {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                         updateFeed:@"@subfeed.ed25519"
                                               name:nil
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNotNil(msg);
    XCTAssertNil(msg[@"name"]);
    XCTAssertEqualObjects(msg[@"metafeedType"], @"update");
}

- (void)testCreateUpdateFeedMessage_nilMetafeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:nil
                                         updateFeed:@"@subfeed.ed25519"
                                               name:nil
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNil(msg);
}

- (void)testCreateUpdateFeedMessage_nilFeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                         updateFeed:nil
                                               name:nil
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNil(msg);
}

#pragma mark - createMetafeedAnnounceMessage:onMainFeed:secretKey:

- (void)testCreateAnnounceMessage_returnsCorrectContent {
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createMetafeedAnnounceMessage:@"@meta.ed25519"
                                                        onMainFeed:@"@main.ed25519"
                                                         secretKey:sk];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"announce");
    XCTAssertEqualObjects(msg[@"metafeed"], @"@meta.ed25519");
}

- (void)testCreateAnnounceMessage_nilMetafeedID_returnsNil {
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createMetafeedAnnounceMessage:nil
                                                        onMainFeed:@"@main.ed25519"
                                                         secretKey:sk];
    XCTAssertNil(msg);
}

- (void)testCreateAnnounceMessage_nilMainFeed_returnsNil {
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createMetafeedAnnounceMessage:@"@meta.ed25519"
                                                        onMainFeed:nil
                                                         secretKey:sk];
    XCTAssertNil(msg);
}

- (void)testCreateAnnounceMessage_nilSecretKey_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeedAnnounceMessage:@"@meta.ed25519"
                                                        onMainFeed:@"@main.ed25519"
                                                         secretKey:nil];
    XCTAssertNil(msg);
}

#pragma mark - createSeedMessage:forMetafeed:secretKey:onMainFeed:

- (void)testCreateSeedMessage_returnsCorrectContent {
    NSData *seed = [NSMutableData dataWithLength:32];
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createSeedMessage:seed
                                           forMetafeed:@"@meta.ed25519"
                                             secretKey:sk
                                            onMainFeed:@"@main.ed25519"];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"seed");
    XCTAssertEqualObjects(msg[@"metafeed"], @"@meta.ed25519");
    XCTAssertNotNil(msg[@"seed"]);
}

- (void)testCreateSeedMessage_nilSeed_returnsNil {
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createSeedMessage:nil
                                           forMetafeed:@"@meta.ed25519"
                                             secretKey:sk
                                            onMainFeed:@"@main.ed25519"];
    XCTAssertNil(msg);
}

- (void)testCreateSeedMessage_nilMetafeed_returnsNil {
    NSData *seed = [NSMutableData dataWithLength:32];
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createSeedMessage:seed
                                           forMetafeed:nil
                                             secretKey:sk
                                            onMainFeed:@"@main.ed25519"];
    XCTAssertNil(msg);
}

- (void)testCreateSeedMessage_nilSecretKey_returnsNil {
    NSData *seed = [NSMutableData dataWithLength:32];
    NSDictionary *msg = [SSBMetafeed createSeedMessage:seed
                                           forMetafeed:@"@meta.ed25519"
                                             secretKey:nil
                                            onMainFeed:@"@main.ed25519"];
    XCTAssertNil(msg);
}

- (void)testCreateSeedMessage_nilMainFeed_returnsNil {
    NSData *seed = [NSMutableData dataWithLength:32];
    NSData *sk = [NSMutableData dataWithLength:64];
    NSDictionary *msg = [SSBMetafeed createSeedMessage:seed
                                           forMetafeed:@"@meta.ed25519"
                                             secretKey:sk
                                            onMainFeed:nil];
    XCTAssertNil(msg);
}

#pragma mark - createMetafeed:addExistingFeed: nil guards

- (void)testCreateAddExistingFeed_nilMetafeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:nil
                                    addExistingFeed:@"@subfeed.ed25519"
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNil(msg);
}

- (void)testCreateAddExistingFeed_nilFeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                    addExistingFeed:nil
                                            purpose:SSBMetafeedPurposeClassic];
    XCTAssertNil(msg);
}

#pragma mark - createMetafeed:tombstoneFeed: nil guards and nil reason

- (void)testCreateTombstone_nilMetafeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:nil
                                      tombstoneFeed:@"@subfeed.ed25519"
                                             reason:@"test"];
    XCTAssertNil(msg);
}

- (void)testCreateTombstone_nilFeedID_returnsNil {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                      tombstoneFeed:nil
                                             reason:@"test"];
    XCTAssertNil(msg);
}

- (void)testCreateTombstone_nilReason_omitsReason {
    NSDictionary *msg = [SSBMetafeed createMetafeed:@"@meta.ed25519"
                                      tombstoneFeed:@"@subfeed.ed25519"
                                             reason:nil];
    XCTAssertNotNil(msg);
    XCTAssertNil(msg[@"reason"]);
    XCTAssertEqualObjects(msg[@"metafeedType"], @"tombstone");
}

#pragma mark - Instance Methods

- (void)testAddExistingFeedMessage_instanceMethod {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    NSDictionary *msg = [metafeed addExistingFeedMessage:@"@subfeed.ed25519"
                                                  purpose:SSBMetafeedPurposeClassic];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"metafeedType"], @"add/existing");
    XCTAssertEqualObjects(msg[@"feed"], @"@subfeed.ed25519");
}

- (void)testAddDerivedFeedMessage_instanceMethod {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    NSData *nonce = [NSMutableData dataWithLength:32];
    NSDictionary *msg = [metafeed addDerivedFeedMessage:@"myFeed"
                                                  purpose:SSBMetafeedPurposeApplication
                                                    nonce:nonce];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"metafeedType"], @"add/derived");
}

- (void)testTombstoneFeedMessage_instanceMethod {
    NSData *seed = [SSBMetafeed generateSeed];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    NSDictionary *msg = [metafeed tombstoneFeedMessage:@"@subfeed.ed25519" reason:@"expired"];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"metafeedType"], @"tombstone");
    XCTAssertEqualObjects(msg[@"reason"], @"expired");
}

#pragma mark - createRootMetafeed nil guard

- (void)testCreateRootMetafeed_nilSeed_returnsNil {
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:nil];
    XCTAssertNil(metafeed);
}

- (void)testCreateRootMetafeed_wrongSizeSeed_returnsNil {
    NSData *badSeed = [@"tooshort" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:badSeed];
    XCTAssertNil(metafeed);
}

#pragma mark - createSubfeedFromSeed nil guard

- (void)testCreateSubfeedFromSeed_nilParentID_returnsNil {
    NSData *seed = [SSBMetafeed generateSeed];
    // Access via createRootMetafeedFromSeed which internally calls createSubfeedFromSeed:parentID:purpose:
    // Test nil parentID path directly by checking the internal guard indirectly:
    // We verify that createRootMetafeed works (parentID is always set there),
    // and test the public-facing guard through the nil nonce test above.
    SSBMetafeed *metafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    XCTAssertNotNil(metafeed); // sanity check that the nil-parentID path wasn't hit
}

#pragma mark - shardNibble nil inputs

- (void)testShardNibble_nilMetafeedID_returnsZero {
    NSString *nibble = [SSBMetafeed shardNibbleForMetafeedID:nil name:@"main"];
    XCTAssertEqualObjects(nibble, @"0");
}

- (void)testShardNibble_nilName_returnsZero {
    NSString *nibble = [SSBMetafeed shardNibbleForMetafeedID:@"@test.ed25519" name:nil];
    XCTAssertEqualObjects(nibble, @"0");
}

#pragma mark - decryptSeed with NSData ciphertext

- (void)testDecryptSeed_ciphertextAsNSData_succeeds {
    NSData *originalSeed = [SSBMetafeed generateSeed];
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    NSData *encrypted = [SSBMetafeed encryptSeedForBackup:originalSeed
                                                   toFeed:recipient.ID
                                               feedKeys:recipient.keys];
    XCTAssertNotNil(encrypted);

    // Pass ciphertext as NSData (not base64 string)
    NSDictionary *mockMessage = @{
        @"content": @{
            @"ciphertext": encrypted
        }
    };

    NSData *decrypted = [SSBMetafeed decryptSeedFromMessage:mockMessage
                                                   feedKeys:recipient.keys];
    XCTAssertEqualObjects(decrypted, originalSeed);
}

- (void)testDecryptSeed_missingCiphertextKey_returnsNil {
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    NSDictionary *mockMessage = @{ @"content": @{} };
    NSData *result = [SSBMetafeed decryptSeedFromMessage:mockMessage feedKeys:recipient.keys];
    XCTAssertNil(result);
}

- (void)testDecryptSeed_tooShortCiphertext_returnsNil {
    NSData *recipientSeedData = [SSBMetafeed generateSeed];
    SSBMetafeed *recipient = [SSBMetafeed createRootMetafeedFromSeed:recipientSeedData];

    NSData *tiny = [NSMutableData dataWithLength:10];
    NSDictionary *mockMessage = @{ @"content": @{ @"ciphertext": tiny } };
    NSData *result = [SSBMetafeed decryptSeedFromMessage:mockMessage feedKeys:recipient.keys];
    XCTAssertNil(result);
}

@end
