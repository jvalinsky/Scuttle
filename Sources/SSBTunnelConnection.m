#import "SSBTunnelConnection.h"
#import "SSBLogCompat.h"

#define NW_MAX_FRAME_SIZE 65535

@interface SSBTunnelConnection ()
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, strong, readwrite) NSString *peerId;
@property (nonatomic, strong, readwrite) SSBMuxRPCSession *rpcSession;

@property (nonatomic, strong) NSData *peerPublicKey;
@property (nonatomic, strong) NSData *localIdentity;
@property (nonatomic, weak) SSBMuxRPCSession *roomSession;
@property (nonatomic, assign) int32_t tunnelReqID;
@property (nonatomic, assign) BOOL isServer;
@property (nonatomic, strong) id<SSBTransportBackend> transportBackend;

@property (nonatomic, strong) id<SSBTransportListener> listener;
@property (nonatomic, strong) id<SSBTransportConnection> serverConnection;
@property (nonatomic, strong) id<SSBTransportConnection> clientConnection;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t tunnelQueue;
@property (nonatomic, strong) os_log_t log;
@property (nonatomic, assign) BOOL isHandshakeComplete;
@property (nonatomic, strong) NSMutableArray<SSBMuxRPCMessage *> *pendingMessages;
@property (nonatomic, strong) NSMutableArray<NSData *> *incomingBuffer;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingIncomingRequests;
@end

@implementation SSBTunnelConnection

- (instancetype)initWithPeerId:(NSString *)peerId
                 peerPublicKey:(NSData *)peerPublicKey
                 localIdentity:(NSData *)localSecret
                   roomSession:(SSBMuxRPCSession *)roomSession
                   tunnelReqID:(int32_t)tunnelReqID
                      isServer:(BOOL)isServer {
    self = [super init];
    if (self) {
        _log = os_log_create("com.scuttlebutt.tunnel", "Connection");
        _peerId = peerId;
        _peerPublicKey = peerPublicKey;
        _localIdentity = localSecret;
        _roomSession = roomSession;
        _tunnelReqID = tunnelReqID;
        _isServer = isServer;
        _tunnelQueue = dispatch_queue_create("com.scuttlebutt.tunnel.queue", DISPATCH_QUEUE_SERIAL);
        _transportBackend = [SSBTransport defaultBackend];
        _pendingMessages = [NSMutableArray array];
        _incomingBuffer = [NSMutableArray array];
        _pendingIncomingRequests = [NSMutableArray array];
        
        _rpcSession = [[SSBMuxRPCSession alloc] init];
        
        __weak typeof(self) weakSelf = self;
        _rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            dispatch_async(strongSelf.tunnelQueue, ^{
                if (!strongSelf.isHandshakeComplete) {
                    [strongSelf.pendingMessages addObject:message];
                    return;
                }
                
                if (strongSelf.clientConnection) {
                    NSData *data = [message serialize];
                    if (!data) return;
                    
                    [strongSelf.clientConnection sendData:data isComplete:NO completion:^(NSError * _Nullable error) {
                        if (error) {
                            os_log_error(strongSelf.log, "Failed to send MuxRPC message: %{public}@", error);
                        }
                    }];
                }
            });
        };
        
        _rpcSession.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // Buffer incoming requests until a real handler is installed (e.g. by startEBTReplicationWithSession:).
            // This prevents dropping early peer requests that arrive before EBT setup completes.
            [strongSelf.pendingIncomingRequests addObject:@{
                @"payload": payload ?: [NSNull null],
                @"requestID": @(requestID),
                @"flags": @(flags)
            }];
            os_log_debug(strongSelf.log, "Buffered tunnel request: req=%d (will replay when handler installed)", requestID);
        };
    }
    return self;
}

