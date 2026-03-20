#import "SSBRoomClient.h"
#import "SSBLogCompat.h"
#import "SSBMuxRPCSession.h"
#import "SSBQueryEngine.h"
#import "SSBMuxRPC.h"
#import "SSBSecretStore.h"
#import "../App/Logic/SRNotificationNames.h"
#import "SSBSecretHandshake.h"
#import "SSBBlobStore.h"
#import "tweetnacl.h"
#import "SSBTunnelConnection.h"
#import "SSBBamboo.h"
#import "SSBFeedCodecRegistry.h"
#import <stdlib.h>

static os_log_t ssb_room_log;
static NSString * const kSRPeerDiscoveryLogPath = @"/tmp/scuttle_peer_discovery.log";

@interface SSBRoomClient ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *serverPubKey;
@property (nonatomic, strong) NSData *localIdentitySecret;
@property (nonatomic, strong, nullable) NSString *inviteToken;
@property (nonatomic, assign) BOOL usedHTTPInvite;
@property (nonatomic, readwrite) BOOL isConnected;
@property (nonatomic, assign) BOOL isFeedSynced;

@property (nonatomic, strong) id<SSBTransportConnection> connection;
@property (nonatomic, strong) id<SSBTransportBackend> transportBackend;
@property (nonatomic, strong) SSBMuxRPCSession *rpcSession;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSDictionary *serverManifest;
@property (nonatomic, strong) NSMutableArray<NSString *> *attendantsList;
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, readwrite, nullable) NSArray<NSString *> *roomFeatures;
@property (nonatomic, copy, nullable) NSArray<NSString *> *endpointDiscoveryMethodInUse;
@property (nonatomic, assign) uint64_t endpointDiscoverySubscriptionGeneration;
@property (nonatomic, assign) BOOL endpointDiscoveryReceivedEvent;
@property (nonatomic, readwrite) BOOL isInternalUser;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBTunnelConnection *> *activeTunnels;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingPublishQueue;
@property (nonatomic, assign) BOOL isSyncingLocalFeed;
@property (nonatomic, assign) NSInteger localFeedSeq;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *remoteClock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *internalPeerSyncProgress;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *internalPeerSyncStates;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *peerNextTunnelRetryAt;
@property (nonatomic, strong) NSMapTable<SSBMuxRPCSession *, NSNumber *> *ebtRequestIDsBySession;

/// Tracks per-peer EBT state to handle bilateral replication properly.
/// Key: peer ID, Value: dictionary with { @"requestID": NSNumber, @"clock": NSMutableDictionary }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *peerEBTState;
@end

@implementation SSBRoomClient

+ (void)initialize {
    if (self == [SSBRoomClient class]) {
        ssb_room_log = os_log_create("com.scuttlebutt.room", "Client");
    }
}

- (void)appendPeerDiscoveryDiagnostic:(NSString *)message {
    if (message.length == 0) {
        return;
    }

    static dispatch_queue_t diagQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diagQueue = dispatch_queue_create("com.scuttlebutt.room.peerdiag", DISPATCH_QUEUE_SERIAL);
    });

    NSString *host = self.host ?: @"<unknown-host>";
    NSString *line = [NSString stringWithFormat:@"[%@] host=%@ %@\n", [NSDate date], host, message];
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];

    dispatch_async(diagQueue, ^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:kSRPeerDiscoveryLogPath]) {
                [fm createFileAtPath:kSRPeerDiscoveryLogPath contents:nil attributes:nil];
            }

            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kSRPeerDiscoveryLogPath];
            if (!handle) {
                return;
            }
            @try {
                [handle seekToEndOfFile];
                [handle writeData:lineData];
            } @catch (__unused NSException *exception) {
                // Ignore diagnostic write failures.
            } @finally {
                [handle closeFile];
            }
        }
    });
}

- (instancetype)initWithHost:(NSString *)host 
                        port:(uint16_t)port 
                serverPubKey:(NSData *)serverPubKey 
               localIdentity:(nullable NSData *)localIdentitySecret {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _serverPubKey = serverPubKey;
        
        if (localIdentitySecret) {
            _localIdentitySecret = localIdentitySecret;
        } else {
            NSData *saved = SSBLoadIdentitySecret();
            if (saved) {
                _localIdentitySecret = saved;
            } else {
                _localIdentitySecret = [SSBRoomClient generateLocalIdentity];
            }
        }
        
        _isConnected = NO;
        _isFeedSynced = YES; // Assume synced until proven otherwise
        _clientQueue = dispatch_queue_create("com.ssbc.room.client", DISPATCH_QUEUE_SERIAL);
        _transportBackend = [SSBTransport defaultBackend];
        _rpcSession = [[SSBMuxRPCSession alloc] init];
        
        __weak typeof(self) weakSelf = self;
        _rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
            [weakSelf sendRPCMessage:message];
        };
        _rpcSession.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
            [weakSelf handleServerInitiatedRequest:payload requestID:requestID flags:flags];
        };
        
        _attendantsList = [NSMutableArray array];
        _feedStore = [SSBFeedStore sharedStore];
        _activeTunnels = [NSMutableDictionary dictionary];
        _pendingPublishQueue = [NSMutableArray array];
        _internalPeerSyncProgress = [NSMutableDictionary dictionary];
        _internalPeerSyncStates = [NSMutableDictionary dictionary];
        _peerNextTunnelRetryAt = [NSMutableDictionary dictionary];
        _remoteClock = [NSMutableDictionary dictionary];
        _ebtRequestIDsBySession = [NSMapTable weakToStrongObjectsMapTable];
        _peerEBTState = [NSMutableDictionary dictionary];
        _isSyncingLocalFeed = NO;
        
        // Load local feed sequence from store
        NSString *myId = [self localPublicID];
        SSBFeedState *state = [_feedStore feedStateForAuthor:myId];
        _localFeedSeq = state ? state.maxSequence : 0;
    }
    return self;
}

- (NSDictionary<NSString *, NSNumber *> *)peerSyncProgress {
    __block NSDictionary *snapshot;
    dispatch_sync(self.clientQueue, ^{
        snapshot = [self.internalPeerSyncProgress copy];
    });
    return snapshot;
}

- (NSDictionary<NSString *, NSString *> *)peerSyncStates {
    __block NSDictionary *snapshot;
    dispatch_sync(self.clientQueue, ^{
        snapshot = [self.internalPeerSyncStates copy];
    });
    return snapshot;
}

#pragma mark - Thread-Safe Accessors

- (NSArray<NSString *> *)currentAttendants {
    __block NSArray *snapshot;
    dispatch_sync(self.clientQueue, ^{
        snapshot = [self.attendantsList copy];
    });
    return snapshot;
}

- (nullable NSString *)peerIDFromEndpointItem:(id)item {
    if ([item isKindOfClass:[NSString class]]) {
        return [(NSString *)item length] > 0 ? item : nil;
    }
    if ([item isKindOfClass:[NSArray class]]) {
        for (id candidate in (NSArray *)item) {
            NSString *peerID = [self peerIDFromEndpointItem:candidate];
            if (peerID.length > 0) {
                return peerID;
            }
        }
        return nil;
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)item;
        id direct = dict[@"id"] ?: dict[@"key"] ?: dict[@"feed"];
        if ([direct isKindOfClass:[NSString class]] && [(NSString *)direct length] > 0) {
            return (NSString *)direct;
        }

        // Some room implementations wrap identity under nested "peer" or "value" objects.
        NSString *nestedPeer = [self peerIDFromEndpointItem:dict[@"peer"]];
        if (nestedPeer.length > 0) {
            return nestedPeer;
        }
        NSString *nestedValue = [self peerIDFromEndpointItem:dict[@"value"]];
        if (nestedValue.length > 0) {
            return nestedValue;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)normalizedPeerIDsFromCollection:(NSArray *)items {
    NSMutableArray<NSString *> *peerIDs = [NSMutableArray array];
    for (id item in items) {
        NSString *peerID = [self peerIDFromEndpointItem:item];
        if (peerID.length > 0 && ![peerIDs containsObject:peerID]) {
            [peerIDs addObject:peerID];
        }
    }
    return [peerIDs copy];
}

- (NSArray<NSString *> *)filteredAttendantPeerIDs:(NSArray<NSString *> *)peerIDs {
    NSString *localPeerID = [self localPublicID];
    NSMutableArray<NSString *> *filtered = [NSMutableArray arrayWithCapacity:peerIDs.count];

    for (NSString *peerID in peerIDs) {
        if (peerID.length == 0) {
            continue;
        }
        if (localPeerID.length > 0 && [peerID isEqualToString:localPeerID]) {
            continue;
        }
        if (![filtered containsObject:peerID]) {
            [filtered addObject:peerID];
        }
    }

    return [filtered copy];
}

- (NSString *)syncStatusForTunnelError:(NSError *)error {
    NSString *description = error.localizedDescription ?: @"";
    NSString *lowerDescription = description.lowercaseString;

    if ([lowerDescription containsString:@"can't connect to self"]) {
        return @"This Device";
    }
    if ([lowerDescription containsString:@"stranger"]) {
        return @"Stranger";
    }
    if ([lowerDescription containsString:@"not connected"] ||
        [lowerDescription containsString:@"session terminated"] ||
        [lowerDescription containsString:@"connection"]) {
        return @"Disconnected";
    }

    return @"Unavailable";
}

- (NSTimeInterval)tunnelRetryDelayForStatus:(NSString *)status {
    if ([status isEqualToString:@"Stranger"]) {
        return 60.0;
    }
    if ([status isEqualToString:@"This Device"]) {
        return 300.0;
    }
    if ([status isEqualToString:@"Disconnected"]) {
        return 5.0;
    }
    return 15.0;
}

- (nullable NSDate *)nextTunnelRetryDateForPeer:(NSString *)peerID {
    if (peerID.length == 0) {
        return nil;
    }

    __block NSDate *retryDate = nil;
    dispatch_sync(self.clientQueue, ^{
        retryDate = self.peerNextTunnelRetryAt[peerID];
    });
    return retryDate;
}

- (void)setNextTunnelRetryDate:(nullable NSDate *)retryDate forPeer:(NSString *)peerID {
    if (peerID.length == 0) {
        return;
    }

    dispatch_async(self.clientQueue, ^{
        if (retryDate) {
            self.peerNextTunnelRetryAt[peerID] = retryDate;
        } else {
            [self.peerNextTunnelRetryAt removeObjectForKey:peerID];
        }
    });
}

- (BOOL)isAttendantsEventDictionary:(NSDictionary *)dict {
    return (dict[@"type"] != nil ||
            dict[@"event"] != nil ||
            dict[@"ids"] != nil ||
            dict[@"peers"] != nil ||
            dict[@"attendants"] != nil ||
            dict[@"id"] != nil ||
            dict[@"key"] != nil ||
            dict[@"feed"] != nil);
}

- (nullable id)jsonObjectFromDataIfPossible:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data
                                           options:NSJSONReadingAllowFragments
                                             error:nil];
}

