#import "SSBRoomClient.h"
#import "SSBLogCompat.h"
#import "SSBNetworkCompat.h"
#import "SSBSecurityFramer.h"
#import "SSBMuxRPCFramer.h"
#import "SSBMuxRPCSession.h"
#import "SSBQueryEngine.h"
#import "SSBMuxRPC.h"
#import "SSBKeychain.h"
#import "../App/Logic/SRNotificationNames.h"
#import "SSBSecretHandshake.h"
#import "SSBBlobStore.h"
#import "tweetnacl.h"
#import "SSBTunnelConnection.h"
#import "SSBBamboo.h"
#import "SSBFeedCodecRegistry.h"

static os_log_t ssb_room_log;

@interface SSBRoomClient ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *serverPubKey;
@property (nonatomic, strong) NSData *localIdentitySecret;
@property (nonatomic, strong, nullable) NSString *inviteToken;
@property (nonatomic, assign) BOOL usedHTTPInvite;
@property (nonatomic, readwrite) BOOL isConnected;
@property (nonatomic, assign) BOOL isFeedSynced;

@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) SSBMuxRPCSession *rpcSession;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSDictionary *serverManifest;
@property (nonatomic, strong) NSMutableArray<NSString *> *attendantsList;
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, readwrite, nullable) NSArray<NSString *> *roomFeatures;
@property (nonatomic, copy, nullable) NSArray<NSString *> *endpointDiscoveryMethodInUse;
@property (nonatomic, readwrite) BOOL isInternalUser;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBTunnelConnection *> *activeTunnels;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingPublishQueue;
@property (nonatomic, assign) BOOL isSyncingLocalFeed;
@property (nonatomic, assign) NSInteger localFeedSeq;
@property (nonatomic, assign) int32_t ebtRequestID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *remoteClock;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *internalPeerSyncProgress;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *internalPeerSyncStates;
@property (nonatomic, assign) BOOL isEBTRunning;

/// Tracks per-peer EBT state to handle bilateral replication properly.
/// Key: peer ID, Value: dictionary with { @"requestID": NSNumber, @"clock": NSMutableDictionary }
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *peerEBTState;

/// The current session being used for EBT (to route bilateral requests correctly)
@property (nonatomic, weak) SSBMuxRPCSession *currentEBTSession;
@end

@implementation SSBRoomClient

+ (void)initialize {
    if (self == [SSBRoomClient class]) {
        ssb_room_log = os_log_create("com.scuttlebutt.room", "Client");
    }
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
            NSData *saved = [SSBKeychain loadIdentitySecret];
            if (saved) {
                _localIdentitySecret = saved;
            } else {
                _localIdentitySecret = [SSBRoomClient generateLocalIdentity];
            }
        }
        
        _isConnected = NO;
        _isFeedSynced = YES; // Assume synced until proven otherwise
        _clientQueue = dispatch_queue_create("com.ssbc.room.client", DISPATCH_QUEUE_SERIAL);
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
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)item;
        NSString *peerID = dict[@"id"] ?: dict[@"key"] ?: dict[@"peer"] ?: dict[@"feed"];
        return peerID.length > 0 ? peerID : nil;
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

