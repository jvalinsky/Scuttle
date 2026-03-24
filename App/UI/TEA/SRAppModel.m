#import "SRAppModel.h"

@interface SRAppModel ()
@property (nonatomic, readwrite) SRWorkspaceContext workspace;
@property (nonatomic, readwrite) SRDestination destination;
@property (nonatomic, readwrite) NSArray<RoomConfig *> *rooms;
@property (nonatomic, readwrite) RoomConfig *selectedRoom;
@property (nonatomic, readwrite) NSDictionary<NSString *, NSNumber *> *roomStatuses;
@property (nonatomic, readwrite) NSDictionary<NSString *, NSString *> *roomSyncStatuses;
@property (nonatomic, readwrite) NSDictionary<NSString *, NSNumber *> *roomSyncProgress;
@property (nonatomic, readwrite) NSArray<SSBMessage *> *feed;
@property (nonatomic, readwrite) NSString *currentRoomHost;
@property (nonatomic, readwrite) BOOL hasMoreFeed;
@property (nonatomic, readwrite) NSInteger lastSeq;
@property (nonatomic, readwrite) NSArray<SRPeerModel *> *peers;
@property (nonatomic, readwrite) NSArray<SSBMessage *> *gitRepos;
@property (nonatomic, readwrite) NSArray<NSString *> *channels;
@property (nonatomic, readwrite) NSDictionary<NSString *, id> *localIdentity;
@property (nonatomic, readwrite) NSInteger messageCount;
@property (nonatomic, readwrite) NSInteger followingCount;
@property (nonatomic, readwrite) NSInteger followersCount;
@property (nonatomic, readwrite) SRLoadingState loadingState;
@property (nonatomic, readwrite) NSSet<NSString *> *activeLoads;
@property (nonatomic, readwrite) NSError *error;
@end

@implementation SRAppModel

+ (instancetype)initialModel {
    return [[self alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _workspace = SRWorkspaceContextFeeds;
        _destination = SRDestinationHome;
        _rooms = @[];
        _feed = @[];
        _peers = @[];
        _gitRepos = @[];
        _channels = @[];
        _localIdentity = @{};
        _messageCount = 0;
        _followingCount = 0;
        _followersCount = 0;
        _roomStatuses = @{};
        _roomSyncStatuses = @{};
        _roomSyncProgress = @{};
        _activeLoads = [NSSet set];
        _loadingState = SRLoadingStateIdle;
        _hasMoreFeed = YES;
        _lastSeq = 0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self; // Immutable - copy returns self
}

#pragma mark - Copy Methods

- (instancetype)copyWithWorkspace:(SRWorkspaceContext)workspace {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = SRLoadingStateLoaded;
    m.activeLoads = [self.activeLoads filteredSetUsingPredicate:
                      [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![key isEqualToString:[@"feed:" stringByAppendingString:self.currentRoomHost]];
    }]];
    m.error = self.error;
    return m;
}

- (instancetype)copyWithRooms:(NSArray<RoomConfig *> *)rooms {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithSelectedRoom:(RoomConfig *)room {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = room;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = room.host;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithAppendedFeed:(NSArray<SSBMessage *> *)messages {
    NSMutableArray *newFeed = [self.feed mutableCopy];
    [newFeed addObjectsFromArray:messages];
    
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.feed = [newFeed copy];
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = messages.count >= 20;
    m.lastSeq = messages.count > 0 ? [(SSBMessage *)messages.lastObject sequence] : self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.loadingState = SRLoadingStateLoaded;
    m.activeLoads = [self.activeLoads filteredSetUsingPredicate:
                      [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![key hasPrefix:@"feed:"];
    }]];
    m.error = self.error;
    return m;
}

- (instancetype)copyWithPeers:(NSArray<SRPeerModel *> *)peers {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = peers;
    m.gitRepos = self.gitRepos;
    m.loadingState = SRLoadingStateLoaded;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithPeerUpdate:(SRPeerModel *)peer {
    NSMutableArray *newPeers = [NSMutableArray array];
    BOOL found = NO;
    for (SRPeerModel *p in self.peers) {
        if ([p.peerID isEqualToString:peer.peerID]) {
            [newPeers addObject:peer];
            found = YES;
        } else {
            [newPeers addObject:p];
        }
    }
    if (!found) {
        [newPeers addObject:peer];
    }
    
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = [newPeers copy];
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithGitRepos:(NSArray<SSBMessage *> *)repos {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = repos;
    m.channels = self.channels;
    m.loadingState = SRLoadingStateLoaded;
    m.activeLoads = [self.activeLoads filteredSetUsingPredicate:
                      [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![key isEqualToString:@"git_repos"];
    }]];
    m.error = self.error;
    return m;
}

- (instancetype)copyWithChannels:(NSArray<NSString *> *)channels {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = channels;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithLocalIdentity:(NSDictionary<NSString *, id> *)identity {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = identity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithStats:(NSInteger)messages following:(NSInteger)following followers:(NSInteger)followers {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = messages;
    m.followingCount = following;
    m.followersCount = followers;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithRoomStatus:(NSString *)host status:(NSNumber *)status {
    NSMutableDictionary *newStatuses = [self.roomStatuses mutableCopy];
    newStatuses[host] = status;
    
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = [newStatuses copy];
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithRoomSyncStatus:(NSString *)host status:(NSString *)status progress:(NSNumber *)progress {
    NSMutableDictionary *newStatuses = [self.roomSyncStatuses mutableCopy];
    newStatuses[host] = status;
    NSMutableDictionary *newProgress = [self.roomSyncProgress mutableCopy];
    newProgress[host] = progress;
    
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = [newStatuses copy];
    m.roomSyncProgress = [newProgress copy];
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.channels = self.channels;
    m.localIdentity = self.localIdentity;
    m.messageCount = self.messageCount;
    m.followingCount = self.followingCount;
    m.followersCount = self.followersCount;
    m.loadingState = self.loadingState;
    m.activeLoads = self.activeLoads;
    m.error = self.error;
    return m;
}

- (instancetype)copyWithLoading:(BOOL)loading key:(NSString *)key {
    NSMutableSet *newLoads = [self.activeLoads mutableCopy];
    if (loading) {
        [newLoads addObject:key];
    } else {
        [newLoads removeObject:key];
    }
    
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.loadingState = loading ? SRLoadingStateLoading : (self.activeLoads.count > 1 ? SRLoadingStateLoading : SRLoadingStateLoaded);
    m.activeLoads = [newLoads copy];
    m.error = self.error;
    return m;
}

- (instancetype)copyWithError:(NSError *)error {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.loadingState = SRLoadingStateError;
    m.activeLoads = [NSSet set];
    m.error = error;
    return m;
}

- (instancetype)copyWithClearError {
    SRAppModel *m = [[SRAppModel alloc] init];
    m.workspace = self.workspace;
    m.destination = self.destination;
    m.rooms = self.rooms;
    m.selectedRoom = self.selectedRoom;
    m.roomStatuses = self.roomStatuses;
    m.roomSyncStatuses = self.roomSyncStatuses;
    m.roomSyncProgress = self.roomSyncProgress;
    m.feed = self.feed;
    m.currentRoomHost = self.currentRoomHost;
    m.hasMoreFeed = self.hasMoreFeed;
    m.lastSeq = self.lastSeq;
    m.peers = self.peers;
    m.gitRepos = self.gitRepos;
    m.loadingState = self.feed.count > 0 ? SRLoadingStateLoaded : SRLoadingStateIdle;
    m.activeLoads = self.activeLoads;
    m.error = nil;
    return m;
}

@end
