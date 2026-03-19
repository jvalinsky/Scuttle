#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <Network/Network.h>
#else
#import "SSBNetworkCompat.h"
#endif

NS_ASSUME_NONNULL_BEGIN

/// SSBMuxRPCFramer handles MuxRPC message boundaries.
/// It sits on top of the security/encryption layer.
@interface SSBMuxRPCFramer : NSObject

/// Creates a protocol definition for the MuxRPC framing layer.
+ (nw_protocol_definition_t)createDefinition;

/// Creates a protocol options object for this framer.
+ (nw_protocol_options_t)createOptions;

@end

NS_ASSUME_NONNULL_END
