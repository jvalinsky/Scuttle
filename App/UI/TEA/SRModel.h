#import <Foundation/Foundation.h>
#import "../SRWorkspaceTypes.h"

@class RoomConfig;
@class SSBMessage;

NS_ASSUME_NONNULL_BEGIN

@interface SRModel : NSObject <NSCopying>
 
@property (nonatomic, readonly) SRWorkspaceContext workspaceContext;
@property (nonatomic, readonly) SRDestination activeDestination;
@property (nonatomic, readonly, nullable) RoomConfig *selectedRoom;
@property (nonatomic, readonly) NSArray<SSBMessage *> *gitRepos;
@property (nonatomic, readonly) NSArray<RoomConfig *> *rooms;

- (instancetype)initWithWorkspaceContext:(SRWorkspaceContext)context
                       activeDestination:(SRDestination)destination
                            selectedRoom:(nullable RoomConfig *)room
                                gitRepos:(NSArray<SSBMessage *> *)gitRepos
                                   rooms:(NSArray<RoomConfig *> *)rooms;
 
- (instancetype)copyWithWorkspaceContext:(SRWorkspaceContext)context;
- (instancetype)copyWithActiveDestination:(SRDestination)destination;
- (instancetype)copyWithSelectedRoom:(nullable RoomConfig *)room;
- (instancetype)copyWithGitRepos:(NSArray<SSBMessage *> *)gitRepos;
- (instancetype)copyWithRooms:(NSArray<RoomConfig *> *)rooms;

+ (instancetype)initialModel;

@end

NS_ASSUME_NONNULL_END
