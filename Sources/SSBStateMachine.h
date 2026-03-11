#import <Foundation/Foundation.h>
#import "SSBLogger.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBSyncState) {
    SSBSyncStateIdle = 0,
    SSBSyncStateConnecting = 1,
    SSBSyncStateSyncingLocal = 2,
    SSBSyncStateSyncingRemote = 3,
    SSBSyncStateSynced = 4,
    SSBSyncStateError = 5
};

typedef NS_ENUM(NSInteger, SSBConnectionState) {
    SSBConnectionStateDisconnected = 0,
    SSBConnectionStateConnecting = 1,
    SSBConnectionStateHandshake = 2,
    SSBConnectionStateConnected = 3,
    SSBConnectionStateReconnecting = 4,
    SSBConnectionStateError = 5
};

@interface SSBStateMachine : NSObject

@property (nonatomic, assign) SSBSyncState syncState;
@property (nonatomic, assign) SSBConnectionState connectionState;
@property (nonatomic, assign) SSBLogCategory logCategory;

- (instancetype)initWithCategory:(SSBLogCategory)category;

- (void)transitionToSyncState:(SSBSyncState)newState;
- (void)transitionToConnectionState:(SSBConnectionState)newState;

- (NSString *)syncStateToString:(SSBSyncState)state;
- (NSString *)connectionStateToString:(SSBConnectionState)state;

- (BOOL)canPublish;
- (BOOL)isSyncing;
- (NSString *)diagnosticSummary;

@end

NS_ASSUME_NONNULL_END