- (id)normalizedAttendantsPayloadFromResponse:(id)response {
    id current = response;
    for (NSUInteger depth = 0; depth < 4 && current; depth++) {
        if ([current isKindOfClass:[NSData class]]) {
            NSData *data = (NSData *)current;
            id parsed = [self jsonObjectFromDataIfPossible:data];
            if (parsed) {
                current = parsed;
                continue;
            }
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (text.length > 0) {
                current = text;
                continue;
            }
            break;
        }

        if ([current isKindOfClass:[NSString class]]) {
            NSString *trimmed = [(NSString *)current stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (([trimmed hasPrefix:@"{"] && [trimmed hasSuffix:@"}"]) ||
                ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"])) {
                NSData *jsonData = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
                id parsed = [self jsonObjectFromDataIfPossible:jsonData];
                if (parsed) {
                    current = parsed;
                    continue;
                }
            }
            break;
        }

        if ([current isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)current;
            if ([self isAttendantsEventDictionary:dict]) {
                if (!dict[@"type"] && [dict[@"event"] isKindOfClass:[NSString class]]) {
                    NSMutableDictionary *mutable = [dict mutableCopy];
                    mutable[@"type"] = dict[@"event"];
                    return [mutable copy];
                }
                return dict;
            }

            id wrapped = dict[@"value"] ?: dict[@"payload"] ?: dict[@"data"] ?: dict[@"result"];
            if (wrapped && wrapped != [NSNull null]) {
                current = wrapped;
                continue;
            }
        }

        break;
    }

    return current;
}

- (BOOL)applyAttendantsEventDictionary:(NSDictionary *)dict {
    NSString *type = [dict[@"type"] isKindOfClass:[NSString class]] ? dict[@"type"] : nil;
    if (type.length == 0 && [dict[@"event"] isKindOfClass:[NSString class]]) {
        type = dict[@"event"];
    }
    NSString *normalizedType = [type.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([normalizedType isEqualToString:@"state"] ||
        (normalizedType.length == 0 && (dict[@"ids"] || dict[@"peers"] || dict[@"attendants"]))) {
        id items = dict[@"ids"] ?: dict[@"peers"] ?: dict[@"attendants"];
        NSArray *normalizedItems = nil;
        if ([items isKindOfClass:[NSArray class]]) {
            normalizedItems = (NSArray *)items;
        } else if ([items isKindOfClass:[NSDictionary class]]) {
            NSDictionary *itemsDict = (NSDictionary *)items;
            NSMutableArray *flattened = [NSMutableArray arrayWithArray:itemsDict.allKeys];
            [flattened addObjectsFromArray:itemsDict.allValues];
            normalizedItems = [flattened copy];
        } else if (items && items != [NSNull null]) {
            normalizedItems = @[items];
        }

        BOOL explicitEmpty = ([items isKindOfClass:[NSArray class]] && [(NSArray *)items count] == 0) ||
                             ([items isKindOfClass:[NSDictionary class]] && [(NSDictionary *)items count] == 0);
        if (normalizedItems || explicitEmpty) {
            NSArray<NSString *> *peerIDs = [self filteredAttendantPeerIDs:[self normalizedPeerIDsFromCollection:normalizedItems ?: @[]]];
            [self.attendantsList removeAllObjects];
            [self.attendantsList addObjectsFromArray:peerIDs];
            for (NSString *peerID in peerIDs) {
                [self replicateFromPeer:peerID viaRoom:self.host];
            }
            return YES;
        }
        return NO;
    }

    if ([normalizedType isEqualToString:@"joined"] ||
        [normalizedType isEqualToString:@"join"] ||
        [normalizedType isEqualToString:@"added"]) {
        NSString *peerID = [self peerIDFromEndpointItem:dict];
        NSString *localPeerID = [self localPublicID];
        if (peerID.length > 0 &&
            ![peerID isEqualToString:localPeerID] &&
            ![self.attendantsList containsObject:peerID]) {
            [self.attendantsList addObject:peerID];
        }
        if (peerID.length > 0 && ![peerID isEqualToString:localPeerID]) {
            [self replicateFromPeer:peerID viaRoom:self.host];
            return YES;
        }
        return NO;
    }

    if ([normalizedType isEqualToString:@"left"] ||
        [normalizedType isEqualToString:@"leave"] ||
        [normalizedType isEqualToString:@"removed"]) {
        NSString *peerID = [self peerIDFromEndpointItem:dict];
        if (peerID.length > 0) {
            [self.attendantsList removeObject:peerID];
            return YES;
        }
        return NO;
    }

    return NO;
}

- (BOOL)manifestDictionary:(NSDictionary *)manifest supportsRPCPath:(NSArray<NSString *> *)path {
    id cursor = manifest;
    for (NSString *component in path) {
        if (![cursor isKindOfClass:[NSDictionary class]]) {
            cursor = nil;
            break;
        }
        cursor = ((NSDictionary *)cursor)[component];
        if (!cursor || cursor == [NSNull null]) {
            cursor = nil;
            break;
        }
    }
    if (cursor != nil) {
        return YES;
    }

    NSString *dottedPath = [path componentsJoinedByString:@"."];
    id dottedValue = manifest[dottedPath];
    return (dottedValue && dottedValue != [NSNull null]);
}

- (BOOL)manifestSupportsRPCPath:(NSArray<NSString *> *)path {
    if (![self.serverManifest isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *manifest = (NSDictionary *)self.serverManifest;
    if ([self manifestDictionary:manifest supportsRPCPath:path]) {
        return YES;
    }

    NSDictionary *wrappedManifest = [manifest[@"manifest"] isKindOfClass:[NSDictionary class]] ? manifest[@"manifest"] : nil;
    if (wrappedManifest && [self manifestDictionary:wrappedManifest supportsRPCPath:path]) {
        return YES;
    }
    return NO;
}

- (NSArray<NSString *> *)preferredEndpointDiscoveryMethod {
    if ([self.roomFeatures containsObject:@"room2"]) {
        return @[@"room", @"attendants"];
    }
    if ([self manifestSupportsRPCPath:@[@"room", @"attendants"]]) {
        return @[@"room", @"attendants"];
    }
    return @[@"tunnel", @"endpoints"];
}

- (BOOL)shouldResubscribeForPreferredEndpointDiscoveryMethod {
    NSArray<NSString *> *preferredMethod = [self preferredEndpointDiscoveryMethod];
    if (self.endpointDiscoveryMethodInUse.count == 0) {
        return NO;
    }
    if ([self.endpointDiscoveryMethodInUse isEqualToArray:preferredMethod]) {
        return NO;
    }
    return [preferredMethod isEqualToArray:@[@"room", @"attendants"]];
}

- (BOOL)isRoomAttendantsMethod:(NSArray<NSString *> *)method {
    return [method isEqualToArray:@[@"room", @"attendants"]];
}

- (BOOL)isTunnelEndpointsMethod:(NSArray<NSString *> *)method {
    return [method isEqualToArray:@[@"tunnel", @"endpoints"]];
}

- (void)probeRoomAttendantsSnapshotWithReason:(NSString *)reason {
    if (!self.isConnected) {
        return;
    }

    [self log:[NSString stringWithFormat:@"Switching to room.attendants discovery (%@)", reason ?: @"no reason"]];
    [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"probe room.attendants (source) reason=%@",
                                         reason ?: @"<none>"]];
    [self subscribeToEndpointDiscoveryMethod:@[@"room", @"attendants"] reason:reason ?: @"room.attendants probe"];
}

- (void)armEndpointDiscoveryFallbackTimerForMethod:(NSArray<NSString *> *)method generation:(uint64_t)generation {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), self.clientQueue, ^{
        if (!self.isConnected) {
            return;
        }
        if (self.endpointDiscoverySubscriptionGeneration != generation) {
            return;
        }
        if (![self.endpointDiscoveryMethodInUse isEqualToArray:method]) {
            return;
        }
        if (self.endpointDiscoveryReceivedEvent) {
            return;
        }

        if ([self isRoomAttendantsMethod:method]) {
            [self log:@"No room.attendants events received; falling back to legacy tunnel.endpoints"];
            [self appendPeerDiscoveryDiagnostic:@"fallback: room.attendants timed out without events; switching to tunnel.endpoints"];
            self.endpointDiscoveryMethodInUse = nil;
            [self subscribeToEndpointDiscoveryMethod:@[@"tunnel", @"endpoints"] reason:@"room.attendants timeout"];
            return;
        }

        if ([self isTunnelEndpointsMethod:method]) {
            [self log:@"No tunnel.endpoints events received; probing room.attendants snapshot"];
            [self appendPeerDiscoveryDiagnostic:@"fallback: tunnel.endpoints timed out without events; probing room.attendants snapshot"];
            [self probeRoomAttendantsSnapshotWithReason:@"tunnel.endpoints timeout"];
            return;
        }
    });
}

- (void)subscribeToEndpointDiscoveryMethod:(NSArray<NSString *> *)method reason:(nullable NSString *)reason {
    if (!self.isConnected) {
        [self log:@"Cannot subscribe: Not connected"];
        return;
    }

    if ([self.endpointDiscoveryMethodInUse isEqualToArray:method]) {
        [self log:@"Endpoint discovery subscription already active"];
        [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"subscription skipped (already active): %@.%@",
                                             method.firstObject ?: @"?",
                                             method.count > 1 ? method[1] : @"?"]];
        return;
    }

    if (reason.length > 0) {
        [self log:[NSString stringWithFormat:@"Switching endpoint discovery to %@.%@ (%@)",
                   method.firstObject ?: @"?",
                   method.count > 1 ? method[1] : @"?",
                   reason]];
        [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"subscription switch -> %@.%@ reason=%@",
                                             method.firstObject ?: @"?",
                                             method.count > 1 ? method[1] : @"?",
                                             reason]];
    } else {
        [self log:[NSString stringWithFormat:@"Subscribing to attendants/endpoints for %@", self.host]];
        [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"subscription start -> %@.%@",
                                             method.firstObject ?: @"?",
                                             method.count > 1 ? method[1] : @"?"]];
    }

    uint64_t generation = self.endpointDiscoverySubscriptionGeneration + 1;
    self.endpointDiscoverySubscriptionGeneration = generation;
    self.endpointDiscoveryReceivedEvent = NO;

    __weak typeof(self) weakSelf = self;
    SSBRPCCallback handler = ^(id _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (strongSelf.endpointDiscoverySubscriptionGeneration != generation) {
            os_log_debug(ssb_room_log, "Ignoring stale endpoint discovery event for %{public}@", strongSelf.host);
            [strongSelf appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"ignored stale endpoint event generation=%llu current=%llu",
                                                       generation,
                                                       strongSelf.endpointDiscoverySubscriptionGeneration]];
            return;
        }

        if (!error) {
            strongSelf.endpointDiscoveryReceivedEvent = YES;
            os_log_debug(ssb_room_log, "Got stream event for %{public}@", strongSelf.host);
            [strongSelf appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"stream event received for %@.%@ (class=%@)",
                                                       method.firstObject ?: @"?",
                                                       method.count > 1 ? method[1] : @"?",
                                                       NSStringFromClass([response class])]];
            [strongSelf handleAttendantsResponse:response];
            return;
        }

        if ([strongSelf.endpointDiscoveryMethodInUse isEqualToArray:method]) {
            strongSelf.endpointDiscoveryMethodInUse = nil;
        }
        [strongSelf log:[NSString stringWithFormat:@"Stream error for %@: %@", strongSelf.host, error.localizedDescription]];
        [strongSelf appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"stream error on %@.%@: %@",
                                                   method.firstObject ?: @"?",
                                                   method.count > 1 ? method[1] : @"?",
                                                   error.localizedDescription ?: @"<unknown>"]];

        if ([strongSelf isRoomAttendantsMethod:method]) {
            [strongSelf subscribeToEndpointDiscoveryMethod:@[@"tunnel", @"endpoints"] reason:@"room.attendants stream error"];
        }
    };

    if ([self isRoomAttendantsMethod:method]) {
        if ([self.roomFeatures containsObject:@"room2"]) {
            [self log:@"Using Room v2 attendants discovery"];
        } else {
            [self log:@"Using manifest-discovered attendants discovery"];
        }
    } else {
        [self log:@"Using legacy tunnel.endpoints discovery"];
    }

    self.endpointDiscoveryMethodInUse = [method copy];
    [self sendRPCRequest:method args:@[] type:@"source" completion:handler];
    [self armEndpointDiscoveryFallbackTimerForMethod:method generation:generation];
}

