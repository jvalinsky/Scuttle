#import <Foundation/Foundation.h>
#import "../SRWorkspaceTypes.h"

@class RoomConfig;
@class SSBMessage;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRMsgType) {
    SRMsgTypeSetWorkspaceContext,
    SRMsgTypeSelectDestination,
    SRMsgTypeSelectRoom,
    SRMsgTypeLoadGitRepos,
    SRMsgTypeGitReposLoaded,
};

@interface SRMsg : NSObject

@property (nonatomic, readonly) SRMsgType msgType;

// Payload properties
@property (nonatomic, readonly) SRWorkspaceContext workspaceContext;
@property (nonatomic, readonly) SRDestination destination;
@property (nonatomic, readonly, nullable) RoomConfig *selectedRoom;
@property (nonatomic, readonly) NSArray<SSBMessage *> *gitRepos;

+ (instancetype)setWorkspaceContext:(SRWorkspaceContext)context;
+ (instancetype)selectDestination:(SRDestination)destination;
+ (instancetype)selectRoom:(nullable RoomConfig *)room;
+ (instancetype)loadGitRepos;
+ (instancetype)gitReposLoaded:(NSArray<SSBMessage *> *)gitRepos;

@end

NS_ASSUME_NONNULL_END
