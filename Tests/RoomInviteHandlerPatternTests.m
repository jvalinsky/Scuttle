#import <XCTest/XCTest.h>
#import "RoomInviteHandler.h"

// A valid 32-byte Ed25519 public key in base64 (from the LN7f... fixture).
static NSString * const kPubKeyB64 = @"LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
static NSString * const kToken     = @"myInviteToken123";

@interface RoomInviteHandlerPatternTests : XCTestCase
@end

@implementation RoomInviteHandlerPatternTests

#pragma mark - Pattern 1: host:port:pubkey:token

- (void)testPattern1_valid {
    NSString *invite = [NSString stringWithFormat:@"example.com:8008:%@:%@", kPubKeyB64, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];

    XCTAssertNotNil(config, @"Pattern 1 should parse successfully");
    XCTAssertEqualObjects(config.host, @"example.com");
    XCTAssertEqual(config.port, 8008);
    XCTAssertEqualObjects(config.inviteToken, kToken);
    XCTAssertNotNil(config.serverPubKey);
    XCTAssertEqual(config.serverPubKey.length, 32);
}

- (void)testPattern1_withEdSuffix {
    // pubkey may include the @...ed25519 sigil wrapper
    NSString *wrappedKey = [NSString stringWithFormat:@"@%@.ed25519", kPubKeyB64];
    NSString *invite = [NSString stringWithFormat:@"room.example.com:8008:%@:%@",
                        wrappedKey, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNotNil(config);
    XCTAssertEqualObjects(config.host, @"room.example.com");
}

- (void)testPattern1_leadingAndTrailingWhitespace {
    NSString *invite = [NSString stringWithFormat:@"  example.com:8008:%@:%@  \n", kPubKeyB64, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNotNil(config, @"Whitespace-trimmed invite should parse");
}

- (void)testPattern1_invalidBase64PubKey_returnsNil {
    NSString *invite = @"example.com:8008:!!!not_base64!!!:token";
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Invalid base64 pub key must fail");
}

- (void)testPattern1_zeroPort_returnsNil {
    NSString *invite = [NSString stringWithFormat:@"example.com:0:%@:%@", kPubKeyB64, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Port 0 is invalid and must fail");
}

- (void)testPattern1_missingToken_returnsNil {
    // Only 3 colon-separated parts
    NSString *invite = [NSString stringWithFormat:@"example.com:8008:%@", kPubKeyB64];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Missing token should fail pattern 1");
}

#pragma mark - Pattern 2: ssb:room-invite:token@host:port:pubkey

- (void)testPattern2_valid {
    NSString *invite = [NSString stringWithFormat:@"ssb:room-invite:%@@example.com:8008:%@",
                        kToken, kPubKeyB64];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];

    XCTAssertNotNil(config, @"Pattern 2 should parse successfully");
    XCTAssertEqualObjects(config.host, @"example.com");
    XCTAssertEqual(config.port, 8008);
    XCTAssertEqualObjects(config.inviteToken, kToken);
    XCTAssertNotNil(config.serverPubKey);
}

- (void)testPattern2_invalidBase64PubKey_returnsNil {
    NSString *invite = @"ssb:room-invite:token@example.com:8008:not_valid_b64";
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Invalid base64 key must fail pattern 2");
}

- (void)testPattern2_missingAtSeparator_returnsNil {
    // No '@' separating token from host
    NSString *invite = [NSString stringWithFormat:@"ssb:room-invite:example.com:8008:%@", kPubKeyB64];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Missing @ separator must fail pattern 2");
}

#pragma mark - Pattern 3: net:host:port~shs:pubkey:token (Legacy Multiserver)

- (void)testPattern3_valid {
    NSString *invite = [NSString stringWithFormat:@"net:example.com:8008~shs:%@:%@",
                        kPubKeyB64, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];

    XCTAssertNotNil(config, @"Pattern 3 should parse successfully");
    XCTAssertEqualObjects(config.host, @"example.com");
    XCTAssertEqual(config.port, 8008);
    XCTAssertEqualObjects(config.inviteToken, kToken);
    XCTAssertNotNil(config.serverPubKey);
    XCTAssertEqual(config.serverPubKey.length, 32);
}

- (void)testPattern3_invalidBase64PubKey_returnsNil {
    NSString *invite = @"net:example.com:8008~shs:not_valid_b64:token";
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Invalid base64 pub key must fail pattern 3");
}

- (void)testPattern3_zeroPort_returnsNil {
    NSString *invite = [NSString stringWithFormat:@"net:example.com:0~shs:%@:%@", kPubKeyB64, kToken];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Port 0 is invalid for pattern 3");
}

- (void)testPattern3_missingToken_returnsNil {
    // Only one part after ~shs:
    NSString *invite = [NSString stringWithFormat:@"net:example.com:8008~shs:%@", kPubKeyB64];
    RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
    XCTAssertNil(config, @"Missing token in legacy MSA must fail");
}

#pragma mark - Edge cases

- (void)testCompletelyInvalidString_returnsNil {
    XCTAssertNil([RoomInviteHandler parseInviteCode:@""]);
    XCTAssertNil([RoomInviteHandler parseInviteCode:@"not-an-invite"]);
    XCTAssertNil([RoomInviteHandler parseInviteCode:@"https://example.com/invite"]);
}

#pragma mark - RoomConfig NSSecureCoding

- (void)testRoomConfig_secureCodingRoundTrip {
    NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:kPubKeyB64 options:0];
    RoomConfig *original = [[RoomConfig alloc] initWithHost:@"room.test" port:8008 pubKey:pubKeyData];
    original.name = @"Test Room";
    original.inviteToken = kToken;
    original.usedHTTPInvite = YES;
    original.httpInviteClaimIdentity = @"@me.ed25519";

    NSError *err = nil;
    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:original
                                            requiringSecureCoding:YES
                                                            error:&err];
    XCTAssertNotNil(archived, @"Archiving should succeed: %@", err);

    RoomConfig *restored = [NSKeyedUnarchiver unarchivedObjectOfClass:[RoomConfig class]
                                                             fromData:archived
                                                                error:&err];
    XCTAssertNotNil(restored, @"Unarchiving should succeed: %@", err);
    XCTAssertEqualObjects(restored.host, original.host);
    XCTAssertEqual(restored.port, original.port);
    XCTAssertEqualObjects(restored.name, original.name);
    XCTAssertEqualObjects(restored.inviteToken, original.inviteToken);
    XCTAssertTrue(restored.usedHTTPInvite);
    XCTAssertEqualObjects(restored.httpInviteClaimIdentity, original.httpInviteClaimIdentity);
    XCTAssertEqualObjects(restored.serverPubKey, original.serverPubKey);
}

- (void)testRoomConfig_defaultName_isHost {
    NSData *pk = [[NSData alloc] initWithBase64EncodedString:kPubKeyB64 options:0];
    RoomConfig *config = [[RoomConfig alloc] initWithHost:@"default.host" port:8008 pubKey:pk];
    XCTAssertEqualObjects(config.name, @"default.host", @"Default name should equal host");
}

- (void)testRoomConfig_usedHTTPInvite_defaultNo {
    NSData *pk = [[NSData alloc] initWithBase64EncodedString:kPubKeyB64 options:0];
    RoomConfig *config = [[RoomConfig alloc] initWithHost:@"h.com" port:8008 pubKey:pk];
    XCTAssertFalse(config.usedHTTPInvite);
}

@end
