#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Handles SSB classic message encoding, signing, verification, and key computation.
@interface SSBMessageCodec : NSObject

/// Creates a signed SSB message value dictionary with proper format.
/// @param content The message content (must include "type" key).
/// @param author The author feed ID (@pubkey.ed25519).
/// @param sequence The sequence number for this message.
/// @param previousKey The key of the previous message, or nil for first message.
/// @param secretKey The 64-byte Ed25519 secret key for signing.
/// @return A dictionary with all value fields including signature, or nil on error.
+ (nullable NSDictionary<NSString *, id> *)createSignedMessageWithContent:(NSDictionary<NSString *, id> *)content
                                                   author:(NSString *)author
                                                 sequence:(NSInteger)sequence
                                              previousKey:(nullable NSString *)previousKey
                                                secretKey:(NSData *)secretKey;

/// Computes the SSB message key (%hash.sha256) from a signed value dictionary.
/// @param signedValue The complete signed message value (including signature).
/// @return The message key string, e.g. "%BASE64.sha256".
+ (nullable NSString *)computeMessageKey:(NSDictionary<NSString *, id> *)signedValue;

/// Verifies the signature of a signed message value.
/// @param signedValue The complete signed message value (including signature).
/// @return YES if the signature is valid, NO otherwise.
+ (BOOL)verifyMessage:(NSDictionary<NSString *, id> *)signedValue;

/// Encodes an SSB message value to canonical legacy JSON bytes.
/// Fields are ordered: previous, author, sequence, timestamp, hash, content, signature.
/// @param value The message value dictionary.
/// @param includeSig Whether to include the signature field.
/// @return The canonical JSON bytes, or nil on error.
+ (nullable NSData *)encodeLegacyValue:(NSDictionary<NSString *, id> *)value includeSignature:(BOOL)includeSig;

/// Creates a "post" content dictionary.
+ (NSDictionary<NSString *, id> *)postContentWithText:(NSString *)text;

/// Creates a "post" content dictionary with a reply reference.
+ (NSDictionary<NSString *, id> *)postContentWithText:(NSString *)text root:(nullable NSString *)root branch:(nullable NSString *)branch;

/// Creates a root "post" content (SIP-010).
+ (NSDictionary<NSString *, id> *)rootPostContentWithText:(NSString *)text
                                  channel:(nullable NSString *)channel
                           contentWarning:(nullable NSString *)contentWarning
                                mentions:(nullable NSArray<id> *)mentions
                                   recps:(nullable NSArray<id> *)recps;

/// Creates a reply "post" content (SIP-010).
+ (NSDictionary<NSString *, id> *)replyContentWithText:(NSString *)text
                                  root:(NSString *)root
                                branch:(id)branch
                              channel:(nullable NSString *)channel
                       contentWarning:(nullable NSString *)contentWarning
                            mentions:(nullable NSArray<id> *)mentions
                               recps:(nullable NSArray<id> *)recps;

/// Creates a "vote" content (SIP-010).
+ (NSDictionary<NSString *, id> *)voteContentForMessage:(NSString *)messageId
                              expression:(NSString *)expression
                                   value:(int)value
                                    root:(nullable NSString *)root
                                  branch:(nullable NSArray<id> *)branch;

/// Creates a simple "like" vote.
+ (NSDictionary<NSString *, id> *)likeVoteForMessage:(NSString *)messageId;

/// Creates a "contact" content with optional blocking.
+ (NSDictionary<NSString *, id> *)contactContentWithTarget:(NSString *)target
                                 following:(BOOL)following
                                  blocking:(BOOL)blocking;

/// Creates an "about" content with optional image (SIP-010).
+ (NSDictionary<NSString *, id> *)aboutAvatarContentForFeed:(NSString *)feedId
                                       name:(nullable NSString *)name
                                  imageBlob:(nullable NSString *)blobId
                                description:(nullable NSString *)description;

/// Normalizes a channel name per SIP-010 (lowercase, max 30 chars, no special chars).
+ (NSString *)normalizeChannelName:(NSString *)name;

/// Validates a channel name per SIP-010.
+ (BOOL)isValidChannelName:(NSString *)name;

/// Creates a mention for a feed.
+ (NSDictionary<NSString *, id> *)mentionForFeed:(NSString *)feedId name:(nullable NSString *)name;

/// Creates a mention for a message.
+ (NSDictionary<NSString *, id> *)mentionForMessage:(NSString *)messageId;

/// Creates a mention for a blob.
+ (NSDictionary<NSString *, id> *)mentionForBlob:(NSString *)blobId name:(nullable NSString *)name size:(NSUInteger)size;

/// Validates a message ID (must start with % and have .sha256 suffix).
+ (BOOL)isValidMessageId:(NSString *)msgId;

/// Validates a feed ID (must start with @ and have .ed25519 suffix).
+ (BOOL)isValidFeedId:(NSString *)feedId;

/// Validates a blob ID (must start with & and have .sha256 suffix).
+ (BOOL)isValidBlobId:(NSString *)blobId;

/// Creates a "contact" content dictionary.
+ (NSDictionary<NSString *, id> *)contactContentWithTarget:(NSString *)target following:(BOOL)following;

/// Creates an "about" content dictionary for setting profile name/description.
+ (NSDictionary<NSString *, id> *)aboutContentForFeed:(NSString *)feedId name:(nullable NSString *)name description:(nullable NSString *)description;

@end

NS_ASSUME_NONNULL_END