- (void)refreshEndpointDiscoverySubscriptionIfNeeded {
    if (![self shouldResubscribeForPreferredEndpointDiscoveryMethod]) {
        return;
    }
    [self log:@"Upgrading endpoint discovery subscription"];
    self.endpointDiscoveryMethodInUse = nil;
    [self subscribeToEndpoints];
}

- (NSDictionary<NSString *, NSNumber *> *)currentRemoteClock {
    __block NSDictionary *snapshot;
    dispatch_sync(self.clientQueue, ^{
        snapshot = [self.remoteClock copy];
    });
    return snapshot;
}

- (NSInteger)pendingMessagesCount {
    __block NSInteger count;
    dispatch_sync(self.clientQueue, ^{
        count = self.pendingPublishQueue.count;
    });
    return count;
}

- (instancetype)initWithConfig:(RoomConfig *)config 
                 localIdentity:(nullable NSData *)localIdentitySecret {
    self = [self initWithHost:config.host port:(uint16_t)config.port serverPubKey:config.serverPubKey localIdentity:localIdentitySecret];
    if (self) {
        _inviteToken = config.inviteToken;
        _usedHTTPInvite = config.usedHTTPInvite;
    }
    return self;
}

- (void)connect {
    if (self.isConnected) return;
    
    os_log_info(ssb_room_log, "Connecting to %{public}@:%d", self.host, self.port);
    [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"connect requested port=%u", self.port]];
    self.endpointDiscoveryMethodInUse = nil;
    
    SSBTransportEndpoint *endpoint = [SSBTransportEndpoint endpointWithHost:self.host port:self.port];
    SSBTransportConnectionOptions *options = [[SSBTransportConnectionOptions alloc] init];
    options.enableTCPNoDelay = YES;
    options.enableSecurityFramer = YES;
    options.enableMuxRPCFramer = YES;
    options.actingAsClient = YES;
    options.localIdentitySecret = self.localIdentitySecret;
    options.remotePublicKey = self.serverPubKey;
    self.connection = [self.transportBackend connectionToEndpoint:endpoint options:options queue:self.clientQueue];
    
    __weak typeof(self) weakSelf = self;
    [self.connection setStateChangedHandler:^(id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (state == SSBTransportConnectionStateReady) {
            os_log_info(ssb_room_log, "Connection state: READY");
            [strongSelf appendPeerDiscoveryDiagnostic:@"connection state READY"];
            [strongSelf log:@"Connected and secured."];
            strongSelf.isConnected = YES;
            if ([strongSelf.delegate respondsToSelector:@selector(roomClientDidConnect:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf.delegate roomClientDidConnect:strongSelf];
                });
            }
            [strongSelf startReceivingMessages];
            [strongSelf performInitialSetup];
        } else if (state == SSBTransportConnectionStateFailed || state == SSBTransportConnectionStateCancelled) {
            os_log_info(ssb_room_log, "Connection state changed: %lu", (unsigned long)state);
            [strongSelf appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"connection state changed=%lu", (unsigned long)state]];
            strongSelf.isConnected = NO;
            strongSelf.endpointDiscoveryMethodInUse = nil;
            if (strongSelf.autoReconnect && state == SSBTransportConnectionStateFailed) {
                [strongSelf scheduleReconnect];
            }
        } else {
            os_log_info(ssb_room_log, "Connection state changed: %lu", (unsigned long)state);
            [strongSelf appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"connection state changed=%lu", (unsigned long)state]];
        }
    }];
    
    [self.connection start];
}

- (void)startReceivingMessages {
    __weak typeof(self) weakSelf = self;
    [self.connection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, BOOL is_complete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            os_log_error(ssb_room_log, "Client %{public}@: receive error: %{public}@", strongSelf.host, error);
            return;
        }

        if (content) {
            if (metadata) {
                NSNumber *flagsObj = metadata[SSBTransportMetadataFlagsKey];
                NSNumber *reqNumObj = metadata[SSBTransportMetadataRequestNumberKey];

                if (flagsObj && reqNumObj) {
                    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:[flagsObj unsignedIntValue]
                                                                      requestNumber:[reqNumObj intValue]
                                                                               body:content];
                    [strongSelf.rpcSession handleIncomingMessage:msg];
                } else {
                    os_log_debug(ssb_room_log, "Client %{public}@: Metadata present but missing values", strongSelf.host);
                }
            } else {
                os_log_debug(ssb_room_log, "Client %{public}@: No MuxRPC metadata found", strongSelf.host);
            }
        } else {
            os_log_debug(ssb_room_log, "Client %{public}@: nil content received, is_complete=%d", strongSelf.host, is_complete);
        }

        if (strongSelf.isConnected) {
            [strongSelf startReceivingMessages];
        }
    }];
}

- (void)sendRPCMessage:(SSBMuxRPCMessage *)msg {
    if (!self.isConnected) {
        os_log_debug(ssb_room_log, "sendRPCMessage DROPPING msg: isConnected=NO");
        return;
    }
    
    NSData *serialized = [msg serialize];
    [self.connection sendData:serialized isComplete:YES completion:^(NSError * _Nullable error) {
        if (error) os_log_error(ssb_room_log, "RPC send failed");
    }];
}

- (void)performInitialSetup {
    os_log_debug(ssb_room_log, "Client: performInitialSetup starting");
    __weak typeof(self) weakSelf = self;
    
    [self sendRPCRequest:@[@"manifest"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        if ([response isKindOfClass:[NSDictionary class]]) {
            weakSelf.serverManifest = response;
            [weakSelf refreshEndpointDiscoverySubscriptionIfNeeded];
        }
    }];
    
    [self sendRPCRequest:@[@"whoami"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        [weakSelf log:[NSString stringWithFormat:@"Identity: %@", response]];
    }];
    
    __block _Atomic BOOL metadataFinished = NO;
    [self sendRPCRequest:@[@"room", @"metadata"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (metadataFinished) return;
        metadataFinished = YES;
        if ([response isKindOfClass:[NSDictionary class]]) {
            weakSelf.roomFeatures = response[@"features"];
            weakSelf.isInternalUser = [response[@"membership"] boolValue];
            [weakSelf log:[NSString stringWithFormat:@"Room features: %@, internal: %d", weakSelf.roomFeatures, weakSelf.isInternalUser]];
            [weakSelf announceWithCompletion:^{
                [weakSelf subscribeToEndpoints];
                [weakSelf syncLocalFeed];
            }];
        } else {
            [weakSelf log:@"No room metadata found, trying legacy flow"];
            [weakSelf announceWithCompletion:^{
                [weakSelf subscribeToEndpoints];
                [weakSelf syncLocalFeed];
            }];
        }
    }];
    
    // Timeout fallback after 5 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!metadataFinished) {
            [weakSelf log:@"room.metadata TIMEOUT, falling back to legacy flow"];
            metadataFinished = YES;
            [weakSelf announceWithCompletion:^{
                [weakSelf subscribeToEndpoints];
                [weakSelf syncLocalFeed];
            }];
        }
    });
    
    if ([self shouldRedeemInviteAfterSetup]) {
        [self redeemInvite:self.inviteToken completion:nil];
    }
}

- (BOOL)shouldRedeemInviteAfterSetup {
    if (self.inviteToken.length == 0) {
        return NO;
    }
    if (self.usedHTTPInvite) {
        return NO;
    }
    if (self.serverManifest && ![self manifestSupportsRPCPath:@[@"room", @"claimInvite"]]) {
        return NO;
    }
    return YES;
}

- (void)redeemInvite:(NSString *)token completion:(nullable SSBRPCCallback)completion {
    [self sendRPCRequest:@[@"room", @"claimInvite"] args:@[token] type:@"async" completion:completion];
}

- (void)registerAlias:(NSString *)alias completion:(nullable SSBRPCCallback)completion {
    NSString *roomId = [self serverPublicID];
    NSString *userId = [self localPublicID];
    NSString *registrationStr = [NSString stringWithFormat:@"=room-alias-registration:%@:%@:%@", roomId, userId, alias];
    
    NSString *sig = [SSBMessageCodec signString:registrationStr withSecretKey:self.localIdentitySecret];
    if (!sig) {
        if (completion) completion(nil, [NSError errorWithDomain:@"SSBError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign alias registration"}]);
        return;
    }
    
    [self registerAlias:alias signature:sig completion:completion];
}

