#import "SSBMetafeed.h"
#import "SSBBFE.h"
#import "SSBMessageCodec.h"
#import "tweetnacl.h"
#import "SSBCommonCryptoCompat.h"

static NSString *const kMetafeedSeedSalt = @"ssb";
static NSString *const kRootMetafeedInfo = @"ssb-meta-feed-seed-v1:metafeed";
static NSInteger const kNumberOfShards = 16;
#define kMetafeedSeedLength     32                                       // seed is always 32 bytes
#define kMetafeedBoxedSeedLen   (crypto_secretbox_BOXZEROBYTES + kMetafeedSeedLength)  // MAC(16)+ct(32)=48
#define kMetafeedPaddedCipherLen (crypto_secretbox_BOXZEROBYTES + kMetafeedBoxedSeedLen) // 64

@implementation SSBMetafeedKeys

- (instancetype)initWithPublicKey:(NSData *)publicKey
                        secretKey:(NSData *)secretKey {
    self = [super init];
    if (self) {
        _publicKey = publicKey;
        _secretKey = secretKey;
        _feedID = [NSString stringWithFormat:@"@%@.ed25519",
                   [SSBBFE base64URLEncodedStringFromData:publicKey]];
    }
    return self;
}

@end

@interface SSBMetafeed ()
@property (nonatomic, readwrite) NSString *ID;
@property (nonatomic, readwrite) SSBMetafeedKeys *keys;
@property (nonatomic, readwrite) SSBMetafeed *v1Subfeed;
@property (nonatomic, readwrite) NSArray<SSBMetafeed *> *shardFeeds;
@end

@implementation SSBMetafeed

#pragma mark - Instance Operations (SIP 2)

- (nullable NSDictionary<NSString *, id> *)addExistingFeedMessage:(NSString *)feedID
                                                          purpose:(SSBMetafeedPurpose)purpose {
    return [SSBMetafeed createMetafeed:self.ID addExistingFeed:feedID purpose:purpose];
}

- (nullable NSDictionary<NSString *, id> *)addDerivedFeedMessage:(NSString *)feedName
                                                         purpose:(SSBMetafeedPurpose)purpose
                                                           nonce:(NSData *)nonce {
    return [SSBMetafeed createMetafeed:self.ID addDerivedFeed:feedName purpose:purpose nonce:nonce];
}

- (nullable NSDictionary<NSString *, id> *)tombstoneFeedMessage:(NSString *)feedID
                                                         reason:(nullable NSString *)reason {
    return [SSBMetafeed createMetafeed:self.ID tombstoneFeed:feedID reason:reason];
}

#pragma mark - Seed Generation

+ (nullable NSData *)generateSeed {
    NSMutableData *seed = [NSMutableData dataWithLength:32];
    if (!seed) return nil;
    
#ifdef __APPLE__
    int result = SecRandomCopyBytes(kSecRandomDefault, 32, seed.mutableBytes);
    if (result != errSecSuccess) {
        return nil;
    }
#else
    extern void randombytes(unsigned char *, unsigned long long);
    randombytes(seed.mutableBytes, 32);
#endif
    
    return seed;
}

#pragma mark - Key Derivation (HKDF)

+ (nullable NSData *)deriveRootKeyFromSeed:(NSData *)seed {
    return [self deriveKeyFromSeed:seed info:kRootMetafeedInfo];
}

+ (nullable NSData *)deriveKeyFromSeed:(NSData *)seed info:(NSString *)info {
    if (!seed || seed.length != 32 || !info) {
        return nil;
    }
    
    NSData *saltData = [kMetafeedSeedSalt dataUsingEncoding:NSUTF8StringEncoding];
    NSData *infoData = [info dataUsingEncoding:NSUTF8StringEncoding];
    
    // HKDF-Extract: PRK = HMAC-SHA512(salt, seed)
    unsigned char prk[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, saltData.bytes, saltData.length, seed.bytes, seed.length, prk);
    
    // HKDF-Expand: OKM = HMAC-SHA512(PRK, info | 0x01) for first 32 bytes
    NSMutableData *t = [NSMutableData dataWithData:infoData];
    uint8_t one = 1;
    [t appendBytes:&one length:1];
    
    unsigned char okm[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, prk, CC_SHA512_DIGEST_LENGTH, t.bytes, t.length, okm);
    
    return [NSData dataWithBytes:okm length:32];
}

