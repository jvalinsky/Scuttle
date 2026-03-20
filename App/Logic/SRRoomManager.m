#import "SRRoomManager.h"
#import "SRDeviceManager.h"
#import "RoomStorage.h"
#import "SRNotificationNames.h"
#import "SRPlatformUI.h"
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBRoomClient.h"
#import "../../Sources/SSBMetafeed.h"
#import "../../Sources/SSBRandom.h"
#import "../../Sources/SSBSecretStore.h"
#import "RoomInviteHandler.h"
#import "../../Sources/SSBLogCompat.h"

static os_log_t ssb_room_log;
static NSString * const kSRPeerDiscoveryLogPath = @"/tmp/scuttle_peer_discovery.log";

static void SRPeerDiscoveryAppend(NSString *line) {
    if (line.length == 0) return;
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.scuttlebutt.room.peerdiag.manager", DISPATCH_QUEUE_SERIAL);
    });

    NSString *full = [NSString stringWithFormat:@"[%@] manager %@\n", [NSDate date], line];
    NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(q, ^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:kSRPeerDiscoveryLogPath]) {
                [fm createFileAtPath:kSRPeerDiscoveryLogPath contents:nil attributes:nil];
            }
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kSRPeerDiscoveryLogPath];
            if (!h) return;
            @try {
                [h seekToEndOfFile];
                [h writeData:data];
            } @catch (__unused NSException *exception) {
            } @finally {
                [h closeFile];
            }
        }
    });
}

NSString * const SRRoomManagerDidUpdateRoomsNotification = @"SRRoomManagerDidUpdateRoomsNotification";
NSString * const SRRoomManagerDidUpdateEndpointsNotification = @"SRRoomManagerDidUpdateEndpointsNotification";
NSString * const SRRoomManagerConnectionStatusChangedNotification = @"SRRoomManagerConnectionStatusChangedNotification";
NSString * const SRRoomManagerEndpointsHostKey = @"SRRoomManagerEndpointsHostKey";
NSString * const SRRoomManagerEndpointsListKey = @"SRRoomManagerEndpointsListKey";

@interface SRRoomManager () <SSBRoomClientDelegate>
@property (nonatomic, strong) NSMutableArray<RoomConfig *> *internalRooms;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBRoomClient *> *internalClients;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *internalRoomEndpoints;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *internalPeerSyncProgressByHost;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *internalPeerSyncStatesByHost;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *internalSyncStatusByHost;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *internalSyncProgressByHost;
@property (nonatomic, strong) dispatch_queue_t managerQueue;
/// Set during bootstrap when a metafeed/announce message still needs to be published.
@property (nonatomic, assign) BOOL needsMetafeedAnnounce;
@end

@implementation SRRoomManager

+ (void)initialize {
    if (self == [SRRoomManager class]) {
        ssb_room_log = os_log_create("com.scuttlebutt.room", "RoomManager");
    }
}

+ (instancetype)sharedManager {
    static SRRoomManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRRoomManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _internalRooms = [[RoomStorage listRooms] mutableCopy];
        _internalClients = [NSMutableDictionary dictionary];
        _internalRoomEndpoints = [NSMutableDictionary dictionary];
        _internalPeerSyncProgressByHost = [NSMutableDictionary dictionary];
        _internalPeerSyncStatesByHost = [NSMutableDictionary dictionary];
        _internalSyncStatusByHost = [NSMutableDictionary dictionary];
        _internalSyncProgressByHost = [NSMutableDictionary dictionary];
        _managerQueue = dispatch_queue_create("com.scuttlebutt.roommanager", DISPATCH_QUEUE_SERIAL);
        
        // Auto-connect to saved rooms
        for (RoomConfig *config in _internalRooms) {
            [self connectToRoom:config];
        }

        // Bootstrap metafeed for existing accounts that predate metafeed support.
        [self bootstrapMetafeedIfNeeded];

        // Defer device registration until after sharedManager initialization completes.
        // Registering synchronously here re-enters +sharedManager via SRDeviceManager.
        dispatch_async(dispatch_get_main_queue(), ^{
            [[SRDeviceManager sharedManager] registerThisDeviceIfNeeded];
        });

        // UI is notified via viewDidLoad pulling state after observers are registered
    }
    return self;
}

