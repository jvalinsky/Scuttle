#import "SRMsg.h"

@implementation SRMsg

- (instancetype)initWithType:(SRMsgType)type
            workspaceContext:(SRWorkspaceContext)context
                 destination:(SRDestination)destination
                selectedRoom:(nullable RoomConfig *)room
                    gitRepos:(NSArray<SSBMessage *> *)gitRepos
                       rooms:(NSArray<RoomConfig *> *)rooms {
    if (self = [super init]) {
        _msgType = type;
        _workspaceContext = context;
        _destination = destination;
        _selectedRoom = room;
        _gitRepos = [gitRepos copy] ?: @[];
        _rooms = [rooms copy] ?: @[];
    }
    return self;
}

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context {
    return [[self alloc] initWithType:SRMsgTypeSetWorkspaceContext
                    workspaceContext:context
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]
                               rooms:@[]];
}

+ (instancetype)selectDestination:(SRDestination)destination {
    return [[self alloc] initWithType:SRMsgTypeSelectDestination
                    workspaceContext:0
                         destination:destination
                        selectedRoom:nil
                            gitRepos:@[]
                               rooms:@[]];
}

+ (instancetype)selectRoom:(nullable RoomConfig *)room {
    return [[self alloc] initWithType:SRMsgTypeSelectRoom
                    workspaceContext:0 
                         destination:0
                        selectedRoom:room
                            gitRepos:@[]
                               rooms:@[]];
}

+ (instancetype)loadGitRepos {
    return [[self alloc] initWithType:SRMsgTypeLoadGitRepos
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]
                               rooms:@[]];
}

+ (instancetype)gitReposLoaded:(NSArray<SSBMessage *> *)gitRepos {
    return [[self alloc] initWithType:SRMsgTypeGitReposLoaded
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:gitRepos
                               rooms:@[]];
}

+ (instancetype)loadRooms {
    return [[self alloc] initWithType:SRMsgTypeLoadRooms
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]
                               rooms:@[]];
}

+ (instancetype)roomsLoaded:(NSArray<RoomConfig *> *)rooms {
    return [[self alloc] initWithType:SRMsgTypeRoomsLoaded
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]
                               rooms:rooms];
}

@end
