#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages the Box Stream symmetric encryption protocol.
@interface SSBBoxStream : NSObject

/// Initializes a new Box Stream with the derived shared keys from the Secret Handshake.
/// @param clientToServerKey The key used to encrypt data sent from client to server.
/// @param serverToClientKey The key used to encrypt data sent from server to client.
/// @param clientToServerNonce The initial nonce used to encrypt data sent from client to server.
/// @param serverToClientNonce The initial nonce used to encrypt data sent from server to client.
- (instancetype)initWithClientToServerKey:(NSData *)clientToServerKey
                        serverToClientKey:(NSData *)serverToClientKey
                      clientToServerNonce:(NSData *)clientToServerNonce
                      serverToClientNonce:(NSData *)serverToClientNonce;

/// Encrypts a payload into a Box Stream packet.
/// @param payload The raw data to encrypt.
/// @return The encrypted packet including the 34-byte header and body, or nil on failure.
- (nullable NSData *)encryptPayload:(NSData *)payload;

/// Decrypts a 34-byte Box Stream header.
/// @param headerData The 34-byte header packet.
/// @param outLength Pointer to store the decrypted body length.
/// @param outMac Pointer to store the decrypted body MAC.
/// @return NO on failure or YES on success.
- (BOOL)decryptHeader:(NSData *)headerData outLength:(size_t *)outLength outBodyMac:(NSData * _Nullable __autoreleasing * _Nullable)outMac;

/// Decrypts a Box Stream body.
/// @param bodyData The encrypted body ciphertext.
/// @param bodyMac The 16-byte MAC parsed from the header.
/// @return The decrypted payload, or nil on failure.
- (nullable NSData *)decryptBody:(NSData *)bodyData expectedMac:(NSData *)bodyMac;

/// Whether this stream is acting as the SHS client (initiator).
@property (nonatomic, assign) BOOL isClient;

@end

NS_ASSUME_NONNULL_END
