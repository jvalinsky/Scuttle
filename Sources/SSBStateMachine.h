#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBLogger.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBSyncState) {
    SSBSyncStateIdle = 0,
    SSBSyncStateConnecting = 1,
    SSBSyncStateSyncingLocal = 2,
    SSBSyncStateSyncingRemote = 3,
    SSBSyncStateSynced = 4,
    SSBSyncStateError = 5
};

typedef NS_ENUM(NSInteger, SSBClientConnectionState) {
    SSBClientConnectionStateDisconnected = 0,
    SSBClientConnectionStateConnecting = 1,
    SSBClientConnectionStateHandshake = 2,
    SSBClientConnectionStateConnected = 3,
    SSBClientConnectionStateReconnecting = 4,
    SSBClientConnectionStateError = 5
};

@interface SSBStateMachine : NSObject

@property (nonatomic, assign) SSBSyncState syncState;
@property (nonatomic, assign) SSBClientConnectionState connectionState;
@property (nonatomic, assign) SSBLogCategory logCategory;

- (instancetype)initWithCategory:(SSBLogCategory)category;

- (void)transitionToSyncState:(SSBSyncState)newState;
- (void)transitionToConnectionState:(SSBClientConnectionState)newState;

- (NSString *)syncStateToString:(SSBSyncState)state;
- (NSString *)connectionStateToString:(SSBClientConnectionState)state;

- (BOOL)canPublish;
- (BOOL)isSyncing;
- (NSString *)diagnosticSummary;

@end

NS_ASSUME_NONNULL_END
