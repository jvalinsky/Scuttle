#import "SRUpdate.h"

@implementation SRCmd
- (instancetype)initWithType:(NSString *)type {
    if (self = [super init]) { _type = type; }
    return self;
}
+ (instancetype)cmdWithType:(NSString *)type {
    return [[self alloc] initWithType:type];
}
@end

@implementation SRUpdateResult
- (instancetype)initWithModel:(SRModel *)model commands:(NSArray<SRCmd *> *)commands {
    if (self = [super init]) {
        _model = model;
        _commands = commands;
    }
    return self;
}
@end

@implementation SRUpdate

+ (SRUpdateResult *)updateWithModel:(SRModel *)model msg:(SRMsg *)msg {
    SRModel *newModel = model;
    NSMutableArray<SRCmd *> *cmds = [NSMutableArray array];

    switch (msg.msgType) {
        case SRMsgTypeSetWorkspaceContext:
            newModel = [model copyWithWorkspaceContext:msg.workspaceContext];
            break;
        case SRMsgTypeSelectDestination:
            newModel = [model copyWithActiveDestination:msg.destination];
            break;
        case SRMsgTypeSelectRoom:
            newModel = [model copyWithSelectedRoom:msg.selectedRoom];
            break;
    }

    return [[SRUpdateResult alloc] initWithModel:newModel commands:cmds];
}

@end
