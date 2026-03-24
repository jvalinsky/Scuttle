#import "SRMsg.h"

@implementation SRMsgResult

+ (instancetype)success:(SSBMessage *)message {
    SRMsgResult *r = [[SRMsgResult alloc] init];
    r->_success = YES;
    r->_message = message;
    return r;
}

+ (instancetype)failure:(NSError *)error {
    SRMsgResult *r = [[SRMsgResult alloc] init];
    r->_success = NO;
    r->_error = error;
    return r;
}

@end

#pragma mark - Private Interface for ivars

@interface SRMsg ()
@property (nonatomic, readwrite) SRMsgType msgType;
@property (nonatomic, readwrite) SRWorkspaceContext workspaceContext;
@property (nonatomic, readwrite) SRDestination destination;
@property (nonatomic, readwrite, nullable) RoomConfig *room;
@property (nonatomic, readwrite, nullable) NSString *roomHost;
@property (nonatomic, readwrite) SRConnectionStatus connectionStatus;
@property (nonatomic, readwrite) NSArray<NSString *> *attendants;
@property (nonatomic, readwrite, nullable) NSString *syncStatus;
@property (nonatomic, readwrite) NSArray<SSBMessage *> *messages;
@property (nonatomic, readwrite, nullable) NSDictionary *messageContent;
@property (nonatomic, readwrite, nullable) NSString *replyToKey;
@property (nonatomic, readwrite, nullable) NSString *contentWarning;
@property (nonatomic, readwrite, nullable) SRMsgResult *result;
@property (nonatomic, readwrite) NSArray<SRPeerModel *> *peers;
@property (nonatomic, readwrite, nullable) NSString *peerID;
@property (nonatomic, readwrite) float syncProgress;
@property (nonatomic, readwrite) NSArray<SSBMessage *> *gitRepos;
@property (nonatomic, readwrite) NSArray<NSString *> *channels;
@property (nonatomic, readwrite) SRLoadingState loadingState;
@property (nonatomic, readwrite, nullable) NSError *error;
@property (nonatomic, readwrite) NSString *loadingKey;
@end

@implementation SRMsg

- (instancetype)init {
    if (self = [super init]) {
        _messages = @[];
        _attendants = @[];
        _peers = @[];
        _gitRepos = @[];
        _loadingState = SRLoadingStateIdle;
    }
    return self;
}

#pragma mark - Workspace Messages

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeSetWorkspaceContext;
    msg.workspaceContext = context;
    return msg;
}

+ (instancetype)selectDestination:(SRDestination)destination {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeSelectDestination;
    msg.destination = destination;
    return msg;
}

#pragma mark - Room Messages

+ (instancetype)loadRooms {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadRooms;
    return msg;
}

+ (instancetype)roomsLoaded:(NSArray<RoomConfig *> *)rooms {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeRoomsLoaded;
    // Store rooms in gitRepos for now as a workaround
    // TODO: Add proper rooms property to SRMsg
    return msg;
}

+ (instancetype)selectRoom:(RoomConfig *)room {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeSelectRoom;
    msg.room = room;
    msg.roomHost = room.host;
    return msg;
}

+ (instancetype)deselectRoom {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeDeselectRoom;
    return msg;
}

+ (instancetype)connectRoom:(RoomConfig *)room {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeConnectRoom;
    msg.room = room;
    msg.roomHost = room.host;
    return msg;
}

+ (instancetype)disconnectRoom:(RoomConfig *)room {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeDisconnectRoom;
    msg.room = room;
    msg.roomHost = room.host;
    return msg;
}

+ (instancetype)roomStatusChanged:(NSString *)host status:(SRConnectionStatus)status {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeRoomStatusChanged;
    msg.roomHost = host;
    msg.connectionStatus = status;
    return msg;
}

+ (instancetype)roomAttendantsUpdated:(NSString *)host attendants:(NSArray<NSString *> *)attendants {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeRoomAttendantsUpdated;
    msg.roomHost = host;
    msg.attendants = attendants;
    return msg;
}