- (void)registerAlias:(NSString *)alias signature:(NSString *)signature completion:(nullable SSBRPCCallback)completion {
    [self sendRPCRequest:@[@"room", @"registerAlias"] args:@[alias, signature] type:@"async" completion:completion];
}

- (void)revokeAlias:(NSString *)alias completion:(nullable SSBRPCCallback)completion {
    [self sendRPCRequest:@[@"room", @"revokeAlias"] args:@[alias] type:@"async" completion:completion];
}

- (void)syncLocalFeed {
    NSString *myId = [self localPublicID];
    SSBFeedState *state = [self.feedStore feedStateForAuthor:myId];
    NSInteger localSeq = state ? state.maxSequence : 0;
    
    // Start syncing
    SSBLogInfo(SSBLogCategorySync, @"🔄 syncLocalFeed STARTING: localSeq=%ld", (long)localSeq);
    self.isSyncingLocalFeed = YES;
    self.localFeedSeq = localSeq;
    
    if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate roomClient:self didUpdateSyncStatus:@"Syncing your feed..." progress:0.0 author:[self localPublicID]];
        });
    }

    if (![self shouldAttemptRoomHistorySync]) {
        SSBLogInfo(SSBLogCategorySync, @"Skipping room feed sync: createHistoryStream unsupported by room");
        self.isSyncingLocalFeed = NO;
        [self processPublishQueue];
        if ([self.delegate respondsToSelector:@selector(roomClientDidSyncLocalFeed:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate roomClientDidSyncLocalFeed:self];
            });
        }
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:[self localPublicID]];
            });
        }
        return;
    }
    
    NSDictionary *args = @{@"id": myId, @"limit": @100, @"reverse": @NO, @"live": @NO};
    
    __block NSInteger replicatedCount = 0;
    int32_t reqID = [self sendRPCRequest:@[@"createHistoryStream"] args:@[args] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            SSBLogError(SSBLogCategorySync, @"❌ syncLocalFeed ERROR: %@", error.localizedDescription);
            self.isSyncingLocalFeed = NO;
            SSBLogInfo(SSBLogCategorySync, @"🔄 syncLocalFeed COMPLETE (error): isSyncingLocalFeed=NO");
            [self processPublishQueue];
            if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:[self localPublicID]];
                });
            }
            return;
        }
        
        if ([response isKindOfClass:[NSDictionary class]]) {
            NSDictionary *val = response[@"value"];
            if ([SSBMessageCodec verifyMessage:val]) {
                SSBMessage *msg = [[SSBMessage alloc] init];
                msg.key = response[@"key"];
                msg.author = val[@"author"];
                msg.sequence = [val[@"sequence"] integerValue];
                msg.previousKey = val[@"previous"];
                msg.claimedTimestamp = [val[@"timestamp"] longLongValue];
                msg.content = val[@"content"];
                msg.contentType = msg.content[@"type"];
                msg.valueJSON = [SSBMessageCodec encodeLegacyValue:val includeSignature:YES];
                if ([self.feedStore appendMessage:msg error:nil]) {
                    replicatedCount++;
                }
            }
        }
        
        // Sync complete (no more messages)
        if (!response) {
            self.isSyncingLocalFeed = NO;
            SSBLogInfo(SSBLogCategorySync, @"✅ syncLocalFeed COMPLETE: %ld messages replicated", (long)replicatedCount);
            SSBLogInfo(SSBLogCategorySync, @"🔄 Feed sync state change: isSyncingLocalFeed=NO, isFeedSynced=%d", self.isFeedSynced);
            
            // Process any queued messages
            [self processPublishQueue];
            
            if ([self.delegate respondsToSelector:@selector(roomClientDidSyncLocalFeed:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate roomClientDidSyncLocalFeed:self];
                });
            }
        }
    }];
    
    // sendRPCRequest returns -1 if not connected — completion never fires
    if (reqID < 0) {
        SSBLogError(SSBLogCategorySync, @"❌ syncLocalFeed FAILED: not connected");
        self.isSyncingLocalFeed = NO;
        SSBLogInfo(SSBLogCategorySync, @"🔄 Feed sync state change: isSyncingLocalFeed=NO (connection failed)");
        [self processPublishQueue];
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:[self localPublicID]];
            });
        }
    }
}

- (BOOL)shouldAttemptRoomHistorySync {
    if (!self.serverManifest) {
        return NO;
    }
    return [self manifestSupportsRPCPath:@[@"createHistoryStream"]];
}

- (void)fetchFeedForPeer:(NSString *)peerID limit:(NSInteger)limit completion:(nullable SSBRPCCallback)completion {
    SSBLogInfo(SSBLogCategoryProfile, @"📥 fetchFeedForPeer: limit=%ld peer=%@", (long)limit, [peerID substringToIndex:MIN(8, peerID.length)]);
    
    NSString *roomId = [NSString stringWithFormat:@"@%@.ed25519", [self.serverPubKey base64EncodedStringWithOptions:0]];
    BOOL isRoom = [peerID isEqualToString:roomId] || [peerID isEqualToString:self.host];
    BOOL isSelf = [peerID isEqualToString:self.localPublicID];
    
    SSBMuxRPCSession *session = self.rpcSession;
    BOOL connected = self.isConnected;
    
    if (!isRoom && !isSelf) {
        SSBTunnelConnection *tunnel = self.activeTunnels[peerID];
        if (!tunnel) {
            [self connectToPeer:peerID];
            tunnel = self.activeTunnels[peerID];
        }
        
        if (tunnel) {
            session = tunnel.rpcSession;
            // The connection might not be ready yet, but nw_connection will buffer the send
            connected = YES;
        } else {
            connected = NO;
        }
    }
    
    if (!connected) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"SSBRoomClient" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]);
        }
        return;
    }
    
    NSDictionary *args = @{@"id": peerID, @"limit": @(limit), @"reverse": @YES, @"live": @NO};
    [session sendRequest:@[@"createHistoryStream"] args:@[args] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            SSBLogError(SSBLogCategoryProfile, @"❌ fetchFeedForPeer failed: %@", error.localizedDescription);
        } else {
            SSBLogInfo(SSBLogCategoryProfile, @"✅ fetchFeedForPeer succeeded for %@", [peerID substringToIndex:MIN(8, peerID.length)]);
        }
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void)publishContact:(NSString *)targetPubKey following:(BOOL)following completion:(nullable SSBRPCCallback)completion {
    SSBLogInfo(SSBLogCategoryProfile, @"👤 publishContact: %@ -> %@", following ? @"Follow" : @"Unfollow", [targetPubKey substringToIndex:MIN(8, targetPubKey.length)]);
    SSBLogInfo(SSBLogCategorySync, @"📊 Feed sync state: isSyncingLocalFeed=%d isFeedSynced=%d", self.isSyncingLocalFeed, self.isFeedSynced);
    
    NSError *error = nil;
    SSBMessage *msg = [self publishLocalContact:targetPubKey following:following error:&error];
    
    if (msg) {
        SSBLogInfo(SSBLogCategoryProfile, @"✅ publishContact succeeded: seq=%ld", (long)msg.sequence);
    } else if (error) {
        SSBLogError(SSBLogCategoryProfile, @"❌ publishContact failed: %@", error.localizedDescription);
    } else {
        SSBLogInfo(SSBLogCategoryProfile, @"⏳ publishContact queued (feed not synced), queue count: %lu", (unsigned long)self.pendingPublishQueue.count);
    }
    
    if (completion) {
        completion(msg, error);
    }
}

- (void)publishBlock:(NSString *)targetPubKey blocking:(BOOL)blocking completion:(nullable SSBRPCCallback)completion {
    SSBLogInfo(SSBLogCategoryProfile, @"🚫 publishBlock: %@ -> %@", blocking ? @"Block" : @"Unblock", [targetPubKey substringToIndex:MIN(8, targetPubKey.length)]);
    
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:targetPubKey following:NO];
    NSMutableDictionary *mutContent = [content mutableCopy];
    mutContent[@"blocking"] = @(blocking);
    
    // Optimistically update the feed store so UI reacts immediately
    [self.feedStore setBlocked:blocking forAuthor:targetPubKey atSequence:0];
    SSBLogInfo(SSBLogCategoryProfile, @"🔄 Optimistic update: blocked=%d for %@", blocking, [targetPubKey substringToIndex:MIN(8, targetPubKey.length)]);
    
    NSError *error = nil;
    SSBMessage *msg = [self publishLocalMessageWithContent:mutContent error:&error];
    if (msg) {
        [self.feedStore setBlocked:blocking forAuthor:targetPubKey atSequence:msg.sequence];
        SSBLogInfo(SSBLogCategoryProfile, @"✅ publishBlock succeeded: seq=%ld", (long)msg.sequence);
    } else if (error) {
        SSBLogError(SSBLogCategoryProfile, @"❌ publishBlock failed: %@", error.localizedDescription);
    } else {
        SSBLogInfo(SSBLogCategoryProfile, @"⏳ publishBlock queued (feed not synced)");
    }
    
    if (completion) {
        completion(msg, error);
    }
}

- (void)fetchProfileForPeer:(NSString *)peerID completion:(nullable SSBRPCCallback)completion {
    SSBLogInfo(SSBLogCategoryProfile, @"👤 fetchProfileForPeer: %@", [peerID substringToIndex:MIN(8, peerID.length)]);
    
    NSString *roomId = [NSString stringWithFormat:@"@%@.ed25519", [self.serverPubKey base64EncodedStringWithOptions:0]];
    BOOL isRoom = [peerID isEqualToString:roomId] || [peerID isEqualToString:self.host];
    BOOL isSelf = [peerID isEqualToString:self.localPublicID];
    
    SSBMuxRPCSession *session = self.rpcSession;
    BOOL connected = self.isConnected;
    
    if (!isRoom && !isSelf) {
        SSBTunnelConnection *tunnel = self.activeTunnels[peerID];
        if (!tunnel) {
            [self connectToPeer:peerID];
            tunnel = self.activeTunnels[peerID];
        }
        
        if (tunnel) {
            session = tunnel.rpcSession;
            // The connection might not be ready yet, but nw_connection will buffer the send
            connected = YES;
        } else {
            connected = NO;
        }
    }
    
    if (!connected) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"SSBRoomClient" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]);
        }
        return;
    }
    
    [session sendRequest:@[@"about"] args:@[@{@"id": peerID}] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            SSBLogError(SSBLogCategoryProfile, @"❌ fetchProfileForPeer failed: %@", error.localizedDescription);
        } else if (response) {
            SSBLogInfo(SSBLogCategoryProfile, @"✅ fetchProfileForPeer succeeded: %@", response);
        }
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void)fetchBlob:(NSString *)blobID completion:(void (^)(NSString * _Nullable localPath, NSError * _Nullable error))completion {
    [[SSBBlobStore sharedStore] fetchBlob:blobID session:self.rpcSession completion:completion];
}

