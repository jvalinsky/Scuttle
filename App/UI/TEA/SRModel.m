#import "SRModel.h"

@implementation SRModel

- (instancetype)initWithWorkspaceContext:(SRWorkspaceContext)context
                       activeDestination:(SRDestination)destination
                            selectedRoom:(nullable RoomConfig *)room {
    if (self = [super init]) {
        _workspaceContext = context;
        _activeDestination = destination;
        _selectedRoom = room; 
    }
    return self;
}

- (instancetype)copyWithWorkspaceContext:(SRWorkspaceContext)context {
    return [[[self class] alloc] initWithWorkspaceContext:context
                                        activeDestination:self.activeDestination
                                             selectedRoom:self.selectedRoom];
}

- (instancetype)copyWithActiveDestination:(SRDestination)destination {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:destination
                                             selectedRoom:self.selectedRoom];
}

- (instancetype)copyWithSelectedRoom:(nullable RoomConfig *)room {
    return [[[self class] alloc] initWithWorkspaceContext:self.workspaceContext
                                        activeDestination:self.activeDestination
                                             selectedRoom:room];
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

+ (instancetype)initialModel {
    return [[self alloc] initWithWorkspaceContext:0 activeDestination:0 selectedRoom:nil];
}

@end
