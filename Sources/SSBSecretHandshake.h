#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages the Secret Handshake (SHS) mutually authenticating key agreement.
@interface SSBSecretHandshake : NSObject

@property (nonatomic, readonly) BOOL isClient;

/// Initializes a new handshake state machine
/// @param isClient YES if initiating the connection, NO if receiving.
/// @param localIdentitySecret 64-byte Ed25519 Secret Key (Seed + PubKey).
/// @param remotePublicKey 32-byte Ed25519 Public Key (Required for clients).
- (instancetype)initWithRole:(BOOL)isClient
               localIdentity:(NSData *)localIdentitySecret
             remotePublicKey:(nullable NSData *)remotePublicKey;

/// Step 1: Generate Client Hello (64 bytes)
- (nullable NSData *)createHello;

/// Step 2: Process received Hello
- (BOOL)processHello:(NSData *)helloData;

/// Step 3: Generate Auth message
- (nullable NSData *)createAuth;

/// Step 4: Process Auth message
- (BOOL)processAuth:(NSData *)authData;

/// Step 5: Generate Accept message
- (nullable NSData *)createAccept;

/// Step 6: Process Accept message
- (BOOL)processAccept:(NSData *)acceptData;

/// Retrieves the derived keys for Box Stream. Only valid after successful handshake.
@property (nonatomic, readonly, nullable) NSData *clientToServerKey;
@property (nonatomic, readonly, nullable) NSData *serverToClientKey;

/// Derived nonces needed to seed the Box Stream
@property (nonatomic, readonly, nullable) NSData *clientToServerNonce;
@property (nonatomic, readonly, nullable) NSData *serverToClientNonce;

@end

NS_ASSUME_NONNULL_END
