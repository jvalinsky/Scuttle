#import "SSBRoomClient.h"
#import <os/log.h>

#import <Network/Network.h>
#import "SSBFramer.h"
#import "SSBConnectionFSM.h"
#import "SSBSecretHandshake.h"
#import "SSBBoxStream.h"
#import "SSBMuxRPC.h"

static os_log_t ssb_room_log;

@interface SSBRPCCallState : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) SSBRPCCallback callback;
@end
@implementation SSBRPCCallState
@end

@interface SSBRoomClient () <SSBConnectionFSMDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *serverPubKey;
@property (nonatomic, strong) NSData *localIdentitySecret;

@property (nonatomic, readwrite) BOOL isConnected;

@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) SSBConnectionFSM *fsm;
@property (nonatomic, strong) SSBSecretHandshake *shs;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSMutableData *rpcBuffer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallState *> *pendingRequests;
@property (nonatomic, assign) int32_t nextRequestID;
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
               localIdentity:(NSData *)localIdentitySecret {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _serverPubKey = serverPubKey;
        _localIdentitySecret = localIdentitySecret;
        _isConnected = NO;
        _clientQueue = dispatch_queue_create("com.ssbc.room.client", DISPATCH_QUEUE_SERIAL);
        _rpcBuffer = [NSMutableData data];
        _pendingRequests = [NSMutableDictionary dictionary];
        _nextRequestID = 1;
    }
    return self;
}

- (void)connect {
    if (self.isConnected) return;
    
    os_log_info(ssb_room_log, "Connecting to room: %{public}@:%d", self.host, self.port);
    
    self.shs = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.localIdentitySecret remotePublicKey:self.serverPubKey];
    self.fsm = [[SSBConnectionFSM alloc] init];
    self.fsm.delegate = self;
    
    nw_endpoint_t endpoint = nw_endpoint_create_host(self.host.UTF8String, [[NSString stringWithFormat:@"%d", self.port] UTF8String]);
    nw_parameters_configure_protocol_block_t configure_tcp = ^(nw_protocol_options_t tcp_options) {
        nw_tcp_options_set_no_delay(tcp_options, true);
    };
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, configure_tcp);
    
    self.connection = nw_connection_create(endpoint, params);
    
    nw_connection_set_queue(self.connection, self.clientQueue);
    nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            os_log_info(ssb_room_log, "TCP connected. Initiating SHS Handshake.");
            [self performSelector:@selector(initiateHandshake) onThread:[NSThread currentThread] withObject:nil waitUntilDone:NO];
            // Since we are likely on clientQueue, just call directly or ensure queue
            dispatch_async(self.clientQueue, ^{
                [self initiateHandshake];
            });
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            os_log_error(ssb_room_log, "NW Connection state: %d", state);
            
            BOOL wasConnected = self.isConnected;
            self.isConnected = NO;
            
            if (state == nw_connection_state_failed && [self.delegate respondsToSelector:@selector(roomClient:didEncounterError:)]) {
                NSError *nsError = nil;
                if (error) {
                    nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(error);
                } else {
                    nsError = [NSError errorWithDomain:@"SSBNetwork" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Connection failed without specific error"}];
                }
                [self.delegate roomClient:self didEncounterError:nsError];
            }
            
            if (self.autoReconnect) {
                os_log_info(ssb_room_log, "Connection dropped or failed (wasConnected: %d). Attempting reconnect...", wasConnected);
                [self scheduleReconnect];
            }
        }
    });
    
    nw_connection_start(self.connection);
}

- (void)scheduleReconnect {
    static int reconnectAttempt = 0;
    reconnectAttempt++;
    
    NSTimeInterval delay = MIN(32.0, pow(2, reconnectAttempt));
    os_log_info(ssb_room_log, "Scheduling reconnect attempt %d in %.1f seconds", reconnectAttempt, delay);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.clientQueue, ^{
        if (self.autoReconnect && !self.isConnected) {
            [self connect];
        }
    });
}

- (void)initiateHandshake {
    NSData *hello = [self.shs createHello];
    dispatch_data_t out_data = dispatch_data_create(hello.bytes, hello.length, self.clientQueue, ^{
        [hello self]; // retain until send finishes
    });
    
    nw_connection_send(self.connection, out_data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t  _Nullable error) {
        if (error) {
            NSLog(@"[Client] Failed to send Client Hello: %@", error);
            [self scheduleReconnect];
            return;
        }
        [self.fsm advanceState]; // -> SHS_Hello await
        [self receiveNextHandshakeStep];
    });
}