- (void)start {
    SSBTransportEndpoint *loopback = [SSBTransportEndpoint endpointWithHost:@"::1" port:0];
    self.listener = [self.transportBackend listenerOnEndpoint:loopback queue:self.tunnelQueue];
    
    __weak typeof(self) weakSelf = self;
    
    [self.listener setStateChangedHandler:^(id<SSBTransportListener> listener, SSBTransportListenerState state, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        os_log_debug(strongSelf.log, "Listener state changed to %lu", (unsigned long)state);
        if (state == SSBTransportListenerStateReady) {
            os_log_info(strongSelf.log, "Listener ready on port %u", strongSelf.listener.port);
            [strongSelf connectClient];
        } else if (state == SSBTransportListenerStateFailed) {
            os_log_error(strongSelf.log, "Tunnel listener failed: %{public}@", error);
        }
    }];
    
    [self.listener setNewConnectionHandler:^(id<SSBTransportConnection> connection) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        os_log_info(strongSelf.log, "Tunnel listener accepted connection");
        
        strongSelf.serverConnection = connection;
        
        // Use a fresh weak reference for the nested handler to avoid retain cycle
        __weak typeof(strongSelf) innerWeakSelf = strongSelf;
        [connection setStateChangedHandler:^(id<SSBTransportConnection> acceptedConnection, SSBTransportConnectionState state, NSError * _Nullable error) {
            __strong typeof(innerWeakSelf) innerSelf = innerWeakSelf;
            if (!innerSelf) return;
            os_log_debug(innerSelf.log, "serverConnection state changed to %lu", (unsigned long)state);
            if (state == SSBTransportConnectionStateReady) {
                os_log_info(innerSelf.log, "serverConnection (accepted) ready, starting readFromServerConnection");
                [innerSelf readFromServerConnection];
                
                // Flush buffered incoming tunnel data
                for (NSData *buffered in innerSelf.incomingBuffer) {
                    [innerSelf receiveTunnelData:buffered];
                }
                [innerSelf.incomingBuffer removeAllObjects];
            } else if (state == SSBTransportConnectionStateFailed || state == SSBTransportConnectionStateCancelled) {
                if (state == SSBTransportConnectionStateFailed) {
                    os_log_error(innerSelf.log, "serverConnection FAILED: %{public}@", error);
                } else {
                    os_log_info(innerSelf.log, "serverConnection CANCELLED");
                }
                [innerSelf stop];
            }
        }];
        
        [connection start];
    }];
    
    [self.listener start];
}

- (void)connectClient {
    SSBTransportEndpoint *endpoint = [SSBTransportEndpoint endpointWithHost:@"::1" port:self.listener.port];
    SSBTransportConnectionOptions *options = [[SSBTransportConnectionOptions alloc] init];
    options.enableSecurityFramer = YES;
    options.enableMuxRPCFramer = YES;
    options.actingAsClient = !self.isServer;
    options.localIdentitySecret = self.localIdentity;
    options.remotePublicKey = self.peerPublicKey;
    self.clientConnection = [self.transportBackend connectionToEndpoint:endpoint options:options queue:self.tunnelQueue];
    
    __weak typeof(self) weakSelf = self;
    [self.clientConnection setStateChangedHandler:^(id<SSBTransportConnection> connection, SSBTransportConnectionState state, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        os_log_debug(strongSelf.log, "clientConnection state changed to %lu", (unsigned long)state);
        if (state == SSBTransportConnectionStateReady) {
            os_log_info(strongSelf.log, "clientConnection (with framers) ready!");
            strongSelf.isConnected = YES;
            strongSelf.isHandshakeComplete = YES;
            
            NSArray<SSBMuxRPCMessage *> *pending = [strongSelf.pendingMessages copy];
            [strongSelf.pendingMessages removeAllObjects];
            for (SSBMuxRPCMessage *msg in pending) {
                strongSelf.rpcSession.sendMessageBlock(msg);
            }
            
            if (strongSelf.onConnectionStateReady) {
                void (^callback)(void) = strongSelf.onConnectionStateReady;
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback();
                });
            }
            
            // Now we can begin reading MuxRPC messages from the framer stack
            [strongSelf readFromClientConnection];
        } else if (state == SSBTransportConnectionStateFailed || state == SSBTransportConnectionStateCancelled) {
            if (state == SSBTransportConnectionStateFailed) {
                os_log_error(strongSelf.log, "Tunnel client connection failed: %{public}@", error);
            } else {
                os_log_info(strongSelf.log, "clientConnection CANCELLED");
            }
            strongSelf.isConnected = NO;
            [strongSelf stop];
        }
    }];
    
    [self.clientConnection start];
}

