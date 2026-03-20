#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBFeedCodec.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a Lipmaa Inclusion Proof for a single Bamboo message.
 * This structure allows a receiver to verify that a message belongs
 * to an author's feed without possessing the entire feed history.
 */
@interface SSBBambooProof : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSData *targetMessage;   // Raw binary of the target message.
@property (nonatomic, copy) NSArray<NSData *> *lipmaaPath; // Ordered hashes along the Lipmaa path.
@property (nonatomic, copy) NSData *rootHash;        // Hash of the sequence 1 message.
@property (nonatomic, copy) NSData *authorPubKey;    // Ed25519 public key.
@end

/**
 * Codec for Bamboo feed format.
 * Bamboo uses a custom binary append-only log with Ed25519 signing,
 * BLAKE2b content hashing, and Lipmaa-linked entries for efficient
 * skip-list traversal. Message IDs are 32 bytes (BLAKE2b-256 of the full entry bytes).
 */
@interface SSBBamboo : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

/// Compute the lipmaa sequence number for a given sequence.
/// lipmaa(1) = 1; for n > 1 returns the largest power-of-3 subtracted from n.
+ (NSInteger)lipmaaSequenceFor:(NSInteger)seq;

/// Compute BLAKE2b-256 hash of data.
+ (nullable NSData *)hashData:(NSData *)data;

/// Validate a raw Bamboo entry binary. Returns YES if structure and signature are valid.
+ (BOOL)validateEntry:(NSData *)entryData;

/// Compute the 32-byte entry ID = BLAKE2b-256 of the full entry bytes.
+ (nullable NSData *)computeEntryID:(NSData *)entryData;

/**
 * Verify a Lipmaa Inclusion Proof.
 * @param proof The proof object to verify.
 * @param error Populated on failure.
 * @return YES if the message is cryptographically proven to belong to the author's chain.
 */
+ (BOOL)verifyProof:(SSBBambooProof *)proof error:(NSError **)error;

/**
 * Serialize a proof to binary for QR encoding.
 */
+ (nullable NSData *)serializeProof:(SSBBambooProof *)proof;

/**
 * Deserialize a proof from binary.
 */
+ (nullable SSBBambooProof *)deserializeProof:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