- (void)receiveNextHandshakeStep {
    size_t expectedSize = 0;
    if (self.fsm.currentState == SSBConnectionStateSHSHelloSent) {
        expectedSize = 64; // Expecting Server Hello
    } else if (self.fsm.currentState == SSBConnectionStateSHSAuthSent) {
        expectedSize = 80; // Expecting Server Accept
    } else {
        NSLog(@"[Client] receiveNextHandshakeStep: No expected data for state %ld", (long)self.fsm.currentState);
        return;
    }
    
    NSLog(@"[Client] Calling nw_connection_receive for %zu bytes (state %ld)...", expectedSize, (long)self.fsm.currentState);
    if (!self.connection) {
        NSLog(@"[Client] ERROR: connection is nil!");
        return;
    }
    nw_connection_receive(self.connection, (uint32_t)expectedSize, (uint32_t)expectedSize, ^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, bool is_complete, nw_error_t  _Nullable error) {
        NSLog(@"[Client] nw_connection_receive callback fired. content: %@, error: %@", content, error);
        
        if (error) {
            NSLog(@"[Client] Handshake Receive Error: %@", error);
            [self.fsm transitionToError:[NSError errorWithDomain:@"SSBNetwork" code:-1 userInfo:nil]];
            return;
        }
        
        if (!content) {
            NSLog(@"[Client] Handshake Receive Error: No content (connection closed?)");
            [self.fsm transitionToError:[NSError errorWithDomain:@"SSBNetwork" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Connection closed during handshake"}]];
            return;
        }
        
        NSMutableData *data = [NSMutableData dataWithCapacity:expectedSize];
        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
            [data appendBytes:buffer length:size];
            return true;
        });
        
        if (expectedSize == 64) {
            if ([self.shs processHello:data]) {
                os_log_info(ssb_room_log, "Server Hello processed successfully.");
                NSData *auth = [self.shs createAuth];
                if (!auth) {
                    os_log_error(ssb_room_log, "Failed to create Auth message");
                    [self.fsm transitionToError:[NSError errorWithDomain:@"SSB" code:-1 userInfo:nil]];
                    return;
                }
                
                NSLog(@"[Client] Sending Auth message (%lu bytes)...", (unsigned long)auth.length);
                dispatch_data_t auth_data = dispatch_data_create(auth.bytes, auth.length, self.clientQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                
                nw_connection_send(self.connection, auth_data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t send_error) {
                    if (!send_error) {
                        NSLog(@"[Client] Auth message sent successfully.");
                        [self.fsm advanceState]; // -> SHSHelloReceived
                        [self.fsm advanceState]; // -> SHSAuthSent
                        [self receiveNextHandshakeStep];
                    } else {
                        NSLog(@"[Client] Auth message send failed: %@", send_error);
                    }
                });
            } else {
                NSLog(@"[Client] Failed to process Server Hello");
            }
        } else if (expectedSize == 80) {
            if ([self.shs processAccept:data]) {
                [self.fsm advanceState]; // -> SHSAcceptReceived
                // Advance remaining states to reach BoxStream
                while (self.fsm.currentState < SSBConnectionStateBoxStream) {
                    [self.fsm advanceState];
                }
            } else {
                NSLog(@"[Client] Failed to process Server Accept");
            }
        }
    });
}

#pragma mark - SSBConnectionFSMDelegate

- (void)connectionFSM:(id)fSM didEncounterError:(NSError *)error {
    os_log_error(ssb_room_log, "FSM Encountered Error: %{public}@", error.localizedDescription);
    [self disconnect];
}

- (void)connectionFSMDidRequestParse:(SSBConnectionFSM *)fsm {
    // Will be called by Framer when it advances states internally.
}

- (void)connectionFSMDidTransitionToBoxStream:(SSBConnectionFSM *)fsm {
    os_log_info(ssb_room_log, "Handshake complete. Transitioning to Box Stream.");
    self.isConnected = YES;
    
    self.boxStream = [[SSBBoxStream alloc] initWithClientToServerKey:self.shs.clientToServerKey
                                                   serverToClientKey:self.shs.serverToClientKey
                                                 clientToServerNonce:self.shs.clientToServerNonce
                                                 serverToClientNonce:self.shs.serverToClientNonce];
    
    // Kick off the BoxStream read loop
    [self receiveBoxStreamHeader];
    
    if ([self.delegate respondsToSelector:@selector(roomClientDidConnect:)]) {
        [self.delegate roomClientDidConnect:self];
    }
}

