#import "SSBStateMachine.h"

@implementation SSBStateMachine

- (instancetype)initWithCategory:(SSBLogCategory)category {
    self = [super init];
    if (self) {
        _syncState = SSBSyncStateIdle;
        _connectionState = SSBConnectionStateDisconnected;
        _logCategory = category;
    }
    return self;
}

- (void)transitionToSyncState:(SSBSyncState)newState {
    if (self.syncState == newState) return;
    
    NSString *fromStr = [self syncStateToString:self.syncState];
    NSString *toStr = [self syncStateToString:newState];
    
    SSBLogInfo(self.logCategory, @"🔄 Sync State: %@ → %@", fromStr, toStr);
    
    self.syncState = newState;
}

- (void)transitionToConnectionState:(SSBConnectionState)newState {
    if (self.connectionState == newState) return;
    
    NSString *fromStr = [self connectionStateToString:self.connectionState];
    NSString *toStr = [self connectionStateToString:newState];
    
    SSBLogInfo(self.logCategory, @"🔗 Connection State: %@ → %@", fromStr, toStr);
    
    self.connectionState = newState;
}

- (NSString *)syncStateToString:(SSBSyncState)state {
    switch (state) {
        case SSBSyncStateIdle: return @"Idle";
        case SSBSyncStateConnecting: return @"Connecting";
        case SSBSyncStateSyncingLocal: return @"SyncingLocal";
        case SSBSyncStateSyncingRemote: return @"SyncingRemote";
        case SSBSyncStateSynced: return @"Synced";
        case SSBSyncStateError: return @"Error";
    }
}

- (NSString *)connectionStateToString:(SSBConnectionState)state {
    switch (state) {
        case SSBConnectionStateDisconnected: return @"Disconnected";
        case SSBConnectionStateConnecting: return @"Connecting";
        case SSBConnectionStateHandshake: return @"Handshake";
        case SSBConnectionStateConnected: return @"Connected";
        case SSBConnectionStateReconnecting: return @"Reconnecting";
        case SSBConnectionStateError: return @"Error";
    }
}

- (BOOL)canPublish {
    return self.connectionState == SSBConnectionStateConnected && 
           (self.syncState == SSBSyncStateSynced || self.syncState == SSBSyncStateIdle);
}

- (BOOL)isSyncing {
    return self.syncState == SSBSyncStateSyncingLocal || 
           self.syncState == SSBSyncStateSyncingRemote ||
           self.syncState == SSBSyncStateConnecting;
}

- (NSString *)diagnosticSummary {
    return [NSString stringWithFormat:@"[StateMachine] Connection: %@, Sync: %@, CanPublish: %@, IsSyncing: %@",
            [self connectionStateToString:self.connectionState],
            [self syncStateToString:self.syncState],
            self.canPublish ? @"YES" : @"NO",
            self.isSyncing ? @"YES" : @"NO"];
}

@end
