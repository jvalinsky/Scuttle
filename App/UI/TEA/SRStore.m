#import "SRStore.h"
#import "../../Logic/SRRoomManager.h"
#import "../../Logic/SRNotificationNames.h"
#import "../../../Sources/SSBFeedStore.h"

static os_log_t store_log;

@interface SRStore ()
@property (nonatomic, strong) SRAppModel *state;
@property (nonatomic, strong) NSMutableArray<void(^)(SRAppModel *)> *subscribers;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray<NSString *> *activeSubscriptions;
@property (nonatomic, strong) dispatch_queue_t subscriptionQueue;
@end

@implementation SRStore

+ (void)initialize {
    if (self == [SRStore class]) {
        store_log = os_log_create("com.scuttlebutt.app", "TEAStore");
    }
}

- (instancetype)init {
    if (self = [super init]) {
        _state = [SRAppModel initialModel];
        _subscribers = [NSMutableArray array];
        _activeSubscriptions = [NSMutableArray array];
        _queue = dispatch_queue_create("com.scuttle.srstore", DISPATCH_QUEUE_SERIAL);
        _subscriptionQueue = dispatch_queue_create("com.scuttle.srstore.subscriptions", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    os_log_info(store_log, "Starting SRStore");
    
    [self subscribeToRoomManagerNotifications];
    
    [self dispatch:[SRMsg appDidFinishLaunching]];
}

- (void)stop {
    os_log_info(store_log, "Stopping SRStore");
    
    dispatch_sync(self.subscriptionQueue, ^{
        for (NSString *name in self.activeSubscriptions) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:name object:nil];
        }
        [self.activeSubscriptions removeAllObjects];
    });
}

#pragma mark - Subscription Management

- (void)subscribeToRoomManagerNotifications {
    dispatch_async(self.subscriptionQueue, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRoomStatusNotification:)
                                                     name:SRRoomManagerConnectionStatusChangedNotification
                                                   object:nil];
        [self.activeSubscriptions addObject:SRRoomManagerConnectionStatusChangedNotification];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleEndpointsNotification:)
                                                     name:SRRoomManagerDidUpdateEndpointsNotification
                                                   object:nil];
        [self.activeSubscriptions addObject:SRRoomManagerDidUpdateEndpointsNotification];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSyncStatusNotification:)
                                                     name:SRRoomSyncStatusChangedNotification
                                                   object:nil];
        [self.activeSubscriptions addObject:SRRoomSyncStatusChangedNotification];
    });
}

- (void)handleRoomStatusNotification:(NSNotification *)n {
    NSString *host = n.userInfo[SRRoomManagerEndpointsHostKey];
    if (!host) return;
    
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:host];
    SRConnectionStatus status = SRConnectionStatusDisconnected;
    if (client) {
        status = SRConnectionStatusConnected;
    }
    
    dispatch_async(self.queue, ^{
        [self dispatch:[SRMsg roomStatusChanged:host status:status]];
    });
}

- (void)handleEndpointsNotification:(NSNotification *)n {
    NSArray *endpoints = n.userInfo[SRRoomManagerEndpointsListKey];
    NSString *host = n.userInfo[SRRoomManagerEndpointsHostKey];
    
    if (host.length > 0 && endpoints.count > 0) {
        dispatch_async(self.queue, ^{
            [self dispatch:[SRMsg roomAttendantsUpdated:host attendants:endpoints]];
        });
    }
}

- (void)handleSyncStatusNotification:(NSNotification *)n {
    NSString *peerID = n.userInfo[SRRoomSyncStatusPeerKey];
    NSNumber *progressNum = n.userInfo[SRRoomSyncStatusProgressKey];
    float progress = progressNum ? progressNum.floatValue : 0.0f;
    
    if (peerID.length > 0) {
        dispatch_async(self.queue, ^{
            [self dispatch:[SRMsg peerSyncStatusChanged:peerID progress:progress]];
        });
    }
}

#pragma mark - Subscriber Management

- (void)subscribe:(void (^)(SRAppModel *))callback {
    dispatch_async(self.queue, ^{
        [self.subscribers addObject:[callback copy]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(self.state);
        });
    });
}

#pragma mark - Dispatch (Core Loop)

- (void)dispatch:(SRMsg *)msg {
    dispatch_async(self.queue, ^{
        SRUpdateResult *result = [SRUpdate updateWithModel:self.state msg:msg];
        self.state = result.model;
        
        for (SRCmd *cmd in result.commands) {
            [self executeCommand:cmd];
        }
        
        SRAppModel *currentState = self.state;
        NSArray *subs = [self.subscribers copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^sub)(SRAppModel *) in subs) {
                sub(currentState);
            }
        });
    });
}