- (void)receiveTunnelData:(NSData *)data {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.tunnelQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        os_log_debug(strongSelf.log, "receiveTunnelData: %lu bytes", (unsigned long)data.length);
        
        if (!strongSelf.serverConnection ||
            strongSelf.serverConnection.state != SSBTransportConnectionStateReady) {
            os_log_debug(strongSelf.log,
                         "serverConnection unavailable or not ready (state=%lu), buffering %lu bytes",
                         (unsigned long)strongSelf.serverConnection.state,
                         (unsigned long)data.length);
            [strongSelf.incomingBuffer addObject:data];
            return;
        }
        
        [strongSelf.serverConnection sendData:data isComplete:NO completion:^(NSError * _Nullable error) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf) {
                os_log_debug(innerSelf.log, "receiveTunnelData: sendData completed (len=%lu) with error=%@", (unsigned long)data.length, error);
            }
            if (error) {
                os_log_error(weakSelf.log, "Failed to write incoming tunnel data to server socket: %{public}@", error);
            }
        }];
    });
}

- (void)readFromServerConnection {
    __weak typeof(self) weakSelf = self;
    [self.serverConnection receiveMinimumLength:1 maximumLength:NW_MAX_FRAME_SIZE completion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, BOOL is_complete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (content) {
                os_log_debug(strongSelf.log, "readFromServerConnection: received %lu bytes from local socket, piping to room", (unsigned long)content.length);
                if (content.length > 0) {
                    int32_t transportID = strongSelf.isServer ? -strongSelf.tunnelReqID : strongSelf.tunnelReqID;
                    [strongSelf.roomSession sendData:content forRequest:transportID isEnd:NO];
                }
            }
        
        if (error || (is_complete && content == nil)) {
            if (error) os_log_error(strongSelf.log, "serverConnection read error: %{public}@", error);
            [strongSelf stop];
        } else {
            [strongSelf readFromServerConnection];
        }
    }];
}

- (void)readFromClientConnection {
    __weak typeof(self) weakSelf = self;
    [self.clientConnection receiveMessageWithCompletion:^(NSData * _Nullable content, NSDictionary<NSString *,id> * _Nullable metadata, BOOL is_complete, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (content) {
            os_log_debug(strongSelf.log, "Client: received content of length %lu", (unsigned long)content.length);
            if (metadata) {
                os_log_debug(strongSelf.log, "Found metadata for MuxRPC message");
                uint8_t flags = 0;
                int32_t reqNum = 0;
                
                NSNumber *flagsNum = metadata[SSBTransportMetadataFlagsKey];
                NSNumber *reqNumNum = metadata[SSBTransportMetadataRequestNumberKey];
                
                if (flagsNum && reqNumNum) {
                    flags = [flagsNum unsignedCharValue];
                    reqNum = [reqNumNum intValue];
                    os_log_debug(strongSelf.log, "Extracted flags=%u reqNum=%d", flags, reqNum);
                    
                    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:content];
                    [strongSelf.rpcSession handleIncomingMessage:msg];
                } else {
                    os_log_error(strongSelf.log, "FAILED to extract flags/reqNum from metadata");
                }
            } else {
                os_log_debug(strongSelf.log, "NO METADATA found for message");
            }
        }
        
        if (error || (is_complete && content == nil)) {
            if (error) os_log_error(strongSelf.log, "clientConnection read error: %{public}@", error);
            [strongSelf stop];
        } else {
            [strongSelf readFromClientConnection];
        }
    }];
}

- (void)replayPendingIncomingRequests {
    dispatch_async(self.tunnelQueue, ^{
        NSArray<NSDictionary *> *pending = [self.pendingIncomingRequests copy];
        [self.pendingIncomingRequests removeAllObjects];
        if (pending.count > 0) {
            os_log_info(self.log, "Replaying %lu buffered tunnel requests", (unsigned long)pending.count);
        }
        for (NSDictionary *req in pending) {
            id payload = req[@"payload"];
            if ([payload isEqual:[NSNull null]]) payload = nil;
            int32_t requestID = [req[@"requestID"] intValue];
            uint8_t flags = [req[@"flags"] unsignedCharValue];
            if (self.rpcSession.receiveRequestBlock) {
                self.rpcSession.receiveRequestBlock(payload, requestID, flags);
            }
        }
    });
}

- (void)stop {
    self.isConnected = NO;
    if (self.clientConnection) {
        [self.clientConnection cancel];
        self.clientConnection = nil;
    }
    if (self.serverConnection) {
        [self.serverConnection cancel];
        self.serverConnection = nil;
    }
    if (self.listener) {
        [self.listener cancel];
        self.listener = nil;
    }
}

@end
