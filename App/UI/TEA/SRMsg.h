#import <Foundation/Foundation.h>
#import "../SRWorkspaceTypes.h"
#import "../../../Sources/RoomInviteHandler.h"
#import "../../../Sources/SSBMessage.h"

@class SRPeerModel;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Message Types

typedef NS_ENUM(NSInteger, SRMsgType) {
    // === Workspace ===
    SRMsgTypeSetWorkspaceContext,
    SRMsgTypeSelectDestination,
    
    // === Rooms ===
    SRMsgTypeLoadRooms,
    SRMsgTypeRoomsLoaded,
    SRMsgTypeSelectRoom,
    SRMsgTypeConnectRoom,
    SRMsgTypeDisconnectRoom,
    SRMsgTypeRoomStatusChanged,
    SRMsgTypeRoomAttendantsUpdated,
    
    // === Feed ===
    SRMsgTypeLoadFeed,
    SRMsgTypeFeedLoaded,
    SRMsgTypeLoadMoreFeed,
    SRMsgTypePublishMessage,
    SRMsgTypeMessagePublished,
    SRMsgTypePublishFailed,
    
    // === Peers ===
    SRMsgTypeLoadPeers,
    SRMsgTypePeersLoaded,
    SRMsgTypePeerSyncStatusChanged,
    SRMsgTypeConnectToPeer,
    SRMsgTypeDisconnectFromPeer,
    
    // === Git ===
    SRMsgTypeLoadGitRepos,
    SRMsgTypeGitReposLoaded,
    
    // === Channels ===
    SRMsgTypeLoadChannels,
    SRMsgTypeChannelsLoaded,
    
    // === Loading States ===
    SRMsgTypeSetLoading,
    SRMsgTypeSetError,
    SRMsgTypeClearError,
    
    // === App Lifecycle ===
    SRMsgTypeAppDidFinishLaunching,
    SRMsgTypeAppWillTerminate,
};

#pragma mark - Loading State

typedef NS_ENUM(NSInteger, SRLoadingState) {
    SRLoadingStateIdle = 0,
    SRLoadingStateLoading,
    SRLoadingStateLoaded,
    SRLoadingStateError
};

#pragma mark - Connection Status

typedef NS_ENUM(NSInteger, SRConnectionStatus) {
    SRConnectionStatusDisconnected = 0,
    SRConnectionStatusConnecting,
    SRConnectionStatusConnected,
    SRConnectionStatusReconnecting,
    SRConnectionStatusError
};

#pragma mark - Message Result

@interface SRMsgResult : NSObject
@property (nonatomic, readonly) BOOL success;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly, nullable) SSBMessage *message;
+ (instancetype)success:(nullable SSBMessage *)message;
+ (instancetype)failure:(NSError *)error;
@end

#pragma mark - Message (Discriminated Union)

@interface SRMsg : NSObject

@property (nonatomic, readonly) SRMsgType msgType;

// Workspace
@property (nonatomic, readonly) SRWorkspaceContext workspaceContext;
@property (nonatomic, readonly) SRDestination destination;

// Rooms
@property (nonatomic, readonly, nullable) RoomConfig *room;
@property (nonatomic, readonly) NSArray<RoomConfig *> *rooms;
@property (nonatomic, readonly, nullable) NSString *roomHost;
@property (nonatomic, readonly) SRConnectionStatus connectionStatus;
@property (nonatomic, readonly) NSArray<NSString *> *attendants;
@property (nonatomic, readonly, nullable) NSString *syncStatus;

// Feed
@property (nonatomic, readonly) NSArray<SSBMessage *> *messages;
@property (nonatomic, readonly, nullable) NSDictionary *messageContent;
@property (nonatomic, readonly, nullable) NSString *replyToKey;
@property (nonatomic, readonly, nullable) NSString *contentWarning;
@property (nonatomic, readonly, nullable) SRMsgResult *result;

// Peers
@property (nonatomic, readonly) NSArray<SRPeerModel *> *peers;
@property (nonatomic, readonly, nullable) NSString *peerID;
@property (nonatomic, readonly) float syncProgress;

// Git
@property (nonatomic, readonly) NSArray<SSBMessage *> *gitRepos;

// Channels
@property (nonatomic, readonly) NSArray<NSString *> *channels;

// Loading/Error
@property (nonatomic, readonly) SRLoadingState loadingState;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly) NSString *loadingKey;

#pragma mark - Workspace Messages
+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context;
+ (instancetype)selectDestination:(SRDestination)destination;

#pragma mark - Room Messages
+ (instancetype)loadRooms;
+ (instancetype)roomsLoaded:(NSArray<RoomConfig *> *)rooms;
+ (instancetype)selectRoom:(nullable RoomConfig *)room;
+ (instancetype)connectRoom:(RoomConfig *)room;
+ (instancetype)disconnectRoom:(nullable RoomConfig *)room;
+ (instancetype)roomStatusChanged:(NSString *)host status:(SRConnectionStatus)status;
+ (instancetype)roomAttendantsUpdated:(NSString *)host attendants:(NSArray<NSString *> *)attendants;
+ (instancetype)roomSyncStatusUpdated:(NSString *)host status:(nullable NSString *)status progress:(float)progress;

#pragma mark - Feed Messages
+ (instancetype)loadFeed:(NSString *)roomHost;
+ (instancetype)feedLoaded:(NSArray<SSBMessage *> *)messages room:(NSString *)roomHost;
+ (instancetype)loadMoreFeed:(NSString *)roomHost beforeSeq:(NSInteger)seq;
+ (instancetype)publishMessage:(NSDictionary *)content replyTo:(nullable NSString *)replyKey cw:(nullable NSString *)cw;
+ (instancetype)messagePublished:(nullable SSBMessage *)message;
+ (instancetype)publishFailed:(NSError *)error;

#pragma mark - Peer Messages
+ (instancetype)loadPeers:(NSString *)roomHost;
+ (instancetype)peersLoaded:(NSArray<SRPeerModel *> *)peers;
+ (instancetype)peerSyncStatusChanged:(NSString *)peerID progress:(float)progress;
+ (instancetype)connectToPeer:(NSString *)peerID;
+ (instancetype)disconnectFromPeer:(NSString *)peerID;

#pragma mark - Git Messages
+ (instancetype)loadGitRepos;
+ (instancetype)gitReposLoaded:(NSArray<SSBMessage *> *)repos;

#pragma mark - Channel Messages
+ (instancetype)loadChannels;
+ (instancetype)channelsLoaded:(NSArray<NSString *> *)channels;

#pragma mark - Loading/Error Messages
+ (instancetype)setLoading:(BOOL)loading key:(NSString *)key;
+ (instancetype)setError:(NSError *)error;
+ (instancetype)clearError;

#pragma mark - Lifecycle Messages
+ (instancetype)appDidFinishLaunching;
+ (instancetype)appWillTerminate;

@end

NS_ASSUME_NONNULL_END
