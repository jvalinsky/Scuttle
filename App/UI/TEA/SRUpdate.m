#import "SRUpdate.h"

#pragma mark - SRCmd Implementation

@interface SRCmd ()
@property (nonatomic, readwrite) SRCmdType cmdType;
@property (nonatomic, readwrite) id payload;
@end

@implementation SRCmd

+ (instancetype)none {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeNone;
    return cmd;
}

+ (instancetype)loadRooms {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeLoadRooms;
    return cmd;
}

+ (instancetype)connectRoom:(RoomConfig *)room {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeConnectRoom;
    cmd.payload = room;
    return cmd;
}

+ (instancetype)disconnectRoom:(RoomConfig *)room {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeDisconnectRoom;
    cmd.payload = room;
    return cmd;
}

+ (instancetype)loadFeed:(NSString *)roomHost {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeLoadFeed;
    cmd.payload = roomHost;
    return cmd;
}

+ (instancetype)loadMoreFeed:(NSString *)roomHost beforeSeq:(NSInteger)seq {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeLoadMoreFeed;
    cmd.payload = @{@"roomHost": roomHost, @"seq": @(seq)};
    return cmd;
}

+ (instancetype)publishMessage:(NSDictionary *)content replyTo:(NSString *)replyKey cw:(NSString *)cw {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypePublishMessage;
    cmd.payload = @{@"content": content, @"replyTo": replyKey ?: [NSNull null], @"cw": cw ?: [NSNull null]};
    return cmd;
}

+ (instancetype)loadPeers:(NSString *)roomHost {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeLoadPeers;
    cmd.payload = roomHost;
    return cmd;
}

+ (instancetype)connectToPeer:(NSString *)peerID {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeConnectToPeer;
    cmd.payload = peerID;
    return cmd;
}

+ (instancetype)loadGitRepos {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeLoadGitRepos;
    return cmd;
}

+ (instancetype)subscribeRoomStatus:(NSString *)roomHost {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeSubscribeRoomStatus;
    cmd.payload = roomHost;
    return cmd;
}

+ (instancetype)subscribePeers:(NSString *)roomHost {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeSubscribePeers;
    cmd.payload = roomHost;
    return cmd;
}

+ (instancetype)subscribeFeed:(NSString *)roomHost {
    SRCmd *cmd = [[SRCmd alloc] init];
    cmd.cmdType = SRCmdTypeSubscribeFeed;
    cmd.payload = roomHost;
    return cmd;
}

@end

#pragma mark - SRUpdateResult Implementation

@implementation SRUpdateResult

- (instancetype)initWithModel:(SRAppModel *)model commands:(NSArray<SRCmd *> *)commands {
    if (self = [super init]) {
        _model = model;
        _commands = commands;
    }
    return self;
}

+ (instancetype)resultWithModel:(SRAppModel *)model {
    return [[self alloc] initWithModel:model commands:@[]];
}

+ (instancetype)resultWithModel:(SRAppModel *)model cmd:(SRCmd *)cmd {
    return [[self alloc] initWithModel:model commands:cmd ? @[cmd] : @[]];
}

+ (instancetype)resultWithModel:(SRAppModel *)model cmds:(NSArray<SRCmd *> *)cmds {
    return [[self alloc] initWithModel:model commands:cmds];
}

@end

#pragma mark - SRUpdate Implementation

@implementation SRUpdate

