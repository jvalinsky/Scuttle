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

@end

NS_ASSUME_NONNULL_END
