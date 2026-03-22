#import "SRModel.h"

@implementation SRModel

- (instancetype)initWithWorkspaceContext:(SRWorkspaceContext)context
                       activeDestination:(SRDestination)destination
                            selectedRoom:(nullable RoomConfig *)room
                                gitRepos:(NSArray<SSBMessage *> *)gitRepos
                                   rooms:(NSArray<RoomConfig *> *)rooms {
    if (self = [super init]) {
        _workspaceContext = context;
        _activeDestination = destination;
        _selectedRoom = room; 
        _gitRepos = [gitRepos copy] ?: @[];
        _rooms = [rooms copy] ?: @[];
    }
    return self;
}

- (instancetype)copyWithWorkspaceContext:(SRWorkspaceContext)context {
    return [[[self class] alloc] initWithWorkspaceContext:context
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:self.gitRepos
                                                    rooms:self.rooms];
}

- (instancetype)copyWithActiveDestination:(SRDestination)destination {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:destination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:self.gitRepos
                                                    rooms:self.rooms];
}

- (instancetype)copyWithSelectedRoom:(nullable RoomConfig *)room {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:room
                                                 gitRepos:self.gitRepos
                                                    rooms:self.rooms];
}

- (instancetype)copyWithGitRepos:(NSArray<SSBMessage *> *)gitRepos {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:gitRepos
                                                    rooms:self.rooms];
}

- (instancetype)copyWithRooms:(NSArray<RoomConfig *> *)rooms {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:self.gitRepos
                                                    rooms:rooms];
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

+ (instancetype)initialModel {
    return [[self alloc] initWithWorkspaceContext:0 activeDestination:0 selectedRoom:nil gitRepos:@[] rooms:@[]];
}

@end
