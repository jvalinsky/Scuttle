#import <Foundation/Foundation.h>
#import "SSBMuxRPC.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SSBRPCCallback)(id _Nullable response, BOOL isEndOrError, NSError * _Nullable error);

@protocol SSBRoomClientDelegate <NSObject>
@optional
/// Called when the connection and handshake are complete.
- (void)roomClientDidConnect:(id)client;
/// Called when the room successfully responds to a ping.
- (void)roomClientDidPingSuccessfully:(id)client;
/// Called when a peer announces themselves or changes state in the room.
- (void)roomClient:(id)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints;
/// Called when a connection tunnel to another peer is successfully established.
- (void)roomClient:(id)client didEstablishTunnelWithPeer:(NSString *)peerId;
/// Called when an error occurs in the room connection or RPC.
- (void)roomClient:(id)client didEncounterError:(NSError *)error;
@end

/// High-level client for connecting to an SSB-Room server and managing muxrpc tunneling.
@interface SSBRoomClient : NSObject

@property (nonatomic, weak) id<SSBRoomClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, assign) BOOL autoReconnect;

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSData *serverPubKey;
@property (nonatomic, readonly) NSData *localIdentitySecret;

/// Initialize with a target room server explicitly.
- (instancetype)initWithHost:(NSString *)host 
                        port:(uint16_t)port 
                serverPubKey:(NSData *)serverPubKey 
               localIdentity:(NSData *)localIdentitySecret;

/// Connects to the room server, performing SHS and Box Stream setup.
- (void)connect;

/// Sends a generic MuxRPC request with a callback handler.
- (int32_t)sendRPCRequest:(NSArray<NSString *> *)name
                     args:(NSArray *)args
                     type:(NSString *)type
               completion:(nullable SSBRPCCallback)completion;

/// Sends a `tunnel.ping` muxrpc request.
- (void)ping;

/// Sends a `tunnel.announce` muxrpc request to join the room publicly.
- (void)announce;

/// Subscribes to `tunnel.endpoints` to receive real-time peer lists.
- (void)subscribeToEndpoints;

/// Sends a `tunnel.connect` duplex request to connect to a specific target peer.
- (void)connectToPeer:(NSString *)targetPeerId;

/// Disconnects from the room.
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
