#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBMuxRPCSession.h>
#import <SSBNetwork/SSBTransport.h>

NS_ASSUME_NONNULL_BEGIN

/// A specialized connection abstraction that hosts a Network.framework framer stack 
/// (Secret Handshake + Box Stream + MuxRPC) over an existing MuxRPC tunnel stream.
@interface SSBTunnelConnection : NSObject

/// Indicates if the tunnel connection is successfully established
@property (nonatomic, assign, readonly) BOOL isConnected;

/// The outer room-session request ID associated with this tunnel stream.
@property (nonatomic, assign, readonly) int32_t tunnelReqID;

/// YES when this tunnel was created from an inbound `tunnel.connect` request.
@property (nonatomic, assign, readonly) BOOL isServer;

/// The target peer ID that we are connected to via the tunnel
@property (nonatomic, strong, readonly) NSString *peerId;

/// The MuxRPC session representing the inner tunneled peer-to-peer connection
@property (nonatomic, strong, readonly) SSBMuxRPCSession *rpcSession;

/// Callback invoked when the tunnel connection is fully established and ready for RPC calls
@property (nonatomic, copy, nullable) void (^onConnectionStateReady)(void);

/// Initialize a new tunnel connection
/// @param peerId The ID of the target peer
/// @param peerPublicKey The public key of the target peer
/// @param localSecret Our local identity secret
/// @param roomSession The room's outer MuxRPC session
/// @param tunnelReqID The MuxRPC request ID
/// @param isServer YES if we are receiving the tunnel request, NO if we are initiating it
- (instancetype)initWithPeerId:(NSString *)peerId
                 peerPublicKey:(NSData *)peerPublicKey
                 localIdentity:(NSData *)localSecret
                   roomSession:(SSBMuxRPCSession *)roomSession
                   tunnelReqID:(int32_t)tunnelReqID
                      isServer:(BOOL)isServer;

/// Starts the listener and connects the client endpoint to begin the Secret Handshake.
- (void)start;

/// Cleans up connections, listeners, and endpoints.
- (void)stop;

/// Called when new payload data arrives from the room's tunnel.connect stream.
/// @param data The encrypted SHS/BoxStream data payload
- (void)receiveTunnelData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
