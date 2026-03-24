#import <Foundation/Foundation.h>
#import "../SRWorkspaceTypes.h"
#import "SRPeerModel.h"
#import "SRMsg.h"

@class RoomConfig;
@class SSBMessage;

NS_ASSUME_NONNULL_BEGIN

@interface SRAppModel : NSObject <NSCopying>

// === Workspace State ===
@property (nonatomic, readonly) SRWorkspaceContext workspace;
@property (nonatomic, readonly) SRDestination destination;

// === Rooms ===
@property (nonatomic, readonly) NSArray<RoomConfig *> *rooms;
@property (nonatomic, readonly, nullable) RoomConfig *selectedRoom;
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *roomStatuses; // host -> SRConnectionStatus
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *roomSyncStatuses; // host -> sync status string
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *roomSyncProgress; // host -> sync progress float

// === Feed ===
@property (nonatomic, readonly) NSArray<SSBMessage *> *feed;
@property (nonatomic, readonly) NSString *currentRoomHost;
@property (nonatomic, readonly) BOOL hasMoreFeed;
@property (nonatomic, readonly) NSInteger lastSeq;

// === Peers ===
@property (nonatomic, readonly) NSArray<SRPeerModel *> *peers;

// === Git ===
@property (nonatomic, readonly) NSArray<SSBMessage *> *gitRepos;

// === Loading/Error ===
@property (nonatomic, readonly) SRLoadingState loadingState;
@property (nonatomic, readonly) NSSet<NSString *> *activeLoads;
@property (nonatomic, readonly, nullable) NSError *error;

// === Init ===
+ (instancetype)initialModel;

// === Copy Methods (Immutable Updates) ===
- (instancetype)copyWithWorkspace:(SRWorkspaceContext)workspace;
- (instancetype)copyWithDestination:(SRDestination)destination;
- (instancetype)copyWithRooms:(NSArray<RoomConfig *> *)rooms;
- (instancetype)copyWithSelectedRoom:(nullable RoomConfig *)room;
- (instancetype)copyWithRoomStatus:(NSString *)host status:(NSNumber *)status;
- (instancetype)copyWithRoomSyncStatus:(NSString *)host status:(NSString *)status progress:(NSNumber *)progress;
- (instancetype)copyWithFeed:(NSArray<SSBMessage *> *)messages roomHost:(NSString *)host;
- (instancetype)copyWithAppendedFeed:(NSArray<SSBMessage *> *)messages;
- (instancetype)copyWithPeers:(NSArray<SRPeerModel *> *)peers;
- (instancetype)copyWithPeerUpdate:(SRPeerModel *)peer;
- (instancetype)copyWithGitRepos:(NSArray<SSBMessage *> *)repos;
- (instancetype)copyWithLoading:(BOOL)loading key:(NSString *)key;
- (instancetype)copyWithError:(nullable NSError *)error;
- (instancetype)copyWithClearError;

@end

NS_ASSUME_NONNULL_END
