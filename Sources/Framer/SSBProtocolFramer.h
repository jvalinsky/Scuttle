#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import "SSBProtocolOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSBProtocolFramer : NSObject

/// Creates a new protocol definition for the SSB Framer.
/// This framer encapsulates the Secret Handshake and Box Stream.
+ (nw_protocol_definition_t)framerDefinition;

/// Creates an options object configured for this framer.
+ (nw_protocol_options_t)createOptionsWithSSBOptions:(SSBProtocolOptions *)options;

@end

NS_ASSUME_NONNULL_END