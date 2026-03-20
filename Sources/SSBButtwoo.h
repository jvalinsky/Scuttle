#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBFeedCodec.h>

NS_ASSUME_NONNULL_BEGIN

/// Codec for Buttwoo (buttwoo-v1) feed format.
/// Buttwoo uses BIPF wire format with Ed25519 signing and deterministic message
/// IDs computed as BLAKE3-256(author_pubkey_32bytes || seq_8bytes_bigendian).
/// Unlike BendyButt, there is no separate content signing.
@interface SSBButtwoo : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

/// Compute the deterministic message key: BLAKE3-256(author_pubkey_32bytes || seq_8bytes_bigendian).
+ (nullable NSData *)computeDeterministicKey:(NSData *)authorPublicKey sequence:(NSInteger)sequence;

/// Returns YES if the Buttwoo message is structurally valid and Ed25519 signature is correct.
+ (BOOL)validateMessage:(NSData *)messageData;

/// Compute the message key from raw wire bytes.
+ (nullable NSData *)computeMessageKey:(NSData *)messageData;

@end

NS_ASSUME_NONNULL_END