- (void)hasBlob:(NSString *)blobID completion:(void (^)(BOOL hasIt))completion {
    // Check local store first
    if ([[SSBBlobStore sharedStore] hasBlob:blobID]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES);
        });
        return;
    }
    [self sendRPCRequest:@[@"blobs", @"has"] args:@[blobID] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(!error && [response isEqual:@YES]);
        });
    }];
}

- (void)fetchRoomMetadataWithCompletion:(nullable SSBRPCCallback)completion {
    [self sendRPCRequest:@[@"room", @"metadata"] args:@[] type:@"async" completion:completion];
}

- (nullable SSBMessage *)publishPostWithText:(NSString *)text error:(NSError **)error {
    NSDictionary *content = [SSBMessageCodec postContentWithText:text];
    return [self publishLocalMessageWithContent:content error:error];
}

- (nullable SSBMessage *)publishLocalContact:(NSString *)targetPubKey following:(BOOL)following error:(NSError **)error {
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:targetPubKey following:following];
    
    // Optimistically update the feed store so UI reacts immediately
    [self.feedStore setFollowing:following forAuthor:targetPubKey atSequence:0]; // Sequence doesn't matter for contact graph
    
    SSBMessage *msg = [self publishLocalMessageWithContent:content error:error];
    if (msg) {
        [self.feedStore setFollowing:following forAuthor:targetPubKey atSequence:msg.sequence];
    }
    return msg;
}

- (nullable SSBMessage *)publishAboutWithName:(nullable NSString *)name description:(nullable NSString *)desc error:(NSError **)error {
    NSDictionary *content = [SSBMessageCodec aboutContentForFeed:[self localPublicID] name:name description:desc];
    return [self publishLocalMessageWithContent:content error:error];
}

- (void)publishLocalMessageWithContent:(NSDictionary<NSString *,id> *)content completion:(void (^)(NSError * _Nullable, SSBMessage * _Nullable))completion {
    NSError *error = nil;
    SSBMessage *msg = [self publishLocalMessageWithContent:content error:&error];
    if (completion) {
        completion(error, msg);
    }
}

- (nullable SSBMessage *)publishLocalMessageWithContent:(NSDictionary *)content error:(NSError **)error {
    // Fork prevention: Queue message if our feed hasn't fully synced
    // This prevents creating forked feeds which can corrupt your identity
    if (!self.isFeedSynced) {
        // Add to queue instead of blocking
        NSDictionary *queuedItem = @{
            @"content": content,
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        };
        [self.pendingPublishQueue addObject:queuedItem];
        SSBLogWarning(SSBLogCategorySync, @"⏳ Message QUEUED (feed not synced): type=%@ queue size=%lu", content[@"type"] ?: @"unknown", (unsigned long)self.pendingPublishQueue.count);
        
        // Notify delegate
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate roomClient:self didUpdateSyncStatus:[NSString stringWithFormat:@"Queued (%lu)", (unsigned long)self.pendingPublishQueue.count] progress:0 author:nil];
            });
        }
        return nil;
    }
    
    // Feed is synced, publish immediately
    return [self publishMessageNow:content error:error];
}

- (nullable SSBMessage *)publishMessageNow:(NSDictionary *)content error:(NSError **)error {
    NSString *myId = [self localPublicID];
    SSBFeedState *state = [self.feedStore feedStateForAuthor:myId];
    NSInteger nextSeq = state ? state.maxSequence + 1 : 1;
    NSString *prevKey = state ? state.maxKey : nil;
    
    NSDictionary *signedValue = [SSBMessageCodec createSignedMessageWithContent:content
                                                                          author:myId
                                                                        sequence:nextSeq
                                                                     previousKey:prevKey
                                                                       secretKey:self.localIdentitySecret];
    if (!signedValue) {
        if (error) *error = [NSError errorWithDomain:@"SSB" code:3 userInfo:nil];
        return nil;
    }
    
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = [SSBMessageCodec computeMessageKey:signedValue];
    msg.author = myId;
    msg.sequence = nextSeq;
    msg.previousKey = prevKey;
    msg.claimedTimestamp = [signedValue[@"timestamp"] longLongValue];
    msg.receivedAt = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    msg.contentType = content[@"type"];
    msg.content = content;
    msg.valueJSON = [SSBMessageCodec encodeLegacyValue:signedValue includeSignature:YES];
    
    if (![self.feedStore appendMessage:msg error:error]) return nil;
    return msg;
}

- (void)processPublishQueue {
    if (self.pendingPublishQueue.count == 0) {
        return;
    }
    
    if (!self.isFeedSynced) {
        SSBLogWarning(SSBLogCategorySync, @"⏳ Cannot process publish queue: feed not synced yet (isSyncingLocalFeed=%d)", self.isSyncingLocalFeed);
        return;
    }
    
    SSBLogInfo(SSBLogCategorySync, @"📤 Processing publish queue: %lu messages", (unsigned long)self.pendingPublishQueue.count);
    
    NSMutableArray *failedItems = [NSMutableArray array];
    NSInteger successCount = 0;
    
    for (NSDictionary *queuedItem in [self.pendingPublishQueue copy]) {
        NSDictionary *content = queuedItem[@"content"];
        SSBLogDebug(SSBLogCategorySync, @"   Publishing queued message: %@", content[@"type"]);
        NSError *error = nil;
        SSBMessage *msg = [self publishMessageNow:content error:&error];
        
        if (msg) {
            successCount++;
            SSBLogInfo(SSBLogCategorySync, @"   ✅ Published: seq=%ld type=%@", (long)msg.sequence, content[@"type"] ?: @"unknown");
        } else {
            SSBLogError(SSBLogCategorySync, @"   ❌ Failed to publish: %@", error.localizedDescription);
            [failedItems addObject:queuedItem];
        }
    }
    
    // Keep failed items in queue for retry
    [self.pendingPublishQueue removeAllObjects];
    [self.pendingPublishQueue addObjectsFromArray:failedItems];
    
    SSBLogInfo(SSBLogCategorySync, @"✅ Publish queue processed: %ld success, %lu remaining", (long)successCount, (unsigned long)self.pendingPublishQueue.count);
    
    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(roomClientDidProcessPublishQueue:success:queuedCount:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate roomClientDidProcessPublishQueue:self success:(failedItems.count == 0) queuedCount:self.pendingPublishQueue.count];
        });
    }
}

- (void)replicateFromPeer:(NSString *)peerID viaRoom:(NSString *)roomHost {
    os_log_debug(ssb_room_log, "replicateFromPeer: %{public}@ via room: %{public}@", peerID, roomHost);
    SSBLogInfo(SSBLogCategoryReplication, @"🔄 replicateFromPeer: %@ via room: %@", [peerID substringToIndex:MIN(8, peerID.length)], roomHost);

    NSDate *retryDate = [self nextTunnelRetryDateForPeer:peerID];
    if (retryDate && [retryDate timeIntervalSinceNow] > 0) {
        os_log_debug(ssb_room_log,
                     "Skipping tunnel retry for %{public}@ until %{public}@",
                     peerID,
                     retryDate.description);
        return;
    }
    
    SSBTunnelConnection *tunnel = self.activeTunnels[peerID];
    if (tunnel) {
        os_log_debug(ssb_room_log, "Found existing tunnel for %{public}@, isConnected=%d", peerID, tunnel.isConnected);
    }

    if (tunnel && tunnel.isConnected) {
        os_log_debug(ssb_room_log, "Tunnel connected, starting EBT on tunnel session");
        [self startEBTReplicationWithSession:tunnel.rpcSession];
    } else if (!tunnel) {
        os_log_debug(ssb_room_log, "No tunnel for %{public}@, initiating connectToPeer:", peerID);
        [self reportSyncStatus:@"Connecting..." progress:0.0 author:peerID];
        [self connectToPeer:peerID];
    } else {
        os_log_debug(ssb_room_log, "Tunnel exists but NOT connected yet for %{public}@", peerID);
        [self reportSyncStatus:@"Handshaking..." progress:0.1 author:peerID];
    }
}

#pragma mark - Replication (EBT)

- (void)startEBTReplicationWithSession:(SSBMuxRPCSession *)session {
    if (!session) return;
    if ([self.ebtRequestIDsBySession objectForKey:session] != nil) return;

    NSDictionary<NSString *, NSNumber *> *clock = [self.feedStore localClock];
    NSDictionary *args = @{@"version": @3};

    __weak typeof(self) weakSelf = self;
    __weak SSBMuxRPCSession *weakSession = session;
    SSBRPCCallback ebtCallback = ^(id _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong SSBMuxRPCSession *strongSession = weakSession;
        if (!strongSelf) return;
        if (error) {
            os_log_error(ssb_room_log, "EBT Replication stream error: %{public}@", error);
            if (strongSession) {
                [strongSelf.ebtRequestIDsBySession removeObjectForKey:strongSession];
            }
            return;
        }
        if (!strongSession) return;
        [strongSelf handleEBTMessage:response requestID:0 flags:0 session:strongSession];
    };

    int32_t requestID = [session sendRequest:@[@"ebt", @"replicate"] args:@[args] type:@"duplex" completion:ebtCallback];
    if (requestID <= 0) {
        os_log_error(ssb_room_log, "Failed to start EBT replication request for session %{public}@", session);
        return;
    }
    [self.ebtRequestIDsBySession setObject:@(requestID) forKey:session];

    session.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong SSBMuxRPCSession *strongSession = weakSession;
        if (!strongSelf || !strongSession) return;
        [strongSelf handleEBTMessage:payload requestID:requestID flags:flags session:strongSession];
    };

    // Send initial clock
    [session sendData:clock forRequest:requestID isEnd:NO];
    os_log_info(ssb_room_log, "Started EBT replication with clock of %lu feeds", (unsigned long)clock.count);
}

