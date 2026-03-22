#import "SRModel.h"

@implementation SRModel

- (instancetype)initWithWorkspaceContext:(SRWorkspaceContext)context
                       activeDestination:(SRDestination)destination
                            selectedRoom:(nullable RoomConfig *)room
                                gitRepos:(NSArray<SSBMessage *> *)gitRepos {
    if (self = [super init]) {
        _workspaceContext = context;
        _activeDestination = destination;
        _selectedRoom = room; 
        _gitRepos = [gitRepos copy] ?: @[];
    }
    return self;
}

- (instancetype)copyWithWorkspaceContext:(SRWorkspaceContext)context {
    return [[[self class] alloc] initWithWorkspaceContext:context
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:self.gitRepos];
}

- (instancetype)copyWithActiveDestination:(SRDestination)destination {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:destination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:self.gitRepos];
}

- (instancetype)copyWithSelectedRoom:(nullable RoomConfig *)room {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:room
                                                 gitRepos:self.gitRepos];
}

- (instancetype)copyWithGitRepos:(NSArray<SSBMessage *> *)gitRepos {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom
                                                 gitRepos:gitRepos];
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

+ (instancetype)initialModel {
    return [[self alloc] initWithWorkspaceContext:0 activeDestination:0 selectedRoom:nil gitRepos:@[]];
}

@end
