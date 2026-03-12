#import <Foundation/Foundation.h>
#import "SSBMuxRPC.h"
#import "RoomInviteHandler.h"
#import "SSBFeedStore.h"
#import "SSBMessageCodec.h"
#import "SSBLogger.h"

NS_ASSUME_NONNULL_BEGIN

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
/// Called when the client wants to emit a diagnostic log.
- (void)roomClient:(id)client didLogMessage:(NSString *)message;
/// Called when new messages are replicated from a peer.
- (void)roomClient:(id)client didReplicateMessagesFromPeer:(NSString *)peerId count:(NSInteger)count;
/// Called when sync status or progress changes.
- (void)roomClient:(id)client didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author;
/// Called when the local feed is fully synced and ready to publish.
- (void)roomClientDidSyncLocalFeed:(id)client;
/// Called when messages in the publish queue have been processed.
- (void)roomClientDidProcessPublishQueue:(id)client success:(BOOL)success queuedCount:(NSInteger)count;
@end

/// High-level client for connecting to an SSB-Room server and managing muxrpc tunneling.
@interface SSBRoomClient : NSObject

@property (nonatomic, weak) id<SSBRoomClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isFeedSynced;
@property (nonatomic, readonly) NSInteger pendingMessagesCount;
@property (nonatomic, assign) BOOL autoReconnect;

@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *peerSyncProgress;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *peerSyncStates;

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSData *serverPubKey;
@property (nonatomic, readonly) NSData *localIdentitySecret;
@property (nonatomic, readonly, nullable) NSString *inviteToken;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *roomFeatures;
@property (nonatomic, readonly) BOOL isInternalUser;

/// Initialize with a target room server explicitly.
- (instancetype)initWithHost:(NSString *)host 
                         port:(uint16_t)port 
                 serverPubKey:(NSData *)serverPubKey 
                localIdentity:(nullable NSData *)localIdentitySecret;

/// Initialize using a RoomConfig object.
- (instancetype)initWithConfig:(RoomConfig *)config 
                   localIdentity:(nullable NSData *)localIdentitySecret;

/// Connects to the room server, performing SHS and Box Stream setup via stacked framers.
- (void)connect;

/// Redeems an invite token via RPC.
- (void)redeemInvite:(NSString *)token completion:(nullable SSBRPCCallback)completion;

/// Registers an alias with the room server. Automatically signs the registration per SIP 7.
- (void)registerAlias:(NSString *)alias completion:(nullable SSBRPCCallback)completion;

/// Registers an alias with a pre-computed signature.
- (void)registerAlias:(NSString *)alias signature:(NSString *)signature completion:(nullable SSBRPCCallback)completion;

/// Revokes a previously registered alias.
- (void)revokeAlias:(NSString *)alias completion:(nullable SSBRPCCallback)completion;

/// Publishes a contact (follow/unfollow) message to the user's feed.
- (void)publishContact:(NSString *)targetPubKey following:(BOOL)following completion:(nullable SSBRPCCallback)completion;

/// Publishes a contact (block/unblock) message to the user's feed.
- (void)publishBlock:(NSString *)targetPubKey blocking:(BOOL)blocking completion:(nullable SSBRPCCallback)completion;

/// Publishes a post message to the local feed.
- (nullable SSBMessage *)publishPostWithText:(NSString *)text error:(NSError **)error;

/// Publishes a message with arbitrary content to the local feed.
- (nullable SSBMessage *)publishLocalMessageWithContent:(NSDictionary<NSString *, id> *)content error:(NSError **)error;

/// Sends a generic MuxRPC request with a callback handler.
- (int32_t)sendRPCRequest:(NSArray<NSString *> *)name
                      args:(NSArray<id> *)args
                      type:(NSString *)type
                completion:(nullable SSBRPCCallback)completion;

/// Fetches history stream for a peer (SIP 7).
- (void)fetchFeedForPeer:(NSString *)peerID limit:(NSInteger)limit completion:(nullable SSBRPCCallback)completion;

/// Fetches profile information (metadata/about) for a peer.
- (void)fetchProfileForPeer:(NSString *)peerID completion:(nullable SSBRPCCallback)completion;

/// Fetches a blob from the connected peer by its blob ID (&hash.sha256).
/// The blob data is accumulated from the source stream and stored locally via SSBBlobStore.
- (void)fetchBlob:(NSString *)blobID completion:(void (^)(NSString * _Nullable localPath, NSError * _Nullable error))completion;

/// Checks if the connected peer has a specific blob.
- (void)hasBlob:(NSString *)blobID completion:(void (^)(BOOL hasIt))completion;

/// Fetches room metadata (name, features, etc.) - SIP 7.
- (void)fetchRoomMetadataWithCompletion:(nullable SSBRPCCallback)completion;

/// Sends a `tunnel.ping` muxrpc request.
- (void)ping;

/// Sends a `tunnel.announce` muxrpc request to join the room publicly.
- (void)announce;

/// Subscribes to `tunnel.endpoints` to receive real-time peer lists.
- (void)subscribeToEndpoints;

/// Queries a subset of messages from the server (SIP 3).
/// @param query The ssb-ql-0 query.
/// @param options Pagination options (@"pageSize", @"descending", @"startFrom").
- (void)getSubset:(NSDictionary<NSString *, id> *)query
          options:(NSDictionary<NSString *, id> *)options
       completion:(nullable SSBRPCCallback)completion;

/// Sends a `tunnel.connect` duplex request to connect to a specific target peer.
- (void)connectToPeer:(NSString *)targetPeerId;

/// Returns the local feed store.
@property (nonatomic, readonly) SSBFeedStore *feedStore;

/// Manually trigger replication from a peer via a room.
- (void)replicateFromPeer:(NSString *)peerID viaRoom:(NSString *)roomHost;

/// Resets the local identity secret in NSUserDefaults.
+ (void)resetLocalIdentity;

/// Generates a new local identity and saves it to NSUserDefaults.
+ (NSData *)generateLocalIdentity;

/// Disconnects from the room.
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END