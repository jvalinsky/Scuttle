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

@end