- (void)startEBTReplication {
    [self startEBTReplicationWithSession:self.rpcSession];
}

        - (void)handleEBTMessage:(id)message requestID:(int32_t)reqID flags:(uint8_t)flags session:(SSBMuxRPCSession *)session {
            if (reqID != 0) {
                os_log_debug(ssb_room_log, "handleEBTMessage: REMOTE REQUEST req=%d flags=%u", reqID, flags);
            } else {
                os_log_debug(ssb_room_log, "handleEBTMessage: RESPONSE");
            }

            // Identify which peer this message is from
            NSString *peerID = nil;
            for (NSString *pid in self.activeTunnels) {
                if (self.activeTunnels[pid].rpcSession == session) {
                    peerID = pid;
                    break;
                }
            }
            if (!peerID) peerID = self.host;

            if ([message isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)message;

                // Check if this is an RPC request rather than an EBT payload
                if (dict[@"name"] && dict[@"args"]) {
                    NSArray *name = dict[@"name"];
                    if ([name isKindOfClass:[NSArray class]] && name.count >= 2 && 
                        [name[0] isEqualToString:@"ebt"] && [name[1] isEqualToString:@"replicate"]) {
                        [self handleBilateralEBT:dict requestID:reqID session:session];
                    } else {
                        os_log_debug(ssb_room_log, "Ignoring non-EBT RPC request: %{public}@", name);
                    }
                    return;
                }

                if (dict[@"key"] && dict[@"value"]) {
                    [self processIncomingMessage:dict fromPeer:peerID];
                } else {
                    [self handleRemoteClockUpdate:dict fromPeer:peerID];
                }
            } else if ([message isKindOfClass:[NSData class]]) {
                NSData *data = (NSData *)message;
                os_log_debug(ssb_room_log, "Received binary EBT payload (%lu bytes)", (unsigned long)data.length);
                // Try to parse as JSON first in case it's a clock update in binary form
                NSError *jsonError = nil;
                id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&jsonError];
                if (!jsonError && [parsed isKindOfClass:[NSDictionary class]]) {
                     os_log_debug(ssb_room_log, "Successfully parsed binary EBT data as JSON dictionary");
                     [self handleEBTMessage:parsed requestID:reqID flags:flags session:session];
                } else {
                     [self processIncomingMessage:data fromPeer:peerID];
                }
            }
        }
        - (void)handleBilateralEBT:(NSDictionary *)req requestID:(int32_t)reqID session:(SSBMuxRPCSession *)session {
        os_log_info(ssb_room_log, "Handling bilateral EBT request (ID=%d)", reqID);

        // We need to know who this peer is. If this is a tunnel, we know the peerID.
        NSString *peerID = nil;
        for (NSString *pid in self.activeTunnels) {
        if (self.activeTunnels[pid].rpcSession == session) {
            peerID = pid;
            break;
        }
        }

        if (!peerID) {
        // If not a tunnel, it's the room itself (acting as a peer)
        peerID = self.host; 
        }

        // Store state for this bilateral session
        self.peerEBTState[peerID] = [@{
        @"requestID": @(reqID),
        @"clock": [NSMutableDictionary dictionary]
        } mutableCopy];

        // Send our clock as the response (duplex stream)
        NSDictionary<NSString *, NSNumber *> *clock = [self.feedStore localClock];
        [session sendData:clock forRequest:reqID isEnd:NO];
        os_log_info(ssb_room_log, "Sent bilateral EBT clock to %{public}@ (%lu feeds)", peerID, (unsigned long)clock.count);
        }

- (void)handleRemoteClockUpdate:(NSDictionary *)update fromPeer:(NSString *)peerID {
    os_log_debug(ssb_room_log, "Received clock update from %{public}@ with %lu entries", peerID, (unsigned long)update.count);
    
    NSMutableDictionary *targetClock;
    if (peerID && self.peerEBTState[peerID]) {
        targetClock = self.peerEBTState[peerID][@"clock"];
    } else {
        targetClock = self.remoteClock;
    }

    [update enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSNumber class]]) {
            NSString *author = (NSString *)key;
            NSInteger seq = [val integerValue];
            os_log_debug(ssb_room_log, "Valid clock for %{public}@ is %ld", author, (long)seq);
            targetClock[author] = @(ABS(seq));
            [self updateSyncProgressForAuthor:author fromPeer:peerID];
        }
    }];
}

- (void)handleRemoteClockUpdate:(NSDictionary *)update {
    [self handleRemoteClockUpdate:update fromPeer:nil];
}

- (void)processIncomingMessage:(id)response fromPeer:(NSString *)peerID {
    NSDictionary *dict = nil;
    if ([response isKindOfClass:[NSData class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:(NSData *)response options:0 error:nil];
    } else if ([response isKindOfClass:[NSDictionary class]]) {
        dict = (NSDictionary *)response;
    }
    
    if (!dict) return;
    
    NSDictionary *val = dict[@"value"] ?: dict;
    NSString *key = dict[@"key"]; // Might be nil if it's just the value
    
    if ([SSBMessageCodec verifyMessage:val]) {
        SSBMessage *msg = [[SSBMessage alloc] init];
        msg.key = key;
        msg.author = val[@"author"];
        msg.sequence = [val[@"sequence"] integerValue];
        msg.previousKey = val[@"previous"];
        msg.claimedTimestamp = [val[@"timestamp"] longLongValue];
        msg.content = val[@"content"];
        msg.contentType = msg.content[@"type"];
        msg.valueJSON = [SSBMessageCodec encodeLegacyValue:val includeSignature:YES];
        
        NSError *error = nil;
        if ([self.feedStore appendMessage:msg error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:SRNewMessageNotification object:nil];
                if ([self.delegate respondsToSelector:@selector(roomClient:didReplicateMessagesFromPeer:count:)]) {
                    [self.delegate roomClient:self didReplicateMessagesFromPeer:msg.author count:1];
                }
            });
            
            // Update the correct clock
            NSMutableDictionary *targetClock;
            if (peerID && self.peerEBTState[peerID]) {
                targetClock = self.peerEBTState[peerID][@"clock"];
            } else {
                targetClock = self.remoteClock;
            }
            if (msg.author) {
                targetClock[msg.author] = @(msg.sequence);
            }
            
            [self updateSyncProgressForAuthor:msg.author fromPeer:peerID];
        }
    }
}

- (void)processIncomingMessage:(id)response {
    [self processIncomingMessage:response fromPeer:nil];
}

- (nullable NSNumber *)remoteSequenceNumberForAuthor:(NSString *)author fromPeer:(nullable NSString *)peerID {
    if (author.length == 0) {
        return nil;
    }

    if (peerID.length > 0) {
        NSDictionary *peerState = self.peerEBTState[peerID];
        NSNumber *peerSequence = peerState[@"clock"][author];
        if (peerSequence != nil) {
            return peerSequence;
        }
    }

    NSNumber *sharedSequence = self.remoteClock[author];
    if (sharedSequence != nil) {
        return sharedSequence;
    }

    for (NSDictionary *peerState in self.peerEBTState.allValues) {
        NSNumber *peerSequence = peerState[@"clock"][author];
        if (peerSequence != nil) {
            return peerSequence;
        }
    }

    return nil;
}

- (void)reportTunnelReadyForPeer:(NSString *)peerID {
    if (peerID.length == 0) {
        return;
    }

    [self reportSyncStatus:@"Connected" progress:0.2f author:peerID];

    if ([self.delegate respondsToSelector:@selector(roomClient:didEstablishTunnelWithPeer:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate roomClient:self didEstablishTunnelWithPeer:peerID];
        });
    }
}

- (void)updateSyncProgressForAuthor:(NSString *)author fromPeer:(nullable NSString *)peerID {
    if (author.length == 0) {
        return;
    }

    SSBFeedState *state = [self.feedStore feedStateForAuthor:author];
    NSInteger localSeq = state ? state.maxSequence : 0;
    
    NSNumber *remoteSeqNum = [self remoteSequenceNumberForAuthor:author fromPeer:peerID];
    if (remoteSeqNum) {
        NSInteger remoteSeq = [remoteSeqNum integerValue];
        // Handle EBT passive notes (negative)
        if (remoteSeq < 0) remoteSeq = ABS(remoteSeq);
        
        float progress = 1.0;
        NSString *status = @"Ready";
        
        if (remoteSeq > localSeq) {
            // We are behind, receiving
            progress = (float)localSeq / (float)remoteSeq;
            status = [NSString stringWithFormat:@"Receiving: %ld/%ld", (long)localSeq, (long)remoteSeq];
        } else if (remoteSeq < localSeq) {
            // We are ahead, possibly sending? or just remote hasn't asked yet.
            // In EBT, we send until we reach localSeq.
            // We don't necessarily know if the remote is currently fetching, 
            // but we can show progress towards them being in sync.
            progress = (float)remoteSeq / (float)localSeq;
            status = [NSString stringWithFormat:@"Sending: %ld/%ld", (long)remoteSeq, (long)localSeq];
        } else {
            progress = 1.0;
            status = @"Ready";
        }
        
        [self reportSyncStatus:status progress:progress author:author];
    }
}

- (void)reportSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author {
    dispatch_async(self.clientQueue, ^{
        if (author.length > 0) {
            self.internalPeerSyncProgress[author] = @(progress);
            self.internalPeerSyncStates[author] = status;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                [self.delegate roomClient:self didUpdateSyncStatus:status progress:progress author:author];
            }
        });
    });
}

