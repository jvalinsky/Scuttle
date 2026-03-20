#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBBFE.h>

NS_ASSUME_NONNULL_BEGIN

/// Protocol implemented by each feed format codec.
/// A codec is responsible for format-specific cryptographic operations:
/// verifying message integrity and computing canonical message keys from
/// raw wire bytes. Sequence/previous chain ordering is handled by SSBFeedStore.
@protocol SSBFeedCodec <NSObject>

/// The BFE feed format this codec handles.
@property (nonatomic, readonly) SSBBFEFeedFormat feedFormat;

/// The BFE message format this codec produces.
@property (nonatomic, readonly) SSBBFEMessageFormat messageFormat;

/// Verify the cryptographic integrity of a message's raw wire bytes.
/// @param messageData Raw wire encoding (canonical JSON for classic, bencode for BendyButt, etc.).
/// @param error Populated on failure with a description of the invalid structure or bad signature.
/// @return YES if the message's signature and structure are valid.
- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error;

/// Compute the canonical message key from raw wire bytes.
/// @param messageData Raw wire encoding.
/// @param error Populated on failure.
/// @return 32-byte hash (SHA-256 for classic, BLAKE2b for BendyButt, etc.), or nil on failure.
- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData
                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