+ (SRUpdateResult *)updateWithModel:(SRAppModel *)model msg:(SRMsg *)msg {
    switch (msg.msgType) {
        // === Workspace ===
        case SRMsgTypeSetWorkspaceContext:
            return [SRUpdateResult resultWithModel:[model copyWithWorkspace:msg.workspaceContext]];
            
        case SRMsgTypeSelectDestination:
            return [SRUpdateResult resultWithModel:[model copyWithDestination:msg.destination]];
            
        // === Rooms ===
        case SRMsgTypeLoadRooms:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:@"rooms"]
                                                  cmd:[SRCmd loadRooms]];
            
        case SRMsgTypeRoomsLoaded:
            return [SRUpdateResult resultWithModel:[model copyWithRooms:msg.rooms]
                                                  cmd:[SRCmd loadGitRepos]];
            
        case SRMsgTypeSelectRoom:
            return [SRUpdateResult resultWithModel:[model copyWithSelectedRoom:msg.room]
                                                  cmd:[SRCmd connectRoom:msg.room]];
            
        case SRMsgTypeConnectRoom:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:[@"room:" stringByAppendingString:msg.roomHost]]
                                                  cmd:[SRCmd connectRoom:msg.room]];
            
        case SRMsgTypeDisconnectRoom:
            return [SRUpdateResult resultWithModel:model
                                                  cmd:[SRCmd disconnectRoom:msg.room]];
            
        case SRMsgTypeRoomStatusChanged:
            if (msg.syncStatus) {
                return [SRUpdateResult resultWithModel:[model copyWithRoomSyncStatus:msg.roomHost
                                                                              status:msg.syncStatus
                                                                           progress:@(msg.syncProgress)]];
            }
            return [SRUpdateResult resultWithModel:[model copyWithRoomStatus:msg.roomHost
                                                                   status:@(msg.connectionStatus)]];
            
        case SRMsgTypeRoomAttendantsUpdated:
            // Attendants update - could trigger peer list reload
            return [SRUpdateResult resultWithModel:model];
            
        // === Feed ===
        case SRMsgTypeLoadFeed:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:[@"feed:" stringByAppendingString:msg.roomHost]]
                                                  cmd:[SRCmd loadFeed:msg.roomHost]];
            
        case SRMsgTypeFeedLoaded:
            return [SRUpdateResult resultWithModel:[model copyWithFeed:msg.messages
                                                              roomHost:msg.roomHost]];
            
        case SRMsgTypeLoadMoreFeed:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:@"feed_more"]
                                                  cmd:[SRCmd loadMoreFeed:msg.roomHost
                                                             beforeSeq:model.lastSeq]];
            
        case SRMsgTypePublishMessage:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:@"publish"]
                                                  cmd:[SRCmd publishMessage:msg.messageContent
                                                                replyTo:msg.replyToKey
                                                                      cw:msg.contentWarning]];
            
        case SRMsgTypeMessagePublished:
            return [SRUpdateResult resultWithModel:[model copyWithClearError]];
            
        case SRMsgTypePublishFailed:
            return [SRUpdateResult resultWithModel:[model copyWithError:msg.error]];
            
        // === Peers ===
        case SRMsgTypeLoadPeers:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:[@"peers:" stringByAppendingString:msg.roomHost]]
                                                  cmd:[SRCmd loadPeers:msg.roomHost]];
            
        case SRMsgTypePeersLoaded:
            return [SRUpdateResult resultWithModel:[model copyWithPeers:msg.peers]];
            
        case SRMsgTypePeerSyncStatusChanged: {
            SRPeerSyncState newState = msg.syncProgress >= 1.0f ? SRPeerSyncStateReady : SRPeerSyncStateSyncing;
            SRPeerModel *peer = [[[[SRPeerModel alloc] initWithPeerID:msg.peerID]
                                  copyWithSyncProgress:msg.syncProgress]
                                 copyWithSyncState:newState];
            return [SRUpdateResult resultWithModel:[model copyWithPeerUpdate:peer]];
        }
            
        case SRMsgTypeConnectToPeer:
            return [SRUpdateResult resultWithModel:model
                                                  cmd:[SRCmd connectToPeer:msg.peerID]];
            
        case SRMsgTypeDisconnectFromPeer:
            // No specific command needed - handled by room disconnect
            return [SRUpdateResult resultWithModel:model];
            
        // === Git ===
        case SRMsgTypeLoadGitRepos:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:YES key:@"git_repos"]
                                                  cmd:[SRCmd loadGitRepos]];
            
        case SRMsgTypeGitReposLoaded:
            return [SRUpdateResult resultWithModel:[model copyWithGitRepos:msg.gitRepos]];
            
        // === Loading/Error ===
        case SRMsgTypeSetLoading:
            return [SRUpdateResult resultWithModel:[model copyWithLoading:msg.loadingState == SRLoadingStateLoading
                                                                     key:msg.loadingKey]];
            
        case SRMsgTypeSetError:
            return [SRUpdateResult resultWithModel:[model copyWithError:msg.error]];
            
        case SRMsgTypeClearError:
            return [SRUpdateResult resultWithModel:[model copyWithClearError]];
            
        // === Lifecycle ===
        case SRMsgTypeAppDidFinishLaunching:
            return [SRUpdateResult resultWithModel:model
                                                  cmds:@[[SRCmd loadRooms]]];
            
        case SRMsgTypeAppWillTerminate:
            // Cleanup handled by command executor
            return [SRUpdateResult resultWithModel:model];
    }
    
    return [SRUpdateResult resultWithModel:model];
}

@end
