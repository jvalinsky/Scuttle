#import "SSBTunnelConnection.h"
#import "SSBSecurityFramer.h"
#import "SSBMuxRPCFramer.h"
#import <os/log.h>
#import <Network/Network.h>

@interface SSBTunnelConnection ()
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, strong, readwrite) NSString *peerId;
@property (nonatomic, strong, readwrite) SSBMuxRPCSession *rpcSession;

@property (nonatomic, strong) NSData *peerPublicKey;
@property (nonatomic, strong) NSData *localIdentity;
@property (nonatomic, weak) SSBMuxRPCSession *roomSession;
@property (nonatomic, assign) int32_t tunnelReqID;

@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) nw_connection_t serverConnection;
@property (nonatomic, strong) nw_connection_t clientConnection;
@property (nonatomic, strong) dispatch_queue_t tunnelQueue;
@property (nonatomic, strong) os_log_t log;
@property (nonatomic, assign) BOOL isHandshakeComplete;
@property (nonatomic, strong) NSMutableArray<SSBMuxRPCMessage *> *pendingMessages;
@end

@implementation SSBTunnelConnection

- (instancetype)initWithPeerId:(NSString *)peerId
                 peerPublicKey:(NSData *)peerPublicKey
                 localIdentity:(NSData *)localSecret
                   roomSession:(SSBMuxRPCSession *)roomSession
                   tunnelReqID:(int32_t)tunnelReqID {
    self = [super init];
    if (self) {
        _log = os_log_create("com.scuttlebutt.tunnel", "Connection");
        _peerId = peerId;
        _peerPublicKey = peerPublicKey;
        _localIdentity = localSecret;
        _roomSession = roomSession;
        _tunnelReqID = tunnelReqID;
        _tunnelQueue = dispatch_queue_create("com.scuttlebutt.tunnel.queue", DISPATCH_QUEUE_SERIAL);
        _pendingMessages = [NSMutableArray array];
        
        _rpcSession = [[SSBMuxRPCSession alloc] init];
        
        __weak typeof(self) weakSelf = self;
        _rpcSession.sendMessageBlock = ^(SSBMuxRPCMessage *message) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            if (!strongSelf.isHandshakeComplete) {
                [strongSelf.pendingMessages addObject:message];
                return;
            }
            
            if (strongSelf.clientConnection) {
                NSData *data = [message serialize];
                if (!data) return;
                
                dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, strongSelf.tunnelQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_connection_send(strongSelf.clientConnection, dispatchData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable error) {
                    if (error) {
                        os_log_error(strongSelf.log, "Failed to send MuxRPC message over tunnel: %{public}@", error);
                    }
                });
            }
        };
        
        _rpcSession.receiveRequestBlock = ^(id payload, int32_t requestID, uint8_t flags) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // The tunnel connection itself can receive EBT requests or subset requests from the peer.
            // Currently, RoomClient handles server-initiated requests. It will need to proxy them if needed.
            // Since this is for EBT initially, we just log it unless we add a delegate later.
            os_log_debug(strongSelf.log, "Unhandled tunnel request: req=%d payload=%{public}@", requestID, payload);
        };
    }
    return self;
}

- (void)start {
    nw_parameters_t listenerParams = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_endpoint_t localEndpoint = nw_endpoint_create_host("127.0.0.1", "0");
    nw_parameters_set_local_endpoint(listenerParams, localEndpoint);
    
    self.listener = nw_listener_create(listenerParams);
    nw_listener_set_queue(self.listener, self.tunnelQueue);
    
    __weak typeof(self) weakSelf = self;
    
    nw_listener_set_state_changed_handler(self.listener, ^(nw_listener_state_t state, nw_error_t error) {
        if (state == nw_listener_state_ready) {
            [weakSelf connectClient];
        } else if (state == nw_listener_state_failed) {
            os_log_error(weakSelf.log, "Tunnel listener failed: %{public}@", error);
        }
    });
    
    nw_listener_set_new_connection_handler(self.listener, ^(nw_connection_t connection) {
        os_log_info(weakSelf.log, "Tunnel listener accepted connection");
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.serverConnection = connection;
        nw_connection_set_queue(connection, strongSelf.tunnelQueue);
        
        nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
            if (state == nw_connection_state_ready) {
                [weakSelf readFromServerConnection];
            } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
                [weakSelf stop];
            }
        });
        
        nw_connection_start(connection);
    });
    
    nw_listener_start(self.listener);
}

