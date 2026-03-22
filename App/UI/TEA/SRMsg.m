#import "SRMsg.h"

@implementation SRMsg

- (instancetype)initWithType:(SRMsgType)type
            workspaceContext:(SRWorkspaceContext)context
                 destination:(SRDestination)destination
                selectedRoom:(nullable RoomConfig *)room
                    gitRepos:(NSArray<SSBMessage *> *)gitRepos {
    if (self = [super init]) {
        _msgType = type;
        _workspaceContext = context;
        _destination = destination;
        _selectedRoom = room;
        _gitRepos = [gitRepos copy] ?: @[];
    }
    return self;
}

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context {
    return [[self alloc] initWithType:SRMsgTypeSetWorkspaceContext
                    workspaceContext:context
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]];
}

+ (instancetype)selectDestination:(SRDestination)destination {
    return [[self alloc] initWithType:SRMsgTypeSelectDestination
                    workspaceContext:0
                         destination:destination
                        selectedRoom:nil
                            gitRepos:@[]];
}

+ (instancetype)selectRoom:(nullable RoomConfig *)room {
    return [[self alloc] initWithType:SRMsgTypeSelectRoom
                    workspaceContext:0 
                         destination:0
                        selectedRoom:room
                            gitRepos:@[]];
}

+ (instancetype)loadGitRepos {
    return [[self alloc] initWithType:SRMsgTypeLoadGitRepos
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:@[]];
}

+ (instancetype)gitReposLoaded:(NSArray<SSBMessage *> *)gitRepos {
    return [[self alloc] initWithType:SRMsgTypeGitReposLoaded
                    workspaceContext:0 
                         destination:0
                        selectedRoom:nil
                            gitRepos:gitRepos];
}

@end