- (void)replicateFeed:(NSString *)feedAuthor fromPeer:(NSString *)peerID {
    SSBFeedState *state = [self.feedStore feedStateForAuthor:feedAuthor];
    NSDictionary *args = @{@"id": feedAuthor, @"seq": @(state ? state.maxSequence + 1 : 1), @"limit": @100, @"live": @NO};
    
    // Notify progress started
    dispatch_async(dispatch_get_main_queue(), ^{
    if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
        [self.delegate roomClient:self didUpdateSyncStatus:[NSString stringWithFormat:@"Syncing %@...", [feedAuthor substringToIndex:MIN(10, feedAuthor.length)]] progress:0.0 author:feedAuthor];
    }
    });

    SSBMuxRPCSession *session = self.rpcSession;
    BOOL connected = self.isConnected;
    SSBTunnelConnection *tunnel = self.activeTunnels[peerID];
    if (tunnel && tunnel.isConnected) {
        session = tunnel.rpcSession;
        connected = YES;
    }
    
    if (!connected || !session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:feedAuthor];
            }
        });
        return;
    }

    __block NSInteger replicatedCount = 0;
    int32_t reqID = [session sendRequest:@[@"createHistoryStream"] args:@[args] type:@"source" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "Feed replication error for %{public}@: %{public}@", feedAuthor, error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                    [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:feedAuthor];
                }
            });
            return;
        }
        
        if ([response isKindOfClass:[NSDictionary class]]) {
            NSDictionary *val = response[@"value"];
            if ([SSBMessageCodec verifyMessage:val]) {
                SSBMessage *msg = [[SSBMessage alloc] init];
                msg.key = response[@"key"];
                msg.author = val[@"author"];
                msg.sequence = [val[@"sequence"] integerValue];
                msg.previousKey = val[@"previous"];
                msg.claimedTimestamp = [val[@"timestamp"] longLongValue];
                msg.content = val[@"content"];
                msg.contentType = msg.content[@"type"];
                msg.valueJSON = [SSBMessageCodec encodeLegacyValue:val includeSignature:YES];
                if ([self.feedStore appendMessage:msg error:nil]) {
                    replicatedCount++;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:SRNewMessageNotification object:nil];
                    });
                }
            }
        }
        if (!response && replicatedCount > 0) {
            if ([self.delegate respondsToSelector:@selector(roomClient:didReplicateMessagesFromPeer:count:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate roomClient:self didReplicateMessagesFromPeer:peerID count:replicatedCount];
                });
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                    [self.delegate roomClient:self didUpdateSyncStatus:[NSString stringWithFormat:@"Synced %ld from %@", (long)replicatedCount, [peerID substringToIndex:MIN(10, peerID.length)]] progress:1.0 author:feedAuthor];
                }
            });
        } else if (!response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                    [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:feedAuthor];
                }
            });
        }
    }];
    
    // sendRPCRequest returns -1 if not connected — completion never fires
    if (reqID < 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
                [self.delegate roomClient:self didUpdateSyncStatus:@"Idle" progress:1.0 author:feedAuthor];
            }
        });
    }
}

- (void)ping {
    [self sendRPCRequest:@[@"tunnel", @"ping"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (!error && [self.delegate respondsToSelector:@selector(roomClientDidPingSuccessfully:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate roomClientDidPingSuccessfully:self];
            });
        }
    }];
}

- (void)announce {
    __weak typeof(self) weakSelf = self;
    [self announceWithCompletion:^{
        [weakSelf subscribeToEndpoints];
    }];
}

- (void)announceWithCompletion:(void(^ _Nullable)(void))completion {
    __weak typeof(self) weakSelf = self;
    [self sendRPCRequest:@[@"tunnel", @"announce"] args:@[] type:@"async" completion:^(id _Nullable response, NSError * _Nullable error) {
        if (!error) {
            [weakSelf log:@"Announce success"];
            if (completion) completion();
        } else {
            [weakSelf log:[NSString stringWithFormat:@"Announce failed: %@", error.localizedDescription]];
            // Still proceed? some servers might return error if already announced
            if (completion) completion();
        }
    }];
}

- (void)subscribeToEndpoints {
    NSArray<NSString *> *method = [self preferredEndpointDiscoveryMethod];
    [self subscribeToEndpointDiscoveryMethod:method reason:nil];
}

- (void)handleAttendantsResponse:(id)response {
    id normalizedResponse = [self normalizedAttendantsPayloadFromResponse:response];
    [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"handleAttendantsResponse rawClass=%@ normalizedClass=%@",
                                         NSStringFromClass([response class]),
                                         NSStringFromClass([normalizedResponse class])]];
    os_log_debug(ssb_room_log,
                 "Received attendants response (%{public}@): %{public}@",
                 NSStringFromClass([normalizedResponse class]),
                 normalizedResponse);

    BOOL handled = NO;
    // Legacy `tunnel.endpoints` (Room v1) returns a direct NSArray of peer IDs.
    if ([normalizedResponse isKindOfClass:[NSArray class]]) {
        NSArray *items = (NSArray *)normalizedResponse;
        BOOL sawEventDictionaries = NO;
        for (id item in items) {
            if ([item isKindOfClass:[NSDictionary class]] && [self isAttendantsEventDictionary:(NSDictionary *)item]) {
                sawEventDictionaries = YES;
                NSDictionary *event = (NSDictionary *)[self normalizedAttendantsPayloadFromResponse:item];
                if ([event isKindOfClass:[NSDictionary class]] && [self applyAttendantsEventDictionary:event]) {
                    handled = YES;
                }
            }
        }

        if (!sawEventDictionaries || !handled) {
            NSArray<NSString *> *peerIDs = [self filteredAttendantPeerIDs:[self normalizedPeerIDsFromCollection:items]];
            if (peerIDs.count > 0 || items.count == 0) {
                [self.attendantsList removeAllObjects];
                [self.attendantsList addObjectsFromArray:peerIDs];
                for (NSString *peerID in peerIDs) {
                    [self replicateFromPeer:peerID viaRoom:self.host];
                }
                handled = YES;
            }
        }
    } else if ([normalizedResponse isKindOfClass:[NSDictionary class]]) {
        handled = [self applyAttendantsEventDictionary:(NSDictionary *)normalizedResponse];
    }

    if (!handled) {
        os_log_info(ssb_room_log,
                    "Unhandled attendants payload (%{public}@) for %{public}@",
                    NSStringFromClass([normalizedResponse class]),
                    self.host);
        [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"unhandled attendants payload class=%@ payload=%@",
                                             NSStringFromClass([normalizedResponse class]),
                                             normalizedResponse]];
    }

    os_log_info(ssb_room_log, "Parsed attendants for %{public}@: %lu peers", self.host, (unsigned long)self.attendantsList.count);
    [self appendPeerDiscoveryDiagnostic:[NSString stringWithFormat:@"parsed attendants peers=%lu list=%@",
                                         (unsigned long)self.attendantsList.count,
                                         self.attendantsList]];
    
    if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateEndpoints:)]) {
        os_log_debug(ssb_room_log, "Notifying delegate of %lu endpoints for %{public}@", (unsigned long)self.attendantsList.count, self.host);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate roomClient:self didUpdateEndpoints:[self.attendantsList copy]];
        });
    }
}

- (void)connectToPeer:(NSString *)targetPeerId {
    os_log_debug(ssb_room_log, "connectToPeer: %{public}@", targetPeerId);
    NSString *base64Key = nil;
    if ([targetPeerId hasPrefix:@"@"] && [targetPeerId hasSuffix:@".ed25519"]) {
        base64Key = [targetPeerId substringWithRange:NSMakeRange(1, targetPeerId.length - 9)];
    }
    
    if (!base64Key) {
        [self log:[NSString stringWithFormat:@"Invalid target peer ID: %@", targetPeerId]];
        [self reportSyncStatus:@"Unavailable" progress:1.0 author:targetPeerId];
        return;
    }
    
    long paddingLength = (4 - (base64Key.length % 4)) % 4;
    NSString *paddedKey = [base64Key stringByPaddingToLength:base64Key.length + paddingLength withString:@"=" startingAtIndex:0];
    
    NSData *remotePubKey = [[NSData alloc] initWithBase64EncodedString:paddedKey options:0];
    if (!remotePubKey) {
        [self log:[NSString stringWithFormat:@"Invalid base64 in peer ID: %@", targetPeerId]];
        [self reportSyncStatus:@"Unavailable" progress:1.0 author:targetPeerId];
        return;
    }

    NSString *localPeerID = [self localPublicID];
    if (localPeerID.length > 0 && [targetPeerId isEqualToString:localPeerID]) {
        [self reportSyncStatus:@"This Device" progress:1.0 author:targetPeerId];
        return;
    }
    
    NSString *portalId = [NSString stringWithFormat:@"@%@.ed25519", [self.serverPubKey base64EncodedStringWithOptions:0]];
    NSString *originPeerId = [self localPublicID];
    NSMutableDictionary *args = [@{
        @"portal": portalId,
        @"target": targetPeerId
    } mutableCopy];
    if (originPeerId.length > 0) {
        args[@"origin"] = originPeerId;
    }
    
    __weak typeof(self) weakSelf = self;
    __block int32_t reqID = 0;
    reqID = [self sendRPCRequest:@[@"tunnel", @"connect"] args:@[[args copy]] type:@"duplex" completion:^(id _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        SSBTunnelConnection *tunnel = strongSelf.activeTunnels[targetPeerId];
        if (error || !tunnel) {
            os_log_error(ssb_room_log, "Tunnel connection failed to %@", targetPeerId);
            [strongSelf.activeTunnels removeObjectForKey:targetPeerId];
            NSString *status = error ? [strongSelf syncStatusForTunnelError:error] : @"Unavailable";
            NSTimeInterval retryDelay = [strongSelf tunnelRetryDelayForStatus:status];
            [strongSelf setNextTunnelRetryDate:[NSDate dateWithTimeIntervalSinceNow:retryDelay] forPeer:targetPeerId];
            [strongSelf reportSyncStatus:status progress:1.0 author:targetPeerId];
            return;
        }
        
        if ([response isKindOfClass:[NSData class]]) {
            [tunnel receiveTunnelData:(NSData *)response];
        } else if ([response isKindOfClass:[NSString class]]) {
            [tunnel receiveTunnelData:[(NSString *)response dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }];

    if (reqID < 0) {
        [self reportSyncStatus:@"Disconnected" progress:1.0 author:targetPeerId];
        return;
    }
    
    SSBTunnelConnection *tunnel = [[SSBTunnelConnection alloc] initWithPeerId:targetPeerId
                                                              peerPublicKey:remotePubKey
                                                              localIdentity:self.localIdentitySecret
                                                                roomSession:self.rpcSession
                                                                tunnelReqID:reqID
                                                                   isServer:NO];
    
    __weak typeof(self) weakSelfOuter = self;
    tunnel.onConnectionStateReady = ^{
        __strong typeof(weakSelfOuter) strongSelfOuter = weakSelfOuter;
        if (strongSelfOuter) {
            os_log_info(ssb_room_log, "Tunnel to %@ is ready for RPC!", targetPeerId);
            [strongSelfOuter setNextTunnelRetryDate:nil forPeer:targetPeerId];
            [strongSelfOuter reportTunnelReadyForPeer:targetPeerId];
            [strongSelfOuter replicateFromPeer:targetPeerId viaRoom:strongSelfOuter.host];
        }
    };
    
    [tunnel start];
    
    self.activeTunnels[targetPeerId] = tunnel;
}

- (void)disconnect {
    if (self.connection) [self.connection cancel];
    self.isConnected = NO;
    self.isSyncingLocalFeed = NO;
    self.endpointDiscoveryMethodInUse = nil;
    self.endpointDiscoverySubscriptionGeneration += 1;
    self.endpointDiscoveryReceivedEvent = NO;
    [self appendPeerDiscoveryDiagnostic:@"disconnect called"];
}

- (int32_t)sendRPCRequest:(NSArray<NSString *> *)name args:(NSArray *)args type:(NSString *)type completion:(SSBRPCCallback)completion {
    if (!self.isConnected) {
        SSBLogWarning(SSBLogCategoryNetwork, @"❌ sendRPCRequest FAILED: Not connected - %@", name);
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SSBRoomClient" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected to server"}];
            completion(nil, error);
        }
        return -1;
    }
    SSBLogInfo(SSBLogCategoryNetwork, @"📤 RPC Request: %@ type: %@ args: %@", name, type, args);
    return [self.rpcSession sendRequest:name args:args type:type completion:^(id response, NSError *error) {
        if (error) {
            SSBLogError(SSBLogCategoryNetwork, @"❌ RPC Response error: %@ for %@", error.localizedDescription, name);
        } else {
            SSBLogInfo(SSBLogCategoryNetwork, @"✅ RPC Response: %@", name);
        }
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void)getSubset:(NSDictionary<NSString *, id> *)query
          options:(NSDictionary<NSString *, id> *)options
       completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    
    NSMutableDictionary *args = [NSMutableDictionary dictionaryWithDictionary:options];
    args[@"query"] = query;
    args[@"querylang"] = @"ssb-ql-0";
    
    [self sendRPCRequest:@[@"getSubset"] args:@[args] type:@"source" completion:completion];
}

- (void)handleServerInitiatedRequest:(id)payload requestID:(int32_t)reqID flags:(uint8_t)flags {
    os_log_debug(ssb_room_log, "Server initiated message: ID=%d flags=%u", reqID, flags);
    
    // Check if this belongs to an active tunnel (Server-initiated duplex stream)
    for (SSBTunnelConnection *tunnel in self.activeTunnels.allValues) {
        if (!tunnel.isServer) {
            continue;
        }
        if (llabs((long long)tunnel.tunnelReqID) == llabs((long long)reqID)) {
            NSData *data = nil;
            if ([payload isKindOfClass:[NSData class]]) {
                data = (NSData *)payload;
            } else if ([payload isKindOfClass:[NSString class]]) {
                data = [(NSString *)payload dataUsingEncoding:NSUTF8StringEncoding];
            }
            
            if (data) {
                [tunnel receiveTunnelData:data];
                return;
            }
        }
    }
    
    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *req = (NSDictionary *)payload;
        NSArray *name = req[@"name"];
        if ([name isKindOfClass:[NSArray class]] && [name.firstObject isEqualToString:@"getSubset"]) {
            [self handleGetSubset:req requestID:reqID];
        } else if ([name isKindOfClass:[NSArray class]] && name.count >= 2 && 
                   [name[0] isEqualToString:@"tunnel"] && [name[1] isEqualToString:@"connect"]) {
            [self handleTunnelConnect:req requestID:reqID];
        }
    }
}