- (void)connectClient {
    uint16_t port = nw_listener_get_port(self.listener);
    NSString *portStr = [NSString stringWithFormat:@"%u", port];
    nw_endpoint_t connectEndpoint = nw_endpoint_create_host("127.0.0.1", portStr.UTF8String);
    
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    
    // Add the Secret Handshake and Box Stream protocol
    nw_protocol_options_t secOptions = [SSBSecurityFramer createOptionsWithLocalSecretKey:self.localIdentity remotePublicKey:self.peerPublicKey];
    nw_protocol_stack_prepend_application_protocol(nw_parameters_copy_default_protocol_stack(params), secOptions);
    
    // Add the MuxRPC protocol
    nw_protocol_options_t muxOptions = [SSBMuxRPCFramer createOptions];
    nw_protocol_stack_prepend_application_protocol(nw_parameters_copy_default_protocol_stack(params), muxOptions);
    
    self.clientConnection = nw_connection_create(connectEndpoint, params);
    nw_connection_set_queue(self.clientConnection, self.tunnelQueue);
    
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(self.clientConnection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            os_log_info(weakSelf.log, "Tunnel client connection (with framers) ready");
            weakSelf.isConnected = YES;
            weakSelf.isHandshakeComplete = YES;
            
            NSArray<SSBMuxRPCMessage *> *pending = [weakSelf.pendingMessages copy];
            [weakSelf.pendingMessages removeAllObjects];
            for (SSBMuxRPCMessage *msg in pending) {
                weakSelf.rpcSession.sendMessageBlock(msg);
            }
            
            if (weakSelf.onConnectionStateReady) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.onConnectionStateReady();
                });
            }
            
            // Now we can begin reading MuxRPC messages from the framer stack
            [weakSelf readFromClientConnection];
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            os_log_error(weakSelf.log, "Tunnel client connection failed: %{public}@", error);
            weakSelf.isConnected = NO;
            [weakSelf stop];
        }
    });
    
    nw_connection_start(self.clientConnection);
}

- (void)receiveTunnelData:(NSData *)data {
    if (!self.serverConnection) return;
    
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, self.tunnelQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    nw_connection_send(self.serverConnection, dispatchData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable error) {
        if (error) {
            os_log_error(self.log, "Failed to write incoming tunnel data to server socket: %{public}@", error);
        }
    });
}

- (void)readFromServerConnection {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive(self.serverConnection, 1, 65536, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (content) {
            // Data successfully processed by the client framer stack, now encrypted/framed bytes to send to the real network (room)
            NSData *data = (NSData *)content;
            if (data.length > 0) {
                [strongSelf.roomSession sendData:data forRequest:strongSelf.tunnelReqID isEnd:NO];
            }
        }
        
        if (is_complete || error) {
            [strongSelf stop];
        } else {
            [strongSelf readFromServerConnection];
        }
    });
}

- (void)readFromClientConnection {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive_message(self.clientConnection, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (content) {
            // A fully framed MuxRPC message has been decrypted and extracted
            NSData *data = (NSData *)content;
            nw_protocol_metadata_t metadata = nw_content_context_copy_protocol_metadata(context, [SSBMuxRPCFramer createDefinition]);
            
            if (metadata) {
                uint8_t flags = 0;
                int32_t reqNum = 0;
                
                // Fetch the values from the framer metadata
                nw_framer_message_t framerMsg = (nw_framer_message_t)metadata;
                NSNumber *flagsNum = nw_framer_message_copy_object_value(framerMsg, "Flags");
                NSNumber *reqNumNum = nw_framer_message_copy_object_value(framerMsg, "RequestNumber");
                
                if (flagsNum && reqNumNum) {
                    flags = [flagsNum unsignedCharValue];
                    reqNum = [reqNumNum intValue];
                    
                    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:data];
                    [strongSelf.rpcSession handleIncomingMessage:msg];
                }
            }
        }
        
        if (is_complete || error) {
            [strongSelf stop];
        } else {
            [strongSelf readFromClientConnection];
        }
    });
}

- (void)stop {
    self.isConnected = NO;
    if (self.clientConnection) {
        nw_connection_cancel(self.clientConnection);
        self.clientConnection = nil;
    }
    if (self.serverConnection) {
        nw_connection_cancel(self.serverConnection);
        self.serverConnection = nil;
    }
    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = nil;
    }
}

@end
