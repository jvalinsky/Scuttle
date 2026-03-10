#import <Foundation/Foundation.h>
#import <Network/Network.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSBProtocolOptions : NSObject

@property (nonatomic, copy) NSData *networkIdentifier;
@property (nonatomic, copy) NSData *localSecretKey;
@property (nonatomic, copy) NSData *remotePublicKey;

- (instancetype)initWithNetworkIdentifier:(NSData *)networkIdentifier
                           localSecretKey:(NSData *)localSecretKey
                          remotePublicKey:(NSData *)remotePublicKey;

// Set these options on a nw_protocol_options_t
- (void)applyToProtocolOptions:(nw_protocol_options_t)options;

// Get these options from a nw_protocol_options_t
+ (nullable SSBProtocolOptions *)optionsFromProtocolOptions:(nw_protocol_options_t)options;

@end

NS_ASSUME_NONNULL_END
