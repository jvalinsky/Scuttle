#import <Foundation/Foundation.h>
#import "../SRWorkspaceTypes.h"

@class RoomConfig;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRMsgType) {
    SRMsgTypeSetWorkspaceContext,
    SRMsgTypeSelectDestination,
    SRMsgTypeSelectRoom,
};

@interface SRMsg : NSObject

@property (nonatomic, readonly) SRMsgType msgType;

// Payload properties
@property (nonatomic, readonly) SRWorkspaceContext workspaceContext;
@property (nonatomic, readonly) SRDestination destination;
@property (nonatomic, readonly, nullable) RoomConfig *selectedRoom;

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context;
+ (instancetype)selectDestination:(SRDestination)destination;
+ (instancetype)selectRoom:(nullable RoomConfig *)room;

@end

NS_ASSUME_NONNULL_END
