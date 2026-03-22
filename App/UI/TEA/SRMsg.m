#import "SRMsg.h"

@implementation SRMsg

- (instancetype)initWithType:(SRMsgType)type
            workspaceContext:(SRWorkspaceContext)context
                 destination:(SRDestination)destination
                selectedRoom:(nullable RoomConfig *)room {
    if (self = [super init]) {
        _msgType = type;
        _workspaceContext = context;
        _destination = destination;
        _selectedRoom = room;
    }
    return self;
}

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context {
    return [[self alloc] initWithType:SRMsgTypeSetWorkspaceContext
                    workspaceContext:context
                         destination:0
                        selectedRoom:nil];
}

+ (instancetype)selectDestination:(SRDestination)destination {
    return [[self alloc] initWithType:SRMsgTypeSelectDestination
                    workspaceContext:0
                         destination:destination
                        selectedRoom:nil];
}

+ (instancetype)selectRoom:(nullable RoomConfig *)room {
    return [[self alloc] initWithType:SRMsgTypeSelectRoom
                    workspaceContext:0 
                         destination:0
                        selectedRoom:room];
}

@end
