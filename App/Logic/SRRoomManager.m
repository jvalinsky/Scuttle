#import "SRRoomManager.h"
#import "RoomStorage.h"
#import "SRNotificationNames.h"
#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBRoomClient.h"
#import "../../Sources/SSBMetafeed.h"
#import <SSBNetwork/SSBKeychain.h>
#import "RoomInviteHandler.h"
#import <os/log.h>

static os_log_t ssb_room_log;

NSString * const SRRoomManagerDidUpdateRoomsNotification = @"SRRoomManagerDidUpdateRoomsNotification";
NSString * const SRRoomManagerDidUpdateEndpointsNotification = @"SRRoomManagerDidUpdateEndpointsNotification";
NSString * const SRRoomManagerConnectionStatusChangedNotification = @"SRRoomManagerConnectionStatusChangedNotification";

@interface SRRoomManager () <SSBRoomClientDelegate>
@property (nonatomic, strong) NSMutableArray<RoomConfig *> *internalRooms;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBRoomClient *> *internalClients;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *internalRoomEndpoints;
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
        _managerQueue = dispatch_queue_create("com.scuttlebutt.roommanager", DISPATCH_QUEUE_SERIAL);
        
        // Auto-connect to saved rooms
        for (RoomConfig *config in _internalRooms) {
            [self connectToRoom:config];
        }

        // Bootstrap metafeed for existing accounts that predate metafeed support.
        [self bootstrapMetafeedIfNeeded];

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
        NSData *savedIdentity = [SSBKeychain loadIdentitySecret];
        NSString *myId = [SSBKeychain publicIDFromSecret:savedIdentity];
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

    NSData *savedIdentity = [SSBKeychain loadIdentitySecret];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification object:client];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    os_log_info(ssb_room_log, "Client %{public}@ updated endpoints: %lu peers", client.host, (unsigned long)endpoints.count);
    dispatch_async(self.managerQueue, ^{
        self.internalRoomEndpoints[client.host] = endpoints;
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateEndpointsNotification object:client];
    });
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    os_log_error(ssb_room_log, "Client %{public}@ encountered error: %{public}@", client.host, error.localizedDescription);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification object:client];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *userInfo = [@{@"status": status, @"progress": @(progress)} mutableCopy];
        if (author) userInfo[@"author"] = author;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomSyncStatusChangedNotification
                                                            object:client
                                                          userInfo:[userInfo copy]];
    });
}

- (void)roomClientDidSyncLocalFeed:(SSBRoomClient *)client {
    if (!self.needsMetafeedAnnounce) return;

    NSData *identitySecret = [SSBKeychain loadIdentitySecret];
    NSString *classicFeedID = [SSBKeychain publicIDFromSecret:identitySecret];
    NSString *metafeedRootID = [SSBKeychain loadMetafeedRootID];
    if (!classicFeedID || !metafeedRootID) return;

    NSDictionary *content = [SSBMetafeed createMetafeedAnnounceMessage:metafeedRootID
                                                            onMainFeed:classicFeedID
                                                             secretKey:identitySecret];
    if (!content) return;

    NSError *publishError;
    SSBMessage *published = [client publishLocalMessageWithContent:content error:&publishError];
    if (published) {
        [SSBKeychain saveMetafeedAnnounced:YES];
        self.needsMetafeedAnnounce = NO;
        os_log_info(ssb_room_log, "Metafeed announce published on classic feed: %{public}@", metafeedRootID);
    } else {
        os_log_error(ssb_room_log, "Metafeed announce publish failed: %{public}@",
                     publishError.localizedDescription);
        // Leave needsMetafeedAnnounce = YES; will retry on the next sync.
    }
}

- (void)disconnectFromRoom:(NSString *)host {
    SSBRoomClient *client = self.internalClients[host];
    [client disconnect];
}

- (void)resetAccount {
    os_log_info(ssb_room_log, "Resetting account");

    NSArray *clientsSnapshot;
    dispatch_sync(self.managerQueue, ^{
        clientsSnapshot = self.internalClients.allValues;
        [self.internalClients removeAllObjects];
        [self.internalRooms removeAllObjects];
        [self.internalRoomEndpoints removeAllObjects];
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
    if ([SSBKeychain loadMetafeedSeed]) {
        // Still need to re-arm the announce flag if it was never published
        // (e.g. app was killed between bootstrap and first successful sync).
        if (![SSBKeychain loadMetafeedAnnounced]) {
            self.needsMetafeedAnnounce = YES;
        }
        return;
    }

    // No identity = nothing to bootstrap yet; called again after generateLocalIdentity.
    NSData *identitySecret = [SSBKeychain loadIdentitySecret];
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

    if (![SSBKeychain saveMetafeedSeed:seed] || ![SSBKeychain saveMetafeedRootID:rootMetafeed.ID]) {
        os_log_error(ssb_room_log, "Metafeed bootstrap: failed to save to keychain");
        return;
    }

    self.needsMetafeedAnnounce = YES;
    os_log_info(ssb_room_log, "Metafeed bootstrapped: %{public}@", rootMetafeed.ID);
}

- (void)removeRoom:(RoomConfig *)config {
    [RoomStorage removeRoom:config];
    [self disconnectFromRoom:config.host];
    dispatch_sync(self.managerQueue, ^{
        [self.internalClients removeObjectForKey:config.host];
        [self.internalRooms removeObject:config];
        [self.internalRoomEndpoints removeObjectForKey:config.host];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
    });
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

@end