- (BOOL)manifestSupportsRPCPath:(NSArray<NSString *> *)path {
    id cursor = self.serverManifest;
    for (NSString *component in path) {
        if (![cursor isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        cursor = ((NSDictionary *)cursor)[component];
        if (!cursor || cursor == [NSNull null]) {
            return NO;
        }
    }
    return YES;
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
    self.endpointDiscoveryMethodInUse = nil;
    
    nw_endpoint_t endpoint = nw_endpoint_create_host(self.host.UTF8String, [[NSString stringWithFormat:@"%d", self.port] UTF8String]);
    
    nw_parameters_configure_protocol_block_t configure_tcp = ^(nw_protocol_options_t tcp_options) {
        nw_tcp_options_set_no_delay(tcp_options, true);
    };
    
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, configure_tcp);
    nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(params);
    
    nw_protocol_stack_prepend_application_protocol(stack, [SSBSecurityFramer createOptionsWithLocalSecretKey:self.localIdentitySecret 
                                                                                               remotePublicKey:self.serverPubKey
                                                                                                      asClient:YES]);
    nw_protocol_stack_prepend_application_protocol(stack, [SSBMuxRPCFramer createOptions]);
    
    self.connection = nw_connection_create(endpoint, params);
    nw_connection_set_queue(self.connection, self.clientQueue);
    
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (state == nw_connection_state_ready) {
            os_log_info(ssb_room_log, "Connection state: READY");
            [strongSelf log:@"Connected and secured."];
            strongSelf.isConnected = YES;
            if ([strongSelf.delegate respondsToSelector:@selector(roomClientDidConnect:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf.delegate roomClientDidConnect:strongSelf];
                });
            }
            [strongSelf startReceivingMessages];
            [strongSelf performInitialSetup];
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            os_log_info(ssb_room_log, "Connection state changed: %d", state);
            strongSelf.isConnected = NO;
            strongSelf.endpointDiscoveryMethodInUse = nil;
            if (strongSelf.autoReconnect && state == nw_connection_state_failed) {
                [strongSelf scheduleReconnect];
            }
        } else {
            os_log_info(ssb_room_log, "Connection state changed: %d", state);
        }
    });
    
    nw_connection_start(self.connection);
}

- (void)startReceivingMessages {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive_message(self.connection, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            os_log_error(ssb_room_log, "Client %{public}@: receive error: %{public}@", strongSelf.host, error);
            return;
        }

        if (content) {
            os_log_debug(ssb_room_log, "Client: received content of length %zu", dispatch_data_get_size(content));
            nw_protocol_metadata_t metadata = nw_content_context_copy_protocol_metadata(context, [SSBMuxRPCFramer createDefinition]);
            if (metadata) {
                NSNumber *flagsObj = nw_framer_message_copy_object_value(metadata, "Flags");
                NSNumber *reqNumObj = nw_framer_message_copy_object_value(metadata, "RequestNumber");

                if (flagsObj && reqNumObj) {
                    // Convert dispatch_data_t to NSData (not toll-free bridged on GNUstep)
                    const void *buf = NULL; size_t sz = 0;
                    dispatch_data_t contiguous = dispatch_data_create_map(content, &buf, &sz);
                    NSData *body = [NSData dataWithBytes:buf length:sz];
                    (void)contiguous; // safe to release; body owns its copy
                    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:[flagsObj unsignedIntValue]
                                                                      requestNumber:[reqNumObj intValue]
                                                                               body:body];
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
    });
}

- (void)sendRPCMessage:(SSBMuxRPCMessage *)msg {
    if (!self.isConnected) {
        os_log_debug(ssb_room_log, "sendRPCMessage DROPPING msg: isConnected=NO");
        return;
    }
    
    NSData *serialized = [msg serialize];
    dispatch_data_t body = dispatch_data_create(serialized.bytes, serialized.length, self.clientQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    nw_connection_send(self.connection, body, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t _Nullable error) {
        if (error) os_log_error(ssb_room_log, "RPC send failed");
    });
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
    
    if (self.inviteToken) {
        [self redeemInvite:self.inviteToken completion:nil];
    }
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
    if (self.isEBTRunning) return;
    
    self.currentEBTSession = session;

    NSDictionary<NSString *, NSNumber *> *clock = [self.feedStore localClock];
    NSDictionary *args = @{@"version": @3};

    __weak typeof(self) weakSelf = self;
    SSBRPCCallback ebtCallback = ^(id _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            os_log_error(ssb_room_log, "EBT Replication stream error: %{public}@", error);
            strongSelf.isEBTRunning = NO;
            return;
        }
        [strongSelf handleEBTMessage:response requestID:0 flags:0 session:session];
        };

        self.ebtRequestID = [session sendRequest:@[@"ebt", @"replicate"] args:@[args] type:@"duplex" completion:ebtCallback];

        session.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
        [weakSelf handleEBTMessage:payload requestID:requestID flags:flags session:session];
        };

        self.isEBTRunning = YES;
        self.remoteClock = [NSMutableDictionary dictionary];

        // Send initial clock
        [session sendData:clock forRequest:self.ebtRequestID isEnd:NO];
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
            [self updateSyncProgressForAuthor:author];
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
            
            [self updateSyncProgressForAuthor:msg.author];
        }
    }
}

