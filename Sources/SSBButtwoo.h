#import <Foundation/Foundation.h>
#import "SSBFeedCodec.h"

NS_ASSUME_NONNULL_BEGIN

/// Codec for Buttwoo (buttwoo-v1) feed format.
/// Buttwoo uses bencode wire format (same as BendyButt) with Ed25519 signing,
/// but with deterministic message IDs computed as BLAKE2b/SHA-256(author || seq).
/// Unlike BendyButt, there is no separate content signing.
@interface SSBButtwoo : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

/// Compute the deterministic message key: SHA-256(author_pubkey_32bytes || seq_8bytes_bigendian).
/// Note: spec uses BLAKE2b; using SHA-256 as placeholder.
+ (nullable NSData *)computeDeterministicKey:(NSData *)authorPublicKey sequence:(NSInteger)sequence;

/// Returns YES if the Buttwoo message is structurally valid and Ed25519 signature is correct.
+ (BOOL)validateMessage:(NSData *)messageData;

/// Compute the message key from raw wire bytes.
+ (nullable NSData *)computeMessageKey:(NSData *)messageData;

@end

NS_ASSUME_NONNULL_END
