#import "SRPeerModel.h"

@interface SRPeerModel ()
@property (nonatomic, readwrite) NSString *peerID;
@property (nonatomic, readwrite, nullable) NSString *displayName;
@property (nonatomic, readwrite) SRPeerSyncState syncState;
@property (nonatomic, readwrite) float syncProgress;
@property (nonatomic, readwrite) NSInteger messageCount;
@property (nonatomic, readwrite) BOOL isLocal;
@end

@implementation SRPeerModel

- (instancetype)initWithPeerID:(NSString *)peerID {
    if (self = [super init]) {
        _peerID = [peerID copy];
        _syncState = SRPeerSyncStateDisconnected;
        _syncProgress = 0.0f;
        _messageCount = 0;
        _isLocal = NO;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SRPeerModel *copy = [[SRPeerModel alloc] initWithPeerID:self.peerID];
    copy.displayName = self.displayName;
    copy.syncState = self.syncState;
    copy.syncProgress = self.syncProgress;
    copy.messageCount = self.messageCount;
    copy.isLocal = self.isLocal;
    return copy;
}

- (instancetype)copyWithSyncState:(SRPeerSyncState)state {
    SRPeerModel *copy = [self copy];
    copy.syncState = state;
    return copy;
}

- (instancetype)copyWithSyncProgress:(float)progress {
    SRPeerModel *copy = [self copy];
    copy.syncProgress = progress;
    return copy;
}

- (instancetype)copyWithMessageCount:(NSInteger)count {
    SRPeerModel *copy = [self copy];
    copy.messageCount = count;
    return copy;
}

- (instancetype)copyWithDisplayName:(NSString *)name {
    SRPeerModel *copy = [self copy];
    copy.displayName = name;
    return copy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SRPeerModel: %@ syncState=%ld progress=%.2f>",
            self.peerID, (long)self.syncState, self.syncProgress];
}

@end