#pragma mark - Root Metafeed Creation

+ (nullable instancetype)createRootMetafeedFromSeed:(NSData *)seed {
    if (!seed || seed.length != 32) {
        return nil;
    }
    
    SSBMetafeed *metafeed = [[SSBMetafeed alloc] init];
    
    NSData *metafeedKeyData = [self deriveKeyFromSeed:seed info:kRootMetafeedInfo];
    if (!metafeedKeyData) {
        return nil;
    }
    
    unsigned char publicKey[crypto_sign_ed25519_PUBLICKEYBYTES];
    unsigned char secretKey[crypto_sign_ed25519_SECRETKEYBYTES];
    
    crypto_sign_seed_keypair(publicKey, secretKey, metafeedKeyData.bytes);
    
    NSData *pubKeyData = [NSData dataWithBytes:publicKey length:crypto_sign_ed25519_PUBLICKEYBYTES];
    NSData *secKeyData = [NSData dataWithBytes:secretKey length:crypto_sign_ed25519_SECRETKEYBYTES];
    
    metafeed.keys = [[SSBMetafeedKeys alloc] initWithPublicKey:pubKeyData
                                                      secretKey:secKeyData];
    metafeed.ID = metafeed.keys.feedID;
    
    NSData *v1Seed = [self deriveKeyFromSeed:seed info:@"ssb-meta-feed-seed-v1:v1"];
    if (v1Seed) {
        metafeed.v1Subfeed = [self createSubfeedFromSeed:v1Seed
                                              parentID:metafeed.ID
                                               purpose:SSBMetafeedPurposeV1];
    }
    
    NSMutableArray<SSBMetafeed *> *shards = [NSMutableArray array];
    for (NSInteger i = 0; i < kNumberOfShards; i++) {
        NSString *shardInfo = [NSString stringWithFormat:@"ssb-meta-feed-seed-v1:shard-%02lx", (long)i];
        NSData *shardSeed = [self deriveKeyFromSeed:seed info:shardInfo];
        if (shardSeed) {
            SSBMetafeed *shard = [self createSubfeedFromSeed:shardSeed
                                                  parentID:metafeed.ID
                                                   purpose:SSBMetafeedPurposeShard];
            if (shard) {
                [shards addObject:shard];
            }
        }
    }
    metafeed.shardFeeds = shards;
    
    return metafeed;
}

+ (nullable SSBMetafeed *)createSubfeedFromSeed:(NSData *)seed
                                      parentID:(NSString *)parentID
                                       purpose:(SSBMetafeedPurpose)purpose {
    if (!seed || seed.length != 32 || !parentID) {
        return nil;
    }
    
    unsigned char publicKey[crypto_sign_ed25519_PUBLICKEYBYTES];
    unsigned char secretKey[crypto_sign_ed25519_SECRETKEYBYTES];
    
    crypto_sign_seed_keypair(publicKey, secretKey, seed.bytes);
    
    NSData *pubKeyData = [NSData dataWithBytes:publicKey length:crypto_sign_ed25519_PUBLICKEYBYTES];
    NSData *secKeyData = [NSData dataWithBytes:secretKey length:crypto_sign_ed25519_SECRETKEYBYTES];
    
    SSBMetafeedKeys *keys = [[SSBMetafeedKeys alloc] initWithPublicKey:pubKeyData
                                                              secretKey:secKeyData];
    
    SSBMetafeed *subfeed = [[SSBMetafeed alloc] init];
    subfeed.keys = keys;
    subfeed.ID = keys.feedID;
    
    return subfeed;
}

#pragma mark - Metafeed Message Creation

+ (nullable NSDictionary *)createMetafeed:(NSString *)metafeedID
                          addExistingFeed:(NSString *)feedID
                                   purpose:(SSBMetafeedPurpose)purpose {
    if (!metafeedID || !feedID) {
        return nil;
    }
    
    NSDictionary *content = @{
        @"type": @"metafeed",
        @"metafeedType": @"add/existing",
        @"feed": feedID,
        @"purpose": @(purpose)
    };
    
    return content;
}

+ (nullable NSDictionary *)createMetafeed:(NSString *)metafeedID
                           addDerivedFeed:(NSString *)feedName
                                   purpose:(SSBMetafeedPurpose)purpose
                                     nonce:(NSData *)nonce {
    if (!metafeedID || !feedName || !nonce) {
        return nil;
    }
    
    NSString *nonceBase64 = [SSBBFE base64URLEncodedStringFromData:nonce];
    
    NSDictionary *content = @{
        @"type": @"metafeed",
        @"metafeedType": @"add/derived",
        @"feed": feedName,
        @"purpose": @(purpose),
        @"nonce": nonceBase64
    };
    
    return content;
}

+ (nullable NSDictionary *)createMetafeed:(NSString *)metafeedID
                            updateFeed:(NSString *)feedID
                                 name:(nullable NSString *)name
                             purpose:(SSBMetafeedPurpose)purpose {
    if (!metafeedID || !feedID) {
        return nil;
    }
    
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"metafeed";
    content[@"metafeedType"] = @"update";
    content[@"feed"] = feedID;
    content[@"purpose"] = @(purpose);
    if (name) {
        content[@"name"] = name;
    }
    
    return content;
}

+ (nullable NSDictionary *)createMetafeed:(NSString *)metafeedID
                          tombstoneFeed:(NSString *)feedID
                                reason:(nullable NSString *)reason {
    if (!metafeedID || !feedID) {
        return nil;
    }
    
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"metafeed";
    content[@"metafeedType"] = @"tombstone";
    content[@"feed"] = feedID;
    if (reason) {
        content[@"reason"] = reason;
    }
    
    return content;
}

+ (nullable NSDictionary *)createMetafeedAnnounceMessage:(NSString *)metafeedID
                                               onMainFeed:(NSString *)mainFeedID
                                                secretKey:(NSData *)secretKey {
    if (!metafeedID || !mainFeedID || !secretKey) {
        return nil;
    }
    
    NSDictionary *content = @{
        @"type": @"metafeed",
        @"metafeedType": @"announce",
        @"metafeed": metafeedID
    };
    
    return content;
}

+ (nullable NSDictionary *)createSeedMessage:(NSData *)seed
                                 forMetafeed:(NSString *)metafeedID
                                  secretKey:(NSData *)secretKey
                                 onMainFeed:(NSString *)mainFeedID {
    if (!seed || !metafeedID || !secretKey || !mainFeedID) {
        return nil;
    }
    
    NSString *seedBase64 = [seed base64EncodedStringWithOptions:0];
    
    NSDictionary *content = @{
        @"type": @"metafeed",
        @"metafeedType": @"seed",
        @"metafeed": metafeedID,
        @"seed": seedBase64
    };
    
    return content;
}

#pragma mark - Seed Encryption