- (void)receiveBoxStreamHeader {
    if (!self.isConnected) return;
    
    size_t length = 34; // 18 byte header box (2 body len + 16 mac) + 16 body mac
    nw_connection_receive(self.connection, (uint32_t)length, (uint32_t)length, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        if (error || !content) {
            NSLog(@"[Client] BoxStream header read failed or connection closed");
            self.isConnected = NO;
            return;
        }
        
        NSMutableData *data = [NSMutableData dataWithCapacity:34];
        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
            [data appendBytes:buffer length:size];
            return true;
        });
        
        size_t bodyLen = 0;
        NSData *bodyMac = nil;
        if ([self.boxStream decryptHeader:data outLength:&bodyLen outBodyMac:&bodyMac]) {
            [self receiveBoxStreamBody:bodyLen expectedMac:bodyMac];
        } else {
            NSLog(@"[Client] Failed to decrypt BoxStream header");
            self.isConnected = NO;
        }
    });
}

- (void)receiveBoxStreamBody:(size_t)length expectedMac:(NSData *)mac {
    nw_connection_receive(self.connection, (uint32_t)length, (uint32_t)length, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        if (error || !content) {
            NSLog(@"[Client] BoxStream body read failed");
            return;
        }
        
        NSMutableData *data = [NSMutableData dataWithCapacity:length];
        dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
            [data appendBytes:buffer length:size];
            return true;
        });
        
        NSData *decryptedBody = [self.boxStream decryptBody:data expectedMac:mac];
        if (decryptedBody) {
            [self handleDecryptedMuxRPCData:decryptedBody];
        } else {
            NSLog(@"[Client] Failed to decrypt BoxStream body");
        }
        
        // Loop back to next header
        [self receiveBoxStreamHeader];
    });
}

- (void)handleDecryptedMuxRPCData:(NSData *)data {
    [self.rpcBuffer appendData:data];
    
    while (self.rpcBuffer.length >= 9) {
        SSBMuxRPCFlags flags;
        int32_t reqNum;
        uint32_t bodyLen = [SSBMuxRPCMessage parseHeader:self.rpcBuffer outFlags:&flags outRequestNumber:&reqNum];
        
        if (self.rpcBuffer.length < 9 + bodyLen) {
            // Wait for more data
            return;
        }
        
        NSData *rpcBody = [self.rpcBuffer subdataWithRange:NSMakeRange(9, bodyLen)];
        NSLog(@"[Client] Received MuxRPC Message: Flags=%02x, Req=%d, BodyLen=%u", flags, reqNum, bodyLen);
        
        id responseObject = nil;
        NSString *bodyStr = nil;
        if (flags & SSBMuxRPCFlagTypeJSON || flags & SSBMuxRPCFlagTypeString) {
            bodyStr = [[NSString alloc] initWithData:rpcBody encoding:NSUTF8StringEncoding];
            if (flags & SSBMuxRPCFlagTypeJSON) {
                NSError *jsonErr;
                responseObject = [NSJSONSerialization JSONObjectWithData:rpcBody options:NSJSONReadingAllowFragments error:&jsonErr];
                if (jsonErr) {
                    NSLog(@"[Client] JSON Parse Error: %@ for body: %@", jsonErr, bodyStr);
                    responseObject = bodyStr;
                }
            } else {
                responseObject = bodyStr;
            }
        } else {
            responseObject = rpcBody;
        }
        
        NSLog(@"[Client] MuxRPC Body Decoded: %@", responseObject);
        
        BOOL isEndOrErr = (flags & SSBMuxRPCFlagEndErr) != 0;
        NSError *rpcError = nil;
        
        if (isEndOrErr) {
            if ([responseObject isKindOfClass:[NSDictionary class]] && [(NSDictionary *)responseObject count] > 0) {
                rpcError = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{NSLocalizedDescriptionKey: [responseObject description]}];
            } else if ([responseObject isKindOfClass:[NSString class]] && ![responseObject isEqualToString:@"true"]) {
                rpcError = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{NSLocalizedDescriptionKey: responseObject}];
            }
        }
        
        if (reqNum < 0) {
            int32_t targetReqNum = -reqNum;
            SSBRPCCallState *state = self.pendingRequests[@(targetReqNum)];
            
            if (state && state.callback) {
                SSBRPCCallback cb = state.callback;
                dispatch_async(dispatch_get_main_queue(), ^{
                    cb(responseObject, isEndOrErr, rpcError);
                });
                
                BOOL isStream = [state.type isEqualToString:@"source"] || [state.type isEqualToString:@"sink"] || [state.type isEqualToString:@"duplex"];
                if (!isStream || isEndOrErr) {
                    [self.pendingRequests removeObjectForKey:@(targetReqNum)];
                }
            } else {
                NSLog(@"[Client] No pending request for response ID %d", targetReqNum);
            }
        } else {
            // Unsolicited or server-initiated request
            NSLog(@"[Client] Server-initiated request received: Req=%d", reqNum);
            // TODO: Handle manifest, whoami, etc if we want to support being a full peer.
        }
        
        // Advance buffer
        [self.rpcBuffer replaceBytesInRange:NSMakeRange(0, 9 + bodyLen) withBytes:NULL length:0];
    }
}