+ (instancetype)roomSyncStatusUpdated:(NSString *)host status:(NSString *)status progress:(float)progress {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeRoomStatusChanged;
    msg.roomHost = host;
    msg.syncStatus = status;
    msg.syncProgress = progress;
    return msg;
}

#pragma mark - Feed Messages

+ (instancetype)loadFeed:(NSString *)roomHost {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadFeed;
    msg.roomHost = roomHost;
    return msg;
}

+ (instancetype)feedLoaded:(NSArray<SSBMessage *> *)messages room:(NSString *)roomHost {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeFeedLoaded;
    msg.messages = messages;
    msg.roomHost = roomHost;
    return msg;
}

+ (instancetype)loadMoreFeed:(NSString *)roomHost beforeSeq:(NSInteger)seq {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadMoreFeed;
    msg.roomHost = roomHost;
    return msg;
}

+ (instancetype)publishMessage:(NSDictionary *)content replyTo:(NSString *)replyKey cw:(NSString *)cw {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypePublishMessage;
    msg.messageContent = content;
    msg.replyToKey = replyKey;
    msg.contentWarning = cw;
    return msg;
}

+ (instancetype)messagePublished:(SSBMessage *)message {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeMessagePublished;
    msg.result = [SRMsgResult success:message];
    return msg;
}

+ (instancetype)publishFailed:(NSError *)error {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypePublishFailed;
    msg.result = [SRMsgResult failure:error];
    msg.error = error;
    return msg;
}

#pragma mark - Peer Messages

+ (instancetype)loadPeers:(NSString *)roomHost {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadPeers;
    msg.roomHost = roomHost;
    return msg;
}

+ (instancetype)peersLoaded:(NSArray<SRPeerModel *> *)peers {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypePeersLoaded;
    msg.peers = peers;
    return msg;
}

+ (instancetype)peerSyncStatusChanged:(NSString *)peerID progress:(float)progress {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypePeerSyncStatusChanged;
    msg.peerID = peerID;
    msg.syncProgress = progress;
    return msg;
}

+ (instancetype)connectToPeer:(NSString *)peerID {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeConnectToPeer;
    msg.peerID = peerID;
    return msg;
}

+ (instancetype)disconnectFromPeer:(NSString *)peerID {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeDisconnectFromPeer;
    msg.peerID = peerID;
    return msg;
}

#pragma mark - Git Messages

+ (instancetype)loadGitRepos {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadGitRepos;
    return msg;
}

+ (instancetype)gitReposLoaded:(NSArray<SSBMessage *> *)repos {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeGitReposLoaded;
    msg.gitRepos = repos;
    return msg;
}

#pragma mark - Channel Messages

+ (instancetype)loadChannels {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeLoadChannels;
    return msg;
}

+ (instancetype)channelsLoaded:(NSArray<NSString *> *)channels {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeChannelsLoaded;
    msg.channels = channels;
    return msg;
}

#pragma mark - Loading/Error Messages

+ (instancetype)setLoading:(BOOL)loading key:(NSString *)key {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeSetLoading;
    msg.loadingState = loading ? SRLoadingStateLoading : SRLoadingStateLoaded;
    msg.loadingKey = key;
    return msg;
}

+ (instancetype)setError:(NSError *)error {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeSetError;
    msg.error = error;
    msg.loadingState = SRLoadingStateError;
    return msg;
}

+ (instancetype)clearError {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeClearError;
    msg.loadingState = SRLoadingStateIdle;
    return msg;
}

#pragma mark - Lifecycle Messages

+ (instancetype)appDidFinishLaunching {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeAppDidFinishLaunching;
    return msg;
}

+ (instancetype)appWillTerminate {
    SRMsg *msg = [[SRMsg alloc] init];
    msg.msgType = SRMsgTypeAppWillTerminate;
    return msg;
}

@end
