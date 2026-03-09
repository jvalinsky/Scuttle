#import <Foundation/Foundation.h>
#import <Network/Network.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBConnectionFSM;

/// SSBFramer manages the custom Network.framework framer for the SSB Protocol.
@interface SSBFramer : NSObject

/// Retrieves the custom NWProtocolDefinition used to configure an NWParameters object.
+ (nw_protocol_definition_t)createFramerDefinition;

@end

NS_ASSUME_NONNULL_END