- (int32_t)sendRPCRequest:(NSArray<NSString *> *)name
                     args:(NSArray *)args
                     type:(NSString *)type
               completion:(SSBRPCCallback)completion {
    if (!self.isConnected) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, YES, [NSError errorWithDomain:@"SSB" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]);
            });
        }
        return -1;
    }
    
    int32_t reqID = self.nextRequestID++;
    if (completion) {
        SSBRPCCallState *state = [[SSBRPCCallState alloc] init];
        state.type = type ?: @"async";
        state.callback = completion;
        self.pendingRequests[@(reqID)] = state;
    }
    
    NSDictionary *reqDict = @{
        @"name": name ?: @[],
        @"type": type ?: @"async",
        @"args": args ?: @[]
    };
    
    SSBMuxRPCFlags rpcFlags = SSBMuxRPCFlagTypeJSON;
    BOOL isStream = [type isEqualToString:@"source"] || [type isEqualToString:@"sink"] || [type isEqualToString:@"duplex"];
    if (isStream) {
        rpcFlags |= SSBMuxRPCFlagStream;
    }
    
    [self sendRawRPCRequest:(id)reqDict requestID:reqID flags:rpcFlags];
    return reqID;
}

- (void)sendRawRPCRequest:(id)payload requestID:(int32_t)reqNum flags:(SSBMuxRPCFlags)flags {
    if (!self.isConnected) return;
    
    NSError *error;
    NSData *jsonData = nil;
    if ([payload isKindOfClass:[NSData class]]) {
        jsonData = payload;
    } else {
        jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    }
    if (!jsonData) return;
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:jsonData];
    NSData *cleartext = [msg serialize];
    NSLog(@"[Client] Outgoing RPC Req=%d, Cleartext Length=%lu", reqNum, (unsigned long)cleartext.length);
    NSData *ciphertext = [self.boxStream encryptPayload:cleartext];
    
    if (ciphertext) {
        dispatch_data_t out_data = dispatch_data_create(ciphertext.bytes, ciphertext.length, self.clientQueue, ^{
            [ciphertext self];
        });
        nw_connection_send(self.connection, out_data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t _Nullable error) {
            if (error) NSLog(@"[Client] RPC send failed");
        });
    }
}

- (void)ping {
    if (!self.isConnected) return;
    NSLog(@"[Client] Sending tunnel.ping");
    
    [self sendRPCRequest:@[@"tunnel", @"ping"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[Client] Ping failed: %@", error);
            return;
        }
        NSLog(@"[Client] Ping response: %@", response);
        if ([self.delegate respondsToSelector:@selector(roomClientDidPingSuccessfully:)]) {
            [self.delegate roomClientDidPingSuccessfully:self];
        }
    }];
}

- (void)announce {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Sending tunnel.announce");
    [self sendRPCRequest:@[@"tunnel", @"announce"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "tunnel.announce failed: %{public}@", error.localizedDescription);
        } else {
            os_log_info(ssb_room_log, "tunnel.announce success: %@", response);
        }
    }];
}

- (void)subscribeToEndpoints {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Subscribing to tunnel.endpoints");
    
    [self sendRPCRequest:@[@"tunnel", @"endpoints"] args:@[] type:@"source" completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "tunnel.endpoints error: %{public}@", error.localizedDescription);
            return;
        }
        
        if ([response isKindOfClass:[NSArray class]]) {
            os_log_info(ssb_room_log, "tunnel.endpoints updated: %lu members", (unsigned long)[(NSArray *)response count]);
            if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateEndpoints:)]) {
                [self.delegate roomClient:self didUpdateEndpoints:response];
            }
        }
        
        if (isEndOrError) {
            os_log_info(ssb_room_log, "tunnel.endpoints stream closed");
        }
    }];
}

- (void)connectToPeer:(NSString *)targetPeerId {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Initiating tunnel.connect to %{public}@", targetPeerId);
    
    // Generate muxrpc JSON: [ "tunnel", "connect" ] with target as 'duplex'
    // Starts duplex stream copy.
    
    if ([self.delegate respondsToSelector:@selector(roomClient:didEstablishTunnelWithPeer:)]) {
        [self.delegate roomClient:self didEstablishTunnelWithPeer:targetPeerId];
    }
}

- (void)disconnect {
    os_log_info(ssb_room_log, "Disconnecting from room");
    self.autoReconnect = NO;
    self.isConnected = NO;
    if (self.connection) {
        nw_connection_cancel(self.connection);
        self.connection = nil;
    }
}

@end