#pragma mark - Command Execution

- (void)executeCommand:(SRCmd *)cmd {
    if (cmd.cmdType == SRCmdTypeNone) return;
    
    os_log_debug(store_log, "Executing command: %d", (int)cmd.cmdType);
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        switch (cmd.cmdType) {
            case SRCmdTypeLoadRooms:
                [self cmdLoadRooms];
                break;
                
            case SRCmdTypeConnectRoom:
                [self cmdConnectRoom:cmd.payload];
                break;
                
            case SRCmdTypeDisconnectRoom:
                [self cmdDisconnectRoom:cmd.payload];
                break;
                
            case SRCmdTypeLoadFeed:
                [self cmdLoadFeed:cmd.payload];
                break;
                
            case SRCmdTypeLoadMoreFeed:
                [self cmdLoadMoreFeed:cmd.payload];
                break;
                
            case SRCmdTypePublishMessage:
                [self cmdPublishMessage:cmd.payload];
                break;
                
            case SRCmdTypeLoadPeers:
                [self cmdLoadPeers:cmd.payload];
                break;
                
            case SRCmdTypeConnectToPeer:
                break;
                
            case SRCmdTypeLoadGitRepos:
                [self cmdLoadGitRepos];
                break;
                
            case SRCmdTypeSubscribeRoomStatus:
            case SRCmdTypeSubscribePeers:
            case SRCmdTypeSubscribeFeed:
                break;
                
            default:
                os_log_debug(store_log, "Unhandled command type: %d", (int)cmd.cmdType);
                break;
        }
    });
}

#pragma mark - Command Implementations

- (void)cmdLoadRooms {
    NSArray *rooms = [[SRRoomManager sharedManager] rooms];
    [self dispatch:[SRMsg roomsLoaded:rooms]];
}

- (void)cmdConnectRoom:(RoomConfig *)room {
    [[SRRoomManager sharedManager] connectToRoom:room];
    [self dispatch:[SRMsg roomStatusChanged:room.host status:SRConnectionStatusConnecting]];
}

- (void)cmdDisconnectRoom:(NSString *)host {
    [[SRRoomManager sharedManager] disconnectFromRoom:host];
    [self dispatch:[SRMsg roomStatusChanged:host status:SRConnectionStatusDisconnected]];
}

- (void)cmdLoadFeed:(NSString *)roomHost {
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:roomHost];
    NSArray<SSBMessage *> *messages = [[SSBFeedStore sharedStore] timelineWithLimit:20];
    [self dispatch:[SRMsg feedLoaded:messages room:roomHost]];
}

- (void)cmdLoadMoreFeed:(NSDictionary *)payload {
    NSString *roomHost = payload[@"roomHost"];
    NSNumber *seqNum = payload[@"seq"];
    NSInteger seq = seqNum ? seqNum.integerValue : 0;
    
    NSArray<SSBMessage *> *messages = [[SSBFeedStore sharedStore] messagesForAuthor:nil
                                                                      fromSequence:seq + 1
                                                                             limit:20];
    [self dispatch:[SRMsg feedLoaded:messages room:roomHost]];
}

- (void)cmdPublishMessage:(NSDictionary *)payload {
    NSDictionary *content = payload[@"content"];
    os_log_info(store_log, "Publish message with content type: %@", content[@"type"]);
    [self dispatch:[SRMsg messagePublished:nil]];
    
    if (self.state.currentRoomHost.length > 0) {
        [self dispatch:[SRMsg loadFeed:self.state.currentRoomHost]];
    }
}

- (void)cmdLoadPeers:(NSString *)roomHost {
    NSMutableSet<NSString *> *allPeers = [NSMutableSet setWithArray:[[SSBFeedStore sharedStore] allKnownAuthors]];
    
    if (roomHost.length > 0) {
        NSArray<NSString *> *endpoints = [[SRRoomManager sharedManager] roomEndpoints][roomHost];
        if (endpoints) {
            [allPeers addObjectsFromArray:endpoints];
        }
    }
    
    NSMutableArray<SRPeerModel *> *peers = [NSMutableArray array];
    for (NSString *peerID in allPeers) {
        SRPeerModel *peer = [[[SRPeerModel alloc] initWithPeerID:peerID] copyWithSyncState:SRPeerSyncStateDisconnected];
        [peers addObject:peer];
    }
    
    [self dispatch:[SRMsg peersLoaded:peers]];
}

- (void)cmdLoadGitRepos {
    NSArray<SSBMessage *> *repos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
    [self dispatch:[SRMsg gitReposLoaded:repos]];
}

@end
