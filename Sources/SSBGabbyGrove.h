#import <Foundation/Foundation.h>
#import "SSBFeedCodec.h"

NS_ASSUME_NONNULL_BEGIN

/// Codec for GabbyGrove (ggfeed-v1) feed format.
/// GabbyGrove uses a Protocol Buffers wire format with Ed25519 author signing
/// and HMAC-SHA256 content authentication.
/// Conforms to SSBFeedCodec and self-registers at +load time.
@interface SSBGabbyGrove : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

/// Encode a varint (unsigned LEB128) to a mutable data buffer.
+ (void)appendVarint:(uint64_t)value toData:(NSMutableData *)data;

/// Decode a varint from bytes at *offset. Returns 0 and does not advance offset on failure.
+ (uint64_t)decodeVarintFrom:(const uint8_t *)bytes length:(NSUInteger)length offset:(NSUInteger *)offset;

/// Compute BLAKE2b-256 hash of data. Returns 32 bytes.
+ (nullable NSData *)blake2b256:(NSData *)data;

/// Returns YES if the GabbyGrove message is structurally valid and the Ed25519 signature is correct.
+ (BOOL)validateMessage:(NSData *)messageData;

/// Compute the message key (BLAKE2b-256 of wire bytes). Returns 32 bytes.
+ (nullable NSData *)computeMessageKey:(NSData *)messageData;

@end

NS_ASSUME_NONNULL_END