+ (nullable NSData *)encryptSeedForBackup:(NSData *)seed
                                   toFeed:(NSString *)feedID
                               feedKeys:(SSBMetafeedKeys *)keys {
    if (!seed || seed.length != 32 || !feedID || !keys) {
        return nil;
    }
    
    NSData *recipientKeyData = [SSBBFE bfeDataFromSigilString:feedID];
    if (!recipientKeyData || recipientKeyData.length < 34) {
        return nil;
    }
    
    NSData *recipientEd25519Key = [recipientKeyData subdataWithRange:NSMakeRange(2, 32)];
    unsigned char recipientCurve25519Key[crypto_box_PUBLICKEYBYTES];
    if (crypto_sign_ed25519_pk_to_curve25519(recipientCurve25519Key, recipientEd25519Key.bytes) != 0) {
        return nil;
    }

    unsigned char ephemeralSK[crypto_box_SECRETKEYBYTES];
#ifdef __APPLE__
    SecRandomCopyBytes(kSecRandomDefault, crypto_box_SECRETKEYBYTES, ephemeralSK);
#else
    extern void randombytes(unsigned char *, unsigned long long);
    randombytes(ephemeralSK, crypto_box_SECRETKEYBYTES);
#endif

    // Derive ephemeral public key from ephemeral secret key
    unsigned char ephemeralPubKey[crypto_box_PUBLICKEYBYTES];
    if (crypto_scalarmult_curve25519_base(ephemeralPubKey, ephemeralSK) != 0) {
        return nil;
    }

    // Compute DH shared secret: ephemeralSK × recipientPK
    unsigned char sharedKey[crypto_box_BEFORENMBYTES];
    if (crypto_box_beforenm(sharedKey, recipientCurve25519Key, ephemeralSK) != 0) {
        return nil;
    }

    // Zero nonce — safe because the DH key is unique per ephemeral keypair
    unsigned char nonce[crypto_box_NONCEBYTES];
    memset(nonce, 0, crypto_box_NONCEBYTES);

    // NaCl secretbox requires first ZEROBYTES (32) of plaintext buffer to be zero
    unsigned char paddedMessage[crypto_secretbox_ZEROBYTES + kMetafeedSeedLength];
    memset(paddedMessage, 0, crypto_secretbox_ZEROBYTES);
    memcpy(paddedMessage + crypto_secretbox_ZEROBYTES, seed.bytes, kMetafeedSeedLength);

    // Output: BOXZEROBYTES (16) zeros || MAC (16) || ciphertext (32) = 64 bytes
    unsigned char result[sizeof(paddedMessage)];
    int ret = crypto_secretbox_xsalsa20poly1305(result, paddedMessage, sizeof(paddedMessage), nonce, sharedKey);
    if (ret != 0) {
        return nil;
    }

    // Skip the BOXZEROBYTES zero-prefix; append MAC (16) + ciphertext (32) = 48 bytes
    NSMutableData *ciphertextData = [NSMutableData dataWithBytes:ephemeralPubKey length:crypto_box_PUBLICKEYBYTES];
    [ciphertextData appendBytes:result + crypto_secretbox_BOXZEROBYTES length:kMetafeedBoxedSeedLen];

    return ciphertextData;
}

