#import <Foundation/Foundation.h>
#import "SSBFeedCodec.h"

NS_ASSUME_NONNULL_BEGIN

/// Codec for Bamboo feed format.
/// Bamboo uses a custom binary append-only log with Ed25519 signing,
/// BLAKE2b content hashing, and Lipmaa-linked entries for efficient
/// skip-list traversal. Message IDs are 64 bytes (entry hash + signature).
@interface SSBBamboo : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

/// Compute the lipmaa sequence number for a given sequence.
/// lipmaa(1) = 1; for n > 1 returns the largest power-of-3 subtracted from n.
+ (NSInteger)lipmaaSequenceFor:(NSInteger)seq;

/// Compute SHA-256 hash of data (stand-in for BLAKE2b until dependency added).
/// TODO: Replace with BLAKE2b-256 per Bamboo spec.
+ (nullable NSData *)hashData:(NSData *)data;

/// Validate a raw Bamboo entry binary. Returns YES if structure and signature are valid.
+ (BOOL)validateEntry:(NSData *)entryData;

/// Compute the 64-byte entry ID (SHA-256(entryData) || signature_bytes).
/// Note: spec uses BLAKE2b; using SHA-256 as placeholder.
+ (nullable NSData *)computeEntryID:(NSData *)entryData;

@end

NS_ASSUME_NONNULL_END