- (void)handleGetSubset:(NSDictionary *)req requestID:(int32_t)reqID {
    NSArray *argsArr = req[@"args"];
    if (![argsArr isKindOfClass:[NSArray class]] || argsArr.count == 0) return;
    
    NSDictionary *args = argsArr.firstObject;
    NSDictionary *query = args[@"query"];
    NSString *qlang = args[@"querylang"];
    
    if (![qlang isEqualToString:@"ssb-ql-0"] || ![SSBQueryEngine isValidQuery:query]) {
        NSDictionary *err = @{@"name": @"Error", @"message": @"Invalid query or unsupported querylang"};
        [self sendRPCResponse:err requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
        return;
    }
    
    NSArray<SSBMessage *> *results = [self.feedStore querySubset:query options:args];
    
    for (SSBMessage *msg in results) {
        NSDictionary *value = [NSJSONSerialization JSONObjectWithData:msg.valueJSON options:0 error:nil];
        if (value) {
            [self sendRPCResponse:value requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream];
        }
    }
    
    [self sendRPCResponse:@YES requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr | SSBMuxRPCFlagStream];
}

- (void)handleTunnelConnect:(NSDictionary *)req requestID:(int32_t)reqID {
    NSArray *argsArr = req[@"args"];
    if (![argsArr isKindOfClass:[NSArray class]] || argsArr.count == 0) {
        [self sendRPCResponse:@{@"name": @"Error", @"message": @"Missing args"} requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
        return;
    }
    
    NSDictionary *args = argsArr.firstObject;
    NSString *portal = args[@"portal"];
    NSString *target = args[@"target"];
    
    if (![target isEqualToString:[self localPublicID]]) {
        [self sendRPCResponse:@{@"name": @"Error", @"message": @"Target mismatch"} requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
        return;
    }
    
    NSString *originPeerId = args[@"origin"] ?: portal;
    
    NSData *remotePubKey = [self publicKeyFromPeerID:originPeerId];
    if (!remotePubKey) {
        [self sendRPCResponse:@{@"name": @"Error", @"message": @"Invalid origin peer ID"} requestID:reqID flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
        return;
    }
    
    os_log_info(ssb_room_log, "Accepting tunnel connection from %@", originPeerId);
    
    SSBTunnelConnection *tunnel = [[SSBTunnelConnection alloc] initWithPeerId:originPeerId
                                                               peerPublicKey:remotePubKey
                                                               localIdentity:self.localIdentitySecret
                                                                 roomSession:self.rpcSession
                                                                 tunnelReqID:reqID
                                                                    isServer:YES];
    
    __weak typeof(self) weakSelf = self;
    tunnel.onConnectionStateReady = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            os_log_info(ssb_room_log, "Incoming tunnel from %@ is ready!", originPeerId);
            [strongSelf setNextTunnelRetryDate:nil forPeer:originPeerId];
            [strongSelf reportTunnelReadyForPeer:originPeerId];
            [strongSelf replicateFromPeer:originPeerId viaRoom:strongSelf.host];
        }
    };
    
    [tunnel start];
    self.activeTunnels[originPeerId] = tunnel;
}

- (NSData *)publicKeyFromPeerID:(NSString *)peerID {
    if ([peerID hasPrefix:@"@"] && [peerID hasSuffix:@".ed25519"]) {
        NSString *base64Key = [peerID substringWithRange:NSMakeRange(1, peerID.length - 9)];
        long paddingLength = (4 - (base64Key.length % 4)) % 4;
        NSString *paddedKey = [base64Key stringByPaddingToLength:base64Key.length + paddingLength withString:@"=" startingAtIndex:0];
        return [[NSData alloc] initWithBase64EncodedString:paddedKey options:0];
    }
    return nil;
}

- (void)sendRPCResponse:(id)payload requestID:(int32_t)reqID flags:(SSBMuxRPCFlags)flags {
    if (!self.isConnected) return;
    
    NSData *bodyData = nil;
    if ([payload isKindOfClass:[NSData class]]) {
        bodyData = payload;
    } else {
        bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    }
    
    if (!bodyData) return;
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:-reqID body:bodyData];
    [self sendRPCMessage:msg];
}

- (void)log:(NSString *)msg {
    os_log_info(ssb_room_log, "%{public}@", msg);
    if ([self.delegate respondsToSelector:@selector(roomClient:didLogMessage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate roomClient:self didLogMessage:msg];
        });
    }
}

- (NSString *)localPublicID {
    return SSBPublicIDFromSecret(self.localIdentitySecret) ?: @"";
}

- (NSString *)serverPublicID {
    return [NSString stringWithFormat:@"@%@.ed25519", [self.serverPubKey base64EncodedStringWithOptions:0]];
}

- (BOOL)isFeedSynced {
    // Feed is synced if we're not actively syncing AND local sequence matches server
    return !self.isSyncingLocalFeed;
}

- (void)scheduleReconnect {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), self.clientQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf connect];
    });
}

- (void)verifyFeedIntegrity:(NSString *)feedID
                     author:(NSString *)author
                     format:(SSBBFEFeedFormat)format
                 completion:(void(^)(BOOL, NSError *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Only GabbyGrove and Bamboo support lipmaa-based verification.
        if (format != SSBBFEFeedFormatGabbygroveV1 && format != SSBBFEFeedFormatBamboo) {
            if (completion) completion(YES, nil);
            return;
        }

        SSBFeedState *state = [self.feedStore feedStateForAuthor:author];
        if (!state || state.maxSequence <= 0) {
            if (completion) completion(YES, nil); // empty feed is trivially valid
            return;
        }

        id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                                  codecForFeedFormat:format];
        if (!codec) {
            NSError *err = [NSError errorWithDomain:@"SSBRoomClient" code:10
                userInfo:@{NSLocalizedDescriptionKey: @"No codec for feed format"}];
            if (completion) completion(NO, err);
            return;
        }

        // Walk the lipmaa chain backwards from the tip.
        // Each iteration verifies the entry at `seq` and jumps to lipmaaSeq.
        NSInteger seq = state.maxSequence;
        BOOL valid = YES;
        NSError *verifyError = nil;

        while (seq > 0) {
            NSArray<SSBMessage *> *msgs = [self.feedStore messagesForAuthor:author
                                                              fromSequence:seq
                                                                     limit:1];
            SSBMessage *msg = msgs.firstObject;
            if (!msg) {
                verifyError = [NSError errorWithDomain:@"SSBRoomClient" code:11
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Missing seq %ld for %@", (long)seq, author]}];
                valid = NO;
                break;
            }

            NSError *err = nil;
            if (![codec verifyMessageData:msg.valueJSON error:&err]) {
                verifyError = err;
                valid = NO;
                break;
            }

            NSInteger lipmaaSeq = [SSBBamboo lipmaaSequenceFor:seq];
            if (lipmaaSeq <= 0 || lipmaaSeq >= seq) break; // reached the beginning
            seq = lipmaaSeq;
        }

        if (completion) completion(valid, verifyError);
    });
}

+ (void)resetLocalIdentity {
    SSBDeleteIdentitySecret();
    SSBSavePublishedMessageCount(0);
    os_log_info(ssb_room_log, "Local identity reset. A new one will be generated on next connection.");
}

+ (NSData *)generateLocalIdentity {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_keypair(pk, sk);
    NSData *secret = [NSData dataWithBytes:sk length:64];
    
    SSBSaveIdentitySecret(secret);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRLocalIdentityGeneratedNotification object:nil];
    });
    
    os_log_info(ssb_room_log, "New local identity generated.");
    return secret;
}

@end
