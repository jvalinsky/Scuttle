#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBFeedCodec.h>

NS_ASSUME_NONNULL_BEGIN

/// Singleton registry that maps SSBBFEFeedFormat values to codec instances.
/// Codecs self-register by calling -registerCodec: from their +load method;
/// no external bootstrap is required.
@interface SSBFeedCodecRegistry : NSObject

+ (instancetype)sharedRegistry;

/// Register a codec for its feedFormat. Replaces any prior registration for that format.
- (void)registerCodec:(id<SSBFeedCodec>)codec;

/// Returns the codec for the given feed format, or nil if no codec has been registered.
- (nullable id<SSBFeedCodec>)codecForFeedFormat:(SSBBFEFeedFormat)format;

@end

NS_ASSUME_NONNULL_END
