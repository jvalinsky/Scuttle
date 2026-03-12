#import <Foundation/Foundation.h>
#import <Network/Network.h>

NS_ASSUME_NONNULL_BEGIN

/// SSBSecurityFramer encapsulates the Secret Handshake (SHS) and Box Stream encryption.
/// It sits directly on top of TCP.
@interface SSBSecurityFramer : NSObject

/// Creates a protocol definition for the SSB Security layer.
+ (nw_protocol_definition_t)createDefinition;

/// Creates a protocol options object for this framer, initialized with the provided keys and role.
/// @param localSecretKey The 64-byte local Ed25519 secret key.
/// @param remotePublicKey The 32-byte remote Ed25519 public key.
/// @param asClient YES to act as the SHS initiator, NO to act as the responder.
+ (nw_protocol_options_t)createOptionsWithLocalSecretKey:(NSData *)localSecretKey
                                         remotePublicKey:(NSData *)remotePublicKey
                                                asClient:(BOOL)asClient;

@end

NS_ASSUME_NONNULL_END