- (NSArray<RoomConfig *> *)rooms {
    __block NSArray *copy;
    dispatch_sync(self.managerQueue, ^{ copy = [self.internalRooms copy]; });
    return copy;
}

- (NSDictionary<NSString *, SSBRoomClient *> *)clients {
    __block NSDictionary *copy;
    dispatch_sync(self.managerQueue, ^{ copy = [self.internalClients copy]; });
    return copy;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)roomEndpoints {
    __block NSDictionary *copy;
    dispatch_sync(self.managerQueue, ^{ copy = [self.internalRoomEndpoints copy]; });
    return copy;
}

- (void)joinRoomWithInvite:(NSString *)invite completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if ([invite hasPrefix:@"http"]) {
        NSData *savedIdentity = SSBLoadIdentitySecret();
        NSString *myId = SSBPublicIDFromSecret(savedIdentity);
        if (!myId) {
            if (completion) completion(NO, [NSError errorWithDomain:@"SRRoomManager" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"No identity found. Please reset and create a new identity."}]);
            return;
        }
        
        [RoomInviteHandler resolveHTTPSInvite:invite localId:myId completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
            if (config) {
                [self handleJoinWithConfig:config];
                if (completion) completion(YES, nil);
            } else {
                if (completion) completion(NO, error);
            }
        }];
    } else {
        RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
        if (config) {
            [self handleJoinWithConfig:config];
            if (completion) completion(YES, nil);
        } else {
            if (completion) completion(NO, [NSError errorWithDomain:@"SRRoomManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid invite code"}]);
        }
    }
}

- (void)handleJoinWithConfig:(RoomConfig *)config {
    [RoomStorage saveRoom:config];
    dispatch_sync(self.managerQueue, ^{
        [self.internalRooms addObject:config];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
    });
    [self connectToRoom:config];
}

- (void)connectToRoom:(RoomConfig *)config {
    __block BOOL alreadyExists = NO;
    dispatch_sync(self.managerQueue, ^{
        alreadyExists = (self.internalClients[config.host] != nil);
    });
    if (alreadyExists) {
        os_log_info(ssb_room_log, "Already have a client for %{public}@", config.host);
        return;
    }

    NSData *savedIdentity = SSBLoadIdentitySecret();
    os_log_info(ssb_room_log, "Creating client for %{public}@ (identity present: %d)", config.host, savedIdentity != nil);

    SSBRoomClient *client = [[SSBRoomClient alloc] initWithConfig:config localIdentity:savedIdentity];
    client.delegate = self;
    client.autoReconnect = YES;

    dispatch_sync(self.managerQueue, ^{
        self.internalClients[config.host] = client;
    });
    [client connect];
}

#pragma mark - SSBRoomClientDelegate

- (void)roomClientDidConnect:(SSBRoomClient *)client {
    os_log_info(ssb_room_log, "Client connected to %{public}@", client.host);
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"client connected host=%@", client.host ?: @"<unknown>"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification
                                                            object:client
                                                          userInfo:@{
                                                              @"host": client.host ?: @"",
                                                              @"connected": @YES
                                                          }];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    NSArray<NSString *> *snapshot = [endpoints copy] ?: @[];
    os_log_info(ssb_room_log, "Client %{public}@ updated endpoints: %lu peers", client.host, (unsigned long)snapshot.count);
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"didUpdateEndpoints host=%@ peers=%lu list=%@",
                           client.host ?: @"<unknown>",
                           (unsigned long)snapshot.count,
                           snapshot]);
    dispatch_async(self.managerQueue, ^{
        self.internalRoomEndpoints[client.host] = snapshot;
        os_log_debug(ssb_room_log, "Cached %lu endpoints for %{public}@; posting notification", (unsigned long)snapshot.count, client.host);
        SRPeerDiscoveryAppend([NSString stringWithFormat:@"cached endpoints host=%@ peers=%lu posting notification",
                               client.host ?: @"<unknown>",
                               (unsigned long)snapshot.count]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateEndpointsNotification
                                                                object:client
                                                              userInfo:@{
                                                                  SRRoomManagerEndpointsHostKey: client.host ?: @"",
                                                                  SRRoomManagerEndpointsListKey: snapshot
                                                              }];
        });
    });
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    os_log_error(ssb_room_log, "Client %{public}@ encountered error: %{public}@", client.host, error.localizedDescription);
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"client error host=%@ error=%@",
                           client.host ?: @"<unknown>",
                           error.localizedDescription ?: @"<unknown>"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification
                                                            object:client
                                                          userInfo:@{
                                                              @"host": client.host ?: @"",
                                                              @"connected": @NO,
                                                              @"error": error.localizedDescription ?: @"Unknown error"
                                                          }];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author {
    NSString *host = client.host ?: @"";
    if (host.length == 0 || status.length == 0) {
        return;
    }

    dispatch_async(self.managerQueue, ^{
        NSMutableDictionary<NSString *, NSNumber *> *progressByAuthor = [self.internalPeerSyncProgressByHost[host] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSString *> *statusByAuthor = [self.internalPeerSyncStatesByHost[host] mutableCopy] ?: [NSMutableDictionary dictionary];

        if (author.length > 0) {
            progressByAuthor[author] = @(progress);
            statusByAuthor[author] = status;
            self.internalPeerSyncProgressByHost[host] = [progressByAuthor copy];
            self.internalPeerSyncStatesByHost[host] = [statusByAuthor copy];
        }

        self.internalSyncStatusByHost[host] = status;
        self.internalSyncProgressByHost[host] = @(progress);

        NSMutableDictionary *userInfo = [@{
            SRRoomSyncStatusHostKey: host,
            SRRoomSyncStatusKey: status,
            SRRoomSyncStatusProgressKey: @(progress)
        } mutableCopy];
        if (author.length > 0) {
            userInfo[SRRoomSyncStatusAuthorKey] = author;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomSyncStatusChangedNotification
                                                                object:client
                                                              userInfo:[userInfo copy]];
        });
    });
}

- (void)roomClient:(SSBRoomClient *)client didReplicateMessagesFromPeer:(NSString *)peerId count:(NSInteger)count {
    // After each replication batch, check for metafeed/seed backup messages addressed to us.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self checkForIncomingSeedBackups];
    });

    // Run lipmaa chain verification for any GabbyGrove/Bamboo feeds received from this peer.
    SSBFeedState *state = [client.feedStore feedStateForAuthor:peerId];
    if (!state) return;
    SSBBFEFeedFormat fmt = state.feedFormat;
    if (fmt != SSBBFEFeedFormatGabbygroveV1 && fmt != SSBBFEFeedFormatBamboo) return;

    [client verifyFeedIntegrity:peerId author:peerId format:fmt
                    completion:^(BOOL verified, NSError *error) {
        if (!verified) {
            os_log_error(ssb_room_log,
                "Feed integrity check FAILED for %{public}@: %{public}@",
                peerId, error.localizedDescription);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:SRFeedIntegrityDidUpdateNotification
                              object:nil
                            userInfo:@{@"author": peerId, @"verified": @(verified)}];
        });
    }];
}

- (void)checkForIncomingSeedBackups {
    NSData *identitySecret = SSBLoadIdentitySecret();
    NSString *classicFeedID = SSBPublicIDFromSecret(identitySecret);
    NSData *localSeed = SSBLoadMetafeedSeed();
    if (!localSeed || !classicFeedID) return;

    SSBMetafeed *localMetafeed = [SSBMetafeed createRootMetafeedFromSeed:localSeed];
    if (!localMetafeed) return;

    NSString *metafeedRootID = SSBLoadMetafeedRootID();

    NSArray<SSBMessage *> *seedMessages = [[SSBFeedStore sharedStore]
        messagesOfType:@"metafeed/seed" limit:50];

    for (SSBMessage *msg in seedMessages) {
        NSDictionary *content = msg.content;
        NSString *recipient = content[@"recipient"];
        if (![recipient isEqualToString:classicFeedID] &&
            !(metafeedRootID && [recipient isEqualToString:metafeedRootID])) {
            continue;
        }

        NSData *recoveredSeed = [SSBMetafeed decryptSeedFromMessage:content
                                                           feedKeys:localMetafeed.keys];
        if (!recoveredSeed || recoveredSeed.length != 32) continue;

        // Skip if this is already our current seed.
        if ([recoveredSeed isEqualToData:localSeed]) continue;

        NSString *fromAuthor = msg.author;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self offerSeedRestoreFromAuthor:fromAuthor recoveredSeed:recoveredSeed];
        });
        break; // Only one prompt at a time.
    }
}

- (void)offerSeedRestoreFromAuthor:(NSString *)author recoveredSeed:(NSData *)seed {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Identity Backup Found";
    alert.informativeText = [NSString stringWithFormat:
        @"A metafeed seed backup from %@ was received. Restoring it will replace your "
        @"current metafeed identity tree. Restore now?", author];
    [alert addButtonWithTitle:@"Restore"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    SSBMetafeed *recoveredMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!recoveredMetafeed) return;

    if (SSBSaveMetafeedSeed(seed) &&
        SSBSaveMetafeedRootID(recoveredMetafeed.ID)) {
        SSBSaveMetafeedAnnounced(NO);
        self.needsMetafeedAnnounce = YES;
        os_log_info(ssb_room_log, "Identity restored from backup; new root: %{public}@",
                    recoveredMetafeed.ID);
    }
}

- (void)roomClientDidSyncLocalFeed:(SSBRoomClient *)client {
    if (!self.needsMetafeedAnnounce) return;

    NSData *identitySecret = SSBLoadIdentitySecret();
    NSString *classicFeedID = SSBPublicIDFromSecret(identitySecret);
    NSString *metafeedRootID = SSBLoadMetafeedRootID();
    if (!classicFeedID || !metafeedRootID) return;

    NSDictionary *content = [SSBMetafeed createMetafeedAnnounceMessage:metafeedRootID
                                                            onMainFeed:classicFeedID
                                                             secretKey:identitySecret];
    if (!content) return;

    NSError *publishError;
    SSBMessage *published = [client publishLocalMessageWithContent:content error:&publishError];
    if (published) {
        SSBSaveMetafeedAnnounced(YES);
        self.needsMetafeedAnnounce = NO;
        os_log_info(ssb_room_log, "Metafeed announce published on classic feed: %{public}@", metafeedRootID);

        // Now that the metafeed is live, register this device's sub-feed.
        [[SRDeviceManager sharedManager] registerThisDeviceIfNeeded];
    } else {
        os_log_error(ssb_room_log, "Metafeed announce publish failed: %{public}@",
                     publishError.localizedDescription);
        // Leave needsMetafeedAnnounce = YES; will retry on the next sync.
    }
}

- (void)disconnectFromRoom:(NSString *)host {
    dispatch_sync(self.managerQueue, ^{
        [self.internalRoomEndpoints removeObjectForKey:host];
        [self.internalPeerSyncProgressByHost removeObjectForKey:host];
        [self.internalPeerSyncStatesByHost removeObjectForKey:host];
        [self.internalSyncStatusByHost removeObjectForKey:host];
        [self.internalSyncProgressByHost removeObjectForKey:host];
    });
    SSBRoomClient *client = self.internalClients[host];
    [client disconnect];
}

- (void)resetAccount {
    os_log_info(ssb_room_log, "Resetting account");

    __block NSArray *clientsSnapshot;
    dispatch_sync(self.managerQueue, ^{
        clientsSnapshot = self.internalClients.allValues;
        [self.internalClients removeAllObjects];
        [self.internalRooms removeAllObjects];
        [self.internalRoomEndpoints removeAllObjects];
        [self.internalPeerSyncProgressByHost removeAllObjects];
        [self.internalPeerSyncStatesByHost removeAllObjects];
        [self.internalSyncStatusByHost removeAllObjects];
        [self.internalSyncProgressByHost removeAllObjects];
    });

    for (SSBRoomClient *client in clientsSnapshot) {
        [client disconnect];
    }

    // Clear credentials and DB
    [SSBRoomClient resetLocalIdentity];
    [[SSBFeedStore sharedStore] wipeDatabase];

    // Clear all saved rooms
    for (RoomConfig *config in [[RoomStorage listRooms] copy]) {
        [RoomStorage removeRoom:config];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];

    // Generate new identity and bootstrap its metafeed.
    [SSBRoomClient generateLocalIdentity];
    [self bootstrapMetafeedIfNeeded];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Account Reset";
        alert.informativeText = @"Identity and Database have been wiped. A new identity has been generated and the UI has been updated.";
        [alert runModal];
    });
}

#pragma mark - Metafeed Bootstrap

- (void)bootstrapMetafeedIfNeeded {
    // Nothing to do if a seed is already stored.
    if (SSBLoadMetafeedSeed()) {
        // Still need to re-arm the announce flag if it was never published
        // (e.g. app was killed between bootstrap and first successful sync).
        if (!SSBLoadMetafeedAnnounced()) {
            self.needsMetafeedAnnounce = YES;
        }
        return;
    }

    // No identity = nothing to bootstrap yet; called again after generateLocalIdentity.
    NSData *identitySecret = SSBLoadIdentitySecret();
    if (!identitySecret) return;

    NSData *seed = [SSBMetafeed generateSeed];
    if (!seed) {
        os_log_error(ssb_room_log, "Metafeed bootstrap: failed to generate seed");
        return;
    }

    SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!rootMetafeed) {
        os_log_error(ssb_room_log, "Metafeed bootstrap: failed to derive root metafeed");
        return;
    }

    if (!SSBSaveMetafeedSeed(seed) || !SSBSaveMetafeedRootID(rootMetafeed.ID)) {
        os_log_error(ssb_room_log, "Metafeed bootstrap: failed to save to keychain");
        return;
    }

    self.needsMetafeedAnnounce = YES;
    os_log_info(ssb_room_log, "Metafeed bootstrapped: %{public}@", rootMetafeed.ID);
}

#pragma mark - Key Rotation (Phase 3)

- (void)revokeSubfeed:(NSString *)feedID reason:(nullable NSString *)reason {
    NSData *seed = SSBLoadMetafeedSeed();
    NSString *metafeedRootID = SSBLoadMetafeedRootID();
    if (!seed || !metafeedRootID) {
        os_log_error(ssb_room_log, "revokeSubfeed: no metafeed seed/rootID in keychain");
        return;
    }

    SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!rootMetafeed) return;

    NSDictionary *content = [rootMetafeed tombstoneFeedMessage:feedID reason:reason];
    if (!content) {
        os_log_error(ssb_room_log, "revokeSubfeed: failed to create tombstone message");
        return;
    }

    SSBRoomClient *client = self.clients.allValues.firstObject;
    if (!client) {
        os_log_error(ssb_room_log, "revokeSubfeed: no connected client");
        return;
    }

    NSError *error;
    SSBMessage *published = [client publishLocalMessageWithContent:content error:&error];
    if (published) {
        os_log_info(ssb_room_log, "Tombstoned subfeed %{public}@", feedID);
    } else {
        os_log_error(ssb_room_log, "revokeSubfeed publish failed: %{public}@",
                     error.localizedDescription);
    }
}

- (void)replaceSubfeed:(NSString *)oldFeedID
            completion:(void(^)(NSString *, NSError *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *seed = SSBLoadMetafeedSeed();
        NSString *metafeedRootID = SSBLoadMetafeedRootID();
        if (!seed || !metafeedRootID) {
            NSError *err = [NSError errorWithDomain:@"SRRoomManager" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"No metafeed seed in keychain"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
        if (!rootMetafeed) {
            NSError *err = [NSError errorWithDomain:@"SRRoomManager" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive root metafeed"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        // Use a random nonce so the new key is distinct even if the feed name matches.
        NSMutableData *nonce = [NSMutableData dataWithLength:32];
        (void)SSBFillRandomBytes(nonce.mutableBytes, 32);

        NSDictionary *addContent = [rootMetafeed addDerivedFeedMessage:@"main"
                                                               purpose:SSBMetafeedPurposeV1
                                                                 nonce:nonce];
        if (!addContent) {
            NSError *err = [NSError errorWithDomain:@"SRRoomManager" code:3
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to create add/derived message"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        SSBRoomClient *client = self.clients.allValues.firstObject;
        if (!client) {
            NSError *err = [NSError errorWithDomain:@"SRRoomManager" code:4
                userInfo:@{NSLocalizedDescriptionKey: @"Not connected to a room"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }

        NSError *publishError;
        SSBMessage *addMsg = [client publishLocalMessageWithContent:addContent error:&publishError];
        if (!addMsg) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, publishError); });
            return;
        }

        NSString *newFeedID = addContent[@"subfeed"];
        os_log_info(ssb_room_log, "Derived new subfeed %{public}@; tombstoning old %{public}@",
                    newFeedID, oldFeedID);

        // Tombstone the old feed.
        [self revokeSubfeed:oldFeedID reason:@"replaced by new subfeed"];

        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(newFeedID, nil); });
    });
}

- (void)removeRoom:(RoomConfig *)config {
    [RoomStorage removeRoom:config];
    [self disconnectFromRoom:config.host];
    dispatch_sync(self.managerQueue, ^{
        [self.internalClients removeObjectForKey:config.host];
        [self.internalRooms removeObject:config];
        [self.internalRoomEndpoints removeObjectForKey:config.host];
        [self.internalPeerSyncProgressByHost removeObjectForKey:config.host];
        [self.internalPeerSyncStatesByHost removeObjectForKey:config.host];
        [self.internalSyncStatusByHost removeObjectForKey:config.host];
        [self.internalSyncProgressByHost removeObjectForKey:config.host];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
    });
}

- (NSString *)displayNameForAuthor:(NSString *)author {
    if (author.length == 0) {
        return @"";
    }

    return [[SSBFeedStore sharedStore] displayNameForAuthor:author];
}

- (NSDictionary<NSString *, NSString *> *)peerSyncStatesForHost:(NSString *)host {
    __block NSDictionary<NSString *, NSString *> *snapshot;
    dispatch_sync(self.managerQueue, ^{
        snapshot = [self.internalPeerSyncStatesByHost[host] copy] ?: @{};
    });
    return snapshot;
}

- (NSDictionary<NSString *, NSNumber *> *)peerSyncProgressForHost:(NSString *)host {
    __block NSDictionary<NSString *, NSNumber *> *snapshot;
    dispatch_sync(self.managerQueue, ^{
        snapshot = [self.internalPeerSyncProgressByHost[host] copy] ?: @{};
    });
    return snapshot;
}

- (nullable NSString *)syncStatusForHost:(NSString *)host {
    __block NSString *status;
    dispatch_sync(self.managerQueue, ^{
        status = self.internalSyncStatusByHost[host];
    });
    return status;
}

- (float)syncProgressForHost:(NSString *)host {
    __block float progress = 1.0f;
    dispatch_sync(self.managerQueue, ^{
        NSNumber *value = self.internalSyncProgressByHost[host];
        if (value != nil) {
            progress = value.floatValue;
        }
    });
    return progress;
}

- (void)resolveDisplayNameForAuthor:(NSString *)author completion:(void(^)(NSString *name))completion {
    if (!author) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSBFeedStore *store = [SSBFeedStore sharedStore];
        
        // Check if we already have it cached in the DB
        NSString *cached = [store displayNameForAuthor:author];
        if (![cached isEqualToString:author]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached);
            });
            return;
        }
        
        // Otherwise, scan for an 'about' message
        // querySubset: will trigger a log scan for 'about' if type isn't indexed!
        NSArray<SSBMessage *> *msgs = [store querySubset:@{@"author": author, @"type": @"about"} 
                                               options:@{@"descending": @YES, @"pageSize": @1}];
        
        if (msgs.count > 0) {
            SSBMessage *latestAbout = msgs.firstObject;
            NSString *name = latestAbout.content[@"name"];
            if (name.length > 0) {
                [store setDisplayName:name image:nil forAuthor:author];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(name);
                });
                return;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(author);
        });
    });
}

- (nullable SSBRoomClient *)clientForHost:(NSString *)host {
    __block SSBRoomClient *client;
    dispatch_sync(self.managerQueue, ^{ client = self.internalClients[host]; });
    return client;
}

- (nullable SSBRoomClient *)anyConnectedClient {
    __block SSBRoomClient *connectedClient = nil;
    dispatch_sync(self.managerQueue, ^{
        for (SSBRoomClient *client in self.internalClients.allValues) {
            if (client.isConnected) {
                connectedClient = client;
                break;
            }
        }
    });
    return connectedClient;
}

@end