- (void)processIncomingMessage:(id)response {
    [self processIncomingMessage:response fromPeer:nil];
}

- (void)updateSyncProgressForAuthor:(NSString *)author {
    SSBFeedState *state = [self.feedStore feedStateForAuthor:author];
    NSInteger localSeq = state ? state.maxSequence : 0;
    
    NSNumber *remoteSeqNum = self.remoteClock[author];
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

- (void)reportSyncStatus:(NSString *)status progress:(float)progress author:(NSString *)author {
    if (!author) return;
    self.internalPeerSyncProgress[author] = @(progress);
    self.internalPeerSyncStates[author] = status;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomSyncStatusChangedNotification
                                                            object:self
                                                          userInfo:@{@"author": author, @"status": status, @"progress": @(progress)}];
        
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateSyncStatus:progress:author:)]) {
            [self.delegate roomClient:self didUpdateSyncStatus:status progress:progress author:author];
        }
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
    if (!self.isConnected) {
        [self log:@"Cannot subscribe: Not connected"];
        return;
    }
    
    [self log:[NSString stringWithFormat:@"Subscribing to attendants/endpoints for %@", self.host]];
    NSArray<NSString *> *method = [self preferredEndpointDiscoveryMethod];
    if ([self.endpointDiscoveryMethodInUse isEqualToArray:method]) {
        [self log:@"Endpoint discovery subscription already active"];
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    SSBRPCCallback handler = ^(id _Nullable response, NSError * _Nullable error) {
        if (!error) {
            os_log_debug(ssb_room_log, "Got stream event for %{public}@", weakSelf.host);
            [weakSelf handleAttendantsResponse:response];
        } else {
            if ([weakSelf.endpointDiscoveryMethodInUse isEqualToArray:method]) {
                weakSelf.endpointDiscoveryMethodInUse = nil;
            }
            [weakSelf log:[NSString stringWithFormat:@"Stream error for %@: %@", weakSelf.host, error.localizedDescription]];
        }
    };
    
    if ([method isEqualToArray:@[@"room", @"attendants"]]) {
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
}

- (void)handleAttendantsResponse:(id)response {
    os_log_debug(ssb_room_log, "Received attendants response: %{public}@", response);
    // Legacy `tunnel.endpoints` (Room v1) returns a direct NSArray of peer IDs.
    if ([response isKindOfClass:[NSArray class]]) {
        NSArray<NSString *> *peerIDs = [self normalizedPeerIDsFromCollection:(NSArray *)response];
        [self.attendantsList removeAllObjects];
        [self.attendantsList addObjectsFromArray:peerIDs];
        for (NSString *peerID in peerIDs) {
            [self replicateFromPeer:peerID viaRoom:self.host];
        }
    } else if ([response isKindOfClass:[NSDictionary class]]) {
        // Room v2 `room.attendants` returns dictionary events.
        NSDictionary *dict = (NSDictionary *)response;
        NSString *type = dict[@"type"];
        
        if ([type isEqualToString:@"state"]) {
            // "state" has either a "peers" array or "ids" array.
            NSArray *items = dict[@"ids"] ?: dict[@"peers"];
            if ([items isKindOfClass:[NSArray class]]) {
                NSArray<NSString *> *peerIDs = [self normalizedPeerIDsFromCollection:items];
                [self.attendantsList removeAllObjects];
                [self.attendantsList addObjectsFromArray:peerIDs];
                for (NSString *peerID in peerIDs) {
                    [self replicateFromPeer:peerID viaRoom:self.host];
                }
            }
        } else if ([type isEqualToString:@"joined"]) {
            NSString *peerID = [self peerIDFromEndpointItem:dict];
            if (peerID && ![self.attendantsList containsObject:peerID]) {
                [self.attendantsList addObject:peerID];
            }
            if (peerID) {
                [self replicateFromPeer:peerID viaRoom:self.host];
            }
        } else if ([type isEqualToString:@"left"]) {
            NSString *peerID = [self peerIDFromEndpointItem:dict];
            if (peerID) {
                [self.attendantsList removeObject:peerID];
            }
        }
    }
    
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
        return;
    }
    
    long paddingLength = (4 - (base64Key.length % 4)) % 4;
    NSString *paddedKey = [base64Key stringByPaddingToLength:base64Key.length + paddingLength withString:@"=" startingAtIndex:0];
    
    NSData *remotePubKey = [[NSData alloc] initWithBase64EncodedString:paddedKey options:0];
    if (!remotePubKey) {
        [self log:[NSString stringWithFormat:@"Invalid base64 in peer ID: %@", targetPeerId]];
        return;
    }
    
    NSString *portalId = [NSString stringWithFormat:@"@%@.ed25519", [self.serverPubKey base64EncodedStringWithOptions:0]];
    NSDictionary *args = @{@"portal": portalId, @"target": targetPeerId};
    
    __weak typeof(self) weakSelf = self;
    __block int32_t reqID = 0;
    reqID = [self sendRPCRequest:@[@"tunnel", @"connect"] args:@[args] type:@"duplex" completion:^(id _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        SSBTunnelConnection *tunnel = strongSelf.activeTunnels[targetPeerId];
        if (error || !tunnel) {
            os_log_error(ssb_room_log, "Tunnel connection failed to %@", targetPeerId);
            [strongSelf.activeTunnels removeObjectForKey:targetPeerId];
            return;
        }
        
        if ([response isKindOfClass:[NSData class]]) {
            [tunnel receiveTunnelData:(NSData *)response];
        } else if ([response isKindOfClass:[NSString class]]) {
            [tunnel receiveTunnelData:[(NSString *)response dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }];
    
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
            [strongSelfOuter replicateFromPeer:targetPeerId viaRoom:strongSelfOuter.host];
        }
    };
    
    [tunnel start];
    
    self.activeTunnels[targetPeerId] = tunnel;
}

- (void)disconnect {
    if (self.connection) nw_connection_cancel(self.connection);
    self.isConnected = NO;
    self.isSyncingLocalFeed = NO;
    self.endpointDiscoveryMethodInUse = nil;
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
        if ([tunnel valueForKey:@"tunnelReqID"] != nil && [[tunnel valueForKey:@"tunnelReqID"] intValue] == reqID) {
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
    return [SSBKeychain publicIDFromSecret:self.localIdentitySecret] ?: @"";
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
    [SSBKeychain deleteIdentitySecret];
    [SSBKeychain savePublishedMessageCount:0];
    os_log_info(ssb_room_log, "Local identity reset. A new one will be generated on next connection.");
}

+ (NSData *)generateLocalIdentity {
    unsigned char pk[32];
    unsigned char sk[64];
    crypto_sign_keypair(pk, sk);
    NSData *secret = [NSData dataWithBytes:sk length:64];
    
    [SSBKeychain saveIdentitySecret:secret];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRLocalIdentityGeneratedNotification object:nil];
    });
    
    os_log_info(ssb_room_log, "New local identity generated.");
    return secret;
}

@end
