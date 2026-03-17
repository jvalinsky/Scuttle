//
//  SSBKeychain.h
//  SSBNetwork
//
//  Secure keychain storage for SSB identity keys
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSBKeychain : NSObject

+ (nullable NSData *)loadIdentitySecret;
+ (BOOL)saveIdentitySecret:(NSData *)secret;
+ (BOOL)deleteIdentitySecret;

+ (nullable NSData *)loadNetworkKey;
+ (BOOL)saveNetworkKey:(NSData *)key;
+ (BOOL)deleteNetworkKey;

+ (NSInteger)loadPublishedMessageCount;
+ (BOOL)savePublishedMessageCount:(NSInteger)count;

+ (BOOL)clearAll;

/// Returns the canonical SSB public ID string ("@<base64>.ed25519") derived from a
/// 64-byte Ed25519 keypair secret. Returns nil if secret is shorter than 64 bytes.
+ (nullable NSString *)publicIDFromSecret:(NSData *)secret;

#pragma mark - Metafeed

/// 32-byte random seed from which the entire metafeed tree is deterministically derived.
+ (nullable NSData *)loadMetafeedSeed;
+ (BOOL)saveMetafeedSeed:(NSData *)seed;
+ (BOOL)deleteMetafeedSeed;

/// Canonical ID of the root metafeed ("@<base64>.ed25519"), derived from the seed.
+ (nullable NSString *)loadMetafeedRootID;
+ (BOOL)saveMetafeedRootID:(NSString *)rootID;
+ (BOOL)deleteMetafeedRootID;

/// Whether a metafeed/announce message has been successfully published on the classic feed.
+ (BOOL)loadMetafeedAnnounced;
+ (BOOL)saveMetafeedAnnounced:(BOOL)announced;
+ (BOOL)deleteMetafeedAnnounced;

@end

NS_ASSUME_NONNULL_END