+ (nullable NSData *)decryptSeedFromMessage:(NSDictionary *)message
                                   feedKeys:(SSBMetafeedKeys *)keys {
    if (!message || !keys) {
        return nil;
    }
    
    id encryptedContent = message[@"content"][@"ciphertext"];
    if (!encryptedContent) {
        return nil;
    }
    
    NSData *ciphertext = nil;
    if ([encryptedContent isKindOfClass:[NSString class]]) {
        ciphertext = [[NSData alloc] initWithBase64EncodedString:encryptedContent options:0];
    } else if ([encryptedContent isKindOfClass:[NSData class]]) {
        ciphertext = (NSData *)encryptedContent;
    }
    
    // ciphertext = ephemeralPubKey (32) || MAC+encryptedSeed (48) = 80 bytes minimum
    if (!ciphertext || ciphertext.length < crypto_box_PUBLICKEYBYTES + kMetafeedBoxedSeedLen) {
        return nil;
    }

    NSData *ephemeralPubKey = [ciphertext subdataWithRange:NSMakeRange(0, crypto_box_PUBLICKEYBYTES)];
    NSData *boxedSeed = [ciphertext subdataWithRange:NSMakeRange(crypto_box_PUBLICKEYBYTES, kMetafeedBoxedSeedLen)];

    unsigned char recipientCurve25519Secret[crypto_box_SECRETKEYBYTES];
    if (crypto_sign_ed25519_sk_to_curve25519(recipientCurve25519Secret, keys.secretKey.bytes) != 0) {
        return nil;
    }

    unsigned char sharedKey[crypto_box_BEFORENMBYTES];
    int ret = crypto_box_beforenm(sharedKey, ephemeralPubKey.bytes, recipientCurve25519Secret);
    if (ret != 0) {
        return nil;
    }

    unsigned char nonce[crypto_box_NONCEBYTES];
    memset(nonce, 0, crypto_box_NONCEBYTES);

    // NaCl _open requires first BOXZEROBYTES (16) of ciphertext buffer to be zero;
    // seed is always kMetafeedSeedLength bytes so buffer sizes are compile-time constants.
    unsigned char paddedC[kMetafeedPaddedCipherLen];
    memset(paddedC, 0, crypto_secretbox_BOXZEROBYTES);
    memcpy(paddedC + crypto_secretbox_BOXZEROBYTES, boxedSeed.bytes, kMetafeedBoxedSeedLen);

    unsigned char decrypted[kMetafeedPaddedCipherLen];
    ret = crypto_secretbox_xsalsa20poly1305_open(decrypted, paddedC, kMetafeedPaddedCipherLen, nonce, sharedKey);
    if (ret != 0) {
        return nil;
    }

    // NaCl _open output: first ZEROBYTES (32) are zero, then plaintext
    return [NSData dataWithBytes:decrypted + crypto_secretbox_ZEROBYTES length:kMetafeedSeedLength];
}

#pragma mark - Shard Calculation

+ (NSString *)shardNibbleForMetafeedID:(NSString *)metafeedID
                                  name:(NSString *)name {
    if (!metafeedID || !name) {
        return @"0";
    }
    
    NSString *combined = [NSString stringWithFormat:@"%@%@", metafeedID, name];
    NSData *combinedData = [combined dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [self sha256:combinedData];
    
    if (!hash || hash.length < 1) {
        return @"0";
    }
    
    const uint8_t *bytes = hash.bytes;
    uint8_t firstNibble = (bytes[0] >> 4) & 0x0F;
    
    return [NSString stringWithFormat:@"%x", firstNibble];
}

#pragma mark - Utility

+ (nullable NSData *)sha256:(NSData *)data {
    if (!data) {
        return nil;
    }
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Feed Purpose Helpers

+ (NSString *)nameForPurpose:(SSBMetafeedPurpose)purpose {
    switch (purpose) {
        case SSBMetafeedPurposeClassic:
            return @"classic";
        case SSBMetafeedPurposeV1:
            return @"v1";
        case SSBMetafeedPurposeShard:
            return @"shard";
        case SSBMetafeedPurposeApplication:
            return @"application";
        case SSBMetafeedPurposeGroup:
            return @"group";
        default:
            return @"unknown";
    }
}

+ (SSBMetafeedPurpose)purposeFromString:(NSString *)purposeString {
    if ([purposeString isEqualToString:@"classic"]) {
        return SSBMetafeedPurposeClassic;
    } else if ([purposeString isEqualToString:@"v1"]) {
        return SSBMetafeedPurposeV1;
    } else if ([purposeString isEqualToString:@"shard"]) {
        return SSBMetafeedPurposeShard;
    } else if ([purposeString isEqualToString:@"application"]) {
        return SSBMetafeedPurposeApplication;
    } else if ([purposeString isEqualToString:@"group"]) {
        return SSBMetafeedPurposeGroup;
    }
    return SSBMetafeedPurposeClassic;
}

@end
