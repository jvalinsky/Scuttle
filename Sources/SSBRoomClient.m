#import "SSBRoomClient.h"
#import <os/log.h>

#import <Network/Network.h>
#import "SSBFramer.h"
#import "SSBConnectionFSM.h"
#import "SSBSecretHandshake.h"
#import "SSBBoxStream.h"
#import "SSBMuxRPC.h"
#import "tweetnacl.h"
#import "SSBFeedStore.h"
#import "SSBMessageCodec.h"

static os_log_t ssb_room_log;

@interface SSBRoomClient () <SSBConnectionFSMDelegate>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *serverPubKey;
@property (nonatomic, strong) NSData *localIdentitySecret;
@property (nonatomic, strong) NSString *inviteToken;
@property (nonatomic, assign) BOOL usedHTTPInvite;
@property (nonatomic, readwrite) BOOL isConnected;
@end

@interface SSBTunnelState : NSObject
@property (nonatomic, strong) SSBSecretHandshake *shs;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, strong) NSString *peerId;
@property (nonatomic, assign) int32_t reqID;
@property (nonatomic, assign) BOOL isEstablished;
@end

@implementation SSBTunnelState
@end

@interface SSBRoomClient () <SSBConnectionFSMDelegate>
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) SSBConnectionFSM *fsm;
@property (nonatomic, strong) SSBSecretHandshake *shs;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSMutableData *rpcBuffer;
@property (nonatomic, strong) NSDictionary *serverManifest;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallState *> *pendingRequests;
@property (nonatomic, assign) int32_t nextRequestID;
@property (nonatomic, strong) NSMutableArray<NSString *> *attendantsList;
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, readwrite, nullable) NSArray<NSString *> *roomFeatures;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBTunnelState *> *activeTunnels;
@end

@implementation SSBRPCCallState
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
        
        if (localIdentitySecret) {
            _localIdentitySecret = localIdentitySecret;
        } else {
            // Load or generate stable identity
            NSData *saved = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
            if (saved) {
                _localIdentitySecret = saved;
            } else {
                unsigned char pk[32];
                unsigned char sk[64];
                crypto_sign_keypair(pk, sk);
                _localIdentitySecret = [NSData dataWithBytes:sk length:64];
                [[NSUserDefaults standardUserDefaults] setObject:_localIdentitySecret forKey:@"SSBLocalIdentity"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
        
        _isConnected = NO;
        _clientQueue = dispatch_queue_create("com.ssbc.room.client", DISPATCH_QUEUE_SERIAL);
        _rpcBuffer = [NSMutableData data];
        _pendingRequests = [NSMutableDictionary dictionary];
        _nextRequestID = 1;
        _attendantsList = [NSMutableArray array];
        _feedStore = [SSBFeedStore sharedStore];
        _activeTunnels = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithConfig:(RoomConfig *)config 
                 localIdentity:(NSData *)localIdentitySecret {
    self = [self initWithHost:config.host port:(uint16_t)config.port serverPubKey:config.serverPubKey localIdentity:localIdentitySecret];
    if (self) {
        _inviteToken = config.inviteToken;
        _usedHTTPInvite = config.usedHTTPInvite;
        
        // Validate identity consistency for HTTP invites (SIP 5)
        if (config.usedHTTPInvite && config.httpInviteClaimIdentity) {
            // Extract the SSB ID from the localIdentitySecret
            NSData *pkData = [self.localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
            NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
            
            // Check if it matches the identity used for HTTP claim
            if (![myId isEqualToString:config.httpInviteClaimIdentity]) {
                os_log_error(ssb_room_log, 
                    "WARNING: HTTP invite identity mismatch! HTTP claim used '%{public}@' but SSB connection will use '%{public}@'. "
                    "Per SIP 5, the room server will reject this connection as unauthorized. "
                    "The same identity MUST be used for both the HTTP POST claim and the SSB connection.",
                    config.httpInviteClaimIdentity, myId);
                
                // Also assert in debug builds to catch this during development
                NSAssert(NO, @"HTTP invite identity mismatch: claim identity '%@' != connection identity '%@'", 
                         config.httpInviteClaimIdentity, myId);
            }
        }
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
            [self log:[NSString stringWithFormat:@"TCP connected to %@. Initiating SHS Handshake.", self.host]];
            // Since we are likely on clientQueue, just call directly or ensure queue
            dispatch_async(self.clientQueue, ^{
                [self initiateHandshake];
            });
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            [self log:[NSString stringWithFormat:@"NW Connection state: %d", state]];
            
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
    
    // Start session overhead calls
    [self startMuxRPCSession];
    
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
        [self log:[NSString stringWithFormat:@"Received MuxRPC: flags=0x%02x req=%d len=%u", flags, reqNum, bodyLen]];
        
        id responseObject = nil;
        NSString *bodyStr = nil;
        if (flags & SSBMuxRPCFlagTypeJSON || flags & SSBMuxRPCFlagTypeString) {
            bodyStr = [[NSString alloc] initWithData:rpcBody encoding:NSUTF8StringEncoding];
            if (flags & SSBMuxRPCFlagTypeJSON) {
                NSError *jsonErr;
                responseObject = [NSJSONSerialization JSONObjectWithData:rpcBody options:NSJSONReadingAllowFragments error:&jsonErr];
                if (jsonErr) {
                    [self log:[NSString stringWithFormat:@"JSON Parse Error: %@ for body: %@", jsonErr, bodyStr]];
                    responseObject = bodyStr;
                }
            } else {
                responseObject = bodyStr;
            }
        } else {
            responseObject = rpcBody;
        }
        
        [self log:[NSString stringWithFormat:@"MuxRPC Decoded Body: %@", responseObject]];
        
        BOOL isEndOrErr = (flags & SSBMuxRPCFlagEndErr) != 0;
        NSError *rpcError = nil;
        
        if (isEndOrErr) {
            // Enhanced EndErr handling per SSB Room Protocol Fixes (Task 3.1)
            // Examine response body to distinguish between successful stream termination and actual errors
            
            // Case 1: "true" string indicates successful completion
            if ([responseObject isKindOfClass:[NSString class]] && [responseObject isEqualToString:@"true"]) {
                // Success - rpcError remains nil
                rpcError = nil;
            }
            // Case 2: Dictionary with "name" and "message" fields indicates genuine error
            else if ([responseObject isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)responseObject;
                if (dict[@"name"] && dict[@"message"]) {
                    // Genuine error response
                    rpcError = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{
                        NSLocalizedDescriptionKey: dict[@"message"] ?: [dict description]
                    }];
                } else {
                    // Success object without error fields - rpcError remains nil
                    rpcError = nil;
                }
            }
            // Case 3: String containing error keywords indicates error
            else if ([responseObject isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)responseObject;
                if ([str containsString:@"Error"] || [str containsString:@"error"]) {
                    rpcError = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{NSLocalizedDescriptionKey: str}];
                } else {
                    // Non-error string - rpcError remains nil
                    rpcError = nil;
                }
            }
            // Case 4: Other types (NSNumber, NSData, etc.) - treat as success
            else {
                rpcError = nil;
            }
        }
        
        if (reqNum < 0) {
            int32_t targetReqNum = -reqNum;
            SSBRPCCallState *state = self.pendingRequests[@(targetReqNum)];
            
            if (state && state.callback) {
                [self log:[NSString stringWithFormat:@"Dispatching response for req %d (EndErr=%d)", targetReqNum, isEndOrErr]];
                SSBRPCCallback cb = state.callback;
                dispatch_async(dispatch_get_main_queue(), ^{
                    cb(responseObject, isEndOrErr, rpcError);
                });
                
                // CRITICAL FIX: Keep the callback until the server explicitly ends the request (EndErr)
                // This handles cases where the server sends the body and End signal in separate packets.
                if (isEndOrErr) {
                    [self.pendingRequests removeObjectForKey:@(targetReqNum)];
                }
            } else {
                [self log:[NSString stringWithFormat:@"No pending request found for response ID %d (maybe already completed?)", targetReqNum]];
            }
        } else {
            // Unsolicited or server-initiated request
            [self log:[NSString stringWithFormat:@"Server-initiated request: req=%d", reqNum]];
            [self handleServerInitiatedRequest:responseObject requestID:reqNum flags:flags];
        }
        
        // Advance buffer
        [self.rpcBuffer replaceBytesInRange:NSMakeRange(0, 9 + bodyLen) withBytes:NULL length:0];
    }
}

- (void)handleServerInitiatedRequest:(id)payload requestID:(int32_t)reqNum flags:(SSBMuxRPCFlags)flags {
    BOOL isEndErr = (flags & SSBMuxRPCFlagEndErr) != 0;
    
    // If it's just an End/Error signal for a request the server started, we don't need to respond or log an error
    if (isEndErr && reqNum != 0) {
        [self log:[NSString stringWithFormat:@"Server closed request %d", reqNum]];
        return;
    }

    if (![payload isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *req = (NSDictionary *)payload;
    id nameObj = req[@"name"];
    
    BOOL matchesManifest = NO;
    BOOL matchesWhoami = NO;
    
    if ([nameObj isKindOfClass:[NSString class]]) {
        NSString *name = (NSString *)nameObj;
        matchesManifest = [name isEqualToString:@"manifest"];
        matchesWhoami = [name isEqualToString:@"whoami"];
    } else if ([nameObj isKindOfClass:[NSArray class]]) {
        NSArray *nameParts = (NSArray *)nameObj;
        matchesManifest = [nameParts containsObject:@"manifest"];
        matchesWhoami = [nameParts containsObject:@"whoami"];
    }

    if (matchesManifest) {
        [self log:@"Responding to server 'manifest' request"];
        // Return a more robust manifest to satisfy servers
        NSDictionary *manifest = @{
            @"manifest": @"sync",
            @"whoami": @"sync",
            @"createHistoryStream": @"source",
            @"tunnel": @{
                @"announce": @"async",
                @"endpoints": @"source",
                @"ping": @"async"
            },
            @"room": @{
                @"listAliases": @"async"
            }
        };
        [self sendRawRPCRequest:manifest requestID:-reqNum flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
    } else if (matchesWhoami) {
        [self log:@"Responding to server 'whoami' request"];
        NSData *pkData = [self.localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
        NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        [self sendRawRPCRequest:@{@"id": myId} requestID:-reqNum flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
    } else if ([nameObj isKindOfClass:[NSArray class]] && [(NSArray *)nameObj containsObject:@"tunnel"] && [(NSArray *)nameObj containsObject:@"connect"]) {
        [self log:@"Received incoming tunnel.connect request"];
        if ([self.delegate respondsToSelector:@selector(roomClient:didEstablishTunnelWithPeer:)]) {
            NSString *peerId = req[@"args"] ? [req[@"args"] firstObject][@"origin"] : nil;
            if (peerId) {
                [self.delegate roomClient:self didEstablishTunnelWithPeer:peerId];
            }
        }
    } else if (([nameObj isKindOfClass:[NSString class]] && [nameObj isEqualToString:@"createHistoryStream"]) ||
               ([nameObj isKindOfClass:[NSArray class]] && [(NSArray *)nameObj containsObject:@"createHistoryStream"])) {
        [self log:@"Serving createHistoryStream request"];
        NSArray *args = req[@"args"];
        if ([args isKindOfClass:[NSArray class]] && args.count > 0 && [args[0] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *opts = args[0];
            NSString *feedId = opts[@"id"];
            NSInteger startSeq = opts[@"seq"] ? [opts[@"seq"] integerValue] : 1;
            NSInteger limit = opts[@"limit"] ? [opts[@"limit"] integerValue] : 100;
            
            if (feedId) {
                NSArray<SSBMessage *> *messages = [self.feedStore messagesForAuthor:feedId fromSequence:startSeq limit:limit];
                for (SSBMessage *msg in messages) {
                    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:msg.valueJSON options:0 error:nil];
                    if (value) {
                        NSDictionary *envelope = @{@"key": msg.key, @"value": value};
                        [self sendRawRPCRequest:envelope requestID:-reqNum flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream];
                    }
                }
            }
        }
        // Send end-of-stream
        [self sendRawRPCRequest:@YES requestID:-reqNum flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr | SSBMuxRPCFlagStream];
    } else {
        [self log:[NSString stringWithFormat:@"Unhandled server request: %@", nameObj]];
        // Send an error response to avoid hanging if the server expects a reply
        if (reqNum != 0 && !isEndErr) {
            [self sendRawRPCRequest:@{@"name": @"UnimplementedError", @"message": @"Method not supported"} requestID:-reqNum flags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagEndErr];
        }
    }
}

- (void)log:(NSString *)message {
    os_log_info(ssb_room_log, "%{public}@", message);
    if ([self.delegate respondsToSelector:@selector(roomClient:didLogMessage:)]) {
        [self.delegate roomClient:self didLogMessage:message];
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
    
    [self log:[NSString stringWithFormat:@"Sending MuxRPC: flags=0x%02x req=%d body=%@", flags, reqNum, payload]];
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:jsonData];
    NSData *cleartext = [msg serialize];
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

- (void)startMuxRPCSession {
    [self log:@"Warming up MuxRPC session..."];
    [self sendRPCRequest:@[@"manifest"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEnd, NSError * _Nullable error) {
        if (!error && [response isKindOfClass:[NSDictionary class]]) {
            self.serverManifest = (NSDictionary *)response;
            [self log:[NSString stringWithFormat:@"Server Manifest: %@", response]];
        }
    }];
    [self sendRPCRequest:@[@"whoami"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEnd, NSError * _Nullable error) {
        if (!error) [self log:[NSString stringWithFormat:@"Server Identity: %@", response]];
    }];
    
    // Room version detection (SIP 7 - Rooms 2)
    // Call room.metadata() to detect Room v2 capabilities
    [self sendRPCRequest:@[@"room", @"metadata"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEnd, NSError * _Nullable error) {
        if (!error && [response isKindOfClass:[NSDictionary class]]) {
            NSDictionary *metadata = (NSDictionary *)response;
            NSArray *features = metadata[@"features"];
            
            if ([features isKindOfClass:[NSArray class]]) {
                self.roomFeatures = features;
                [self log:[NSString stringWithFormat:@"Room features detected: %@", features]];
                
                // Branch behavior based on detected features
                // e.g., skip tunnel.announce if "httpInvite" is present
                BOOL hasHttpInvite = [features containsObject:@"httpInvite"];
                if (hasHttpInvite) {
                    [self log:@"Room supports HTTP invites (Room v2), skipping tunnel.announce"];
                }
            }
        } else {
            // Room v1 or room.metadata not supported
            [self log:@"Room v1 detected (no room.metadata support)"];
            self.roomFeatures = nil;
        }
    }];
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
    
    // Skip tunnel.announce if this connection was established via HTTP invite (SIP 5)
    // and the room supports the "httpInvite" feature (Room v2)
    if (self.usedHTTPInvite && [self.roomFeatures containsObject:@"httpInvite"]) {
        os_log_info(ssb_room_log, "Skipping tunnel.announce: HTTP invite already claimed (SIP 5) and room supports httpInvite");
        return;
    }
    
    os_log_info(ssb_room_log, "Sending tunnel.announce");
    
    // We use 'async' as a safe default, though some manifests mark it as 'sync'.
    // MuxRPC 'async' can handle 'sync' responses fine in this implementation.
    [self sendRPCRequest:@[@"tunnel", @"announce"] args:@[] type:@"async" completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "tunnel.announce failed/unsupported: %{public}@", error.localizedDescription);
        } else {
            os_log_info(ssb_room_log, "tunnel.announce success: %@", response);
        }
    }];
}

- (void)handleAttendantsResponse:(id)response {
    // Handle both legacy array and new Room v2 events
    if ([response isKindOfClass:[NSArray class]]) {
        [self.attendantsList removeAllObjects];
        [self.attendantsList addObjectsFromArray:(NSArray *)response];
        
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateEndpoints:)]) {
            [self.delegate roomClient:self didUpdateEndpoints:[self.attendantsList copy]];
        }
    } else if ([response isKindOfClass:[NSDictionary class]]) {
        NSDictionary *event = (NSDictionary *)response;
        NSString *type = event[@"type"];
        
        if ([type isEqualToString:@"state"]) {
            NSArray *ids = event[@"ids"];
            if ([ids isKindOfClass:[NSArray class]]) {
                [self.attendantsList removeAllObjects];
                [self.attendantsList addObjectsFromArray:ids];
            }
        } else if ([type isEqualToString:@"joined"]) {
            NSString *peerId = event[@"id"];
            if (peerId && ![self.attendantsList containsObject:peerId]) {
                [self.attendantsList addObject:peerId];
            }
        } else if ([type isEqualToString:@"left"]) {
            NSString *peerId = event[@"id"];
            if (peerId) {
                [self.attendantsList removeObject:peerId];
            }
        }
        
        if ([self.delegate respondsToSelector:@selector(roomClient:didUpdateEndpoints:)]) {
            [self.delegate roomClient:self didUpdateEndpoints:[self.attendantsList copy]];
        }
    }
}

- (void)subscribeToEndpoints {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Subscribing to discovery streams...");
    
    SSBRPCCallback endpointHandler = ^(id _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "Discovery error: %{public}@", error.localizedDescription);
            return;
        }
        
        [self handleAttendantsResponse:response];
    };

    // Try standard tunnel.endpoints
    [self sendRPCRequest:@[@"tunnel", @"endpoints"] args:@[] type:@"source" completion:endpointHandler];
    
    // Fallback/Parallel: Try room.attendants (common in multiple manifest variants)
    [self sendRPCRequest:@[@"room", @"attendants"] args:@[] type:@"source" completion:endpointHandler];
}

- (void)connectToPeer:(NSString *)targetPeerId {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Initiating tunneled connection to %{public}@", targetPeerId);
    
    if (self.activeTunnels[targetPeerId]) {
        [self log:[NSString stringWithFormat:@"Tunnel to %@ already in progress", targetPeerId]];
        return;
    }

    NSData *remotePubKey = [self publicKeyFromId:targetPeerId];
    if (!remotePubKey) {
        os_log_error(ssb_room_log, "Invalid peer ID: %@", targetPeerId);
        return;
    }

    SSBTunnelState *tunnel = [[SSBTunnelState alloc] init];
    tunnel.peerId = targetPeerId;
    tunnel.shs = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.localIdentitySecret remotePublicKey:remotePubKey];
    
    if (!self.activeTunnels) {
        self.activeTunnels = [NSMutableDictionary dictionary];
    }
    self.activeTunnels[targetPeerId] = tunnel;

    NSString *portalId = [self localPublicID];
    NSDictionary *args = @{
        @"portal": portalId,
        @"target": targetPeerId
    };
    
    // We initiate a duplex RPC call for the tunnel
    tunnel.reqID = [self sendRPCRequest:@[@"tunnel", @"connect"] args:@[ args ] type:@"duplex" completion:^(id _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            os_log_error(ssb_room_log, "tunnel.connect RPC error for %@: %@", targetPeerId, error.localizedDescription);
            [self.activeTunnels removeObjectForKey:targetPeerId];
            return;
        }
        
        if (isEndOrError) {
            os_log_info(ssb_room_log, "Tunnel stream to %@ closed", targetPeerId);
            [self.activeTunnels removeObjectForKey:targetPeerId];
            return;
        }
        
        // Handle incoming data from the duplex stream
        if ([response isKindOfClass:[NSData class]]) {
            [self handleIncomingTunnelStream:response fromPeer:targetPeerId];
        } else {
            [self log:[NSString stringWithFormat:@"Unexpected tunnel response type from %@: %@", targetPeerId, [response class]]];
        }
    }];

    // Task 1.6: Initiate inner Secret Handshake over the tunnel stream
    NSData *hello = [tunnel.shs createHello];
    if (hello) {
        [self log:[NSString stringWithFormat:@"Sending inner SHS Hello to %@", targetPeerId]];
        [self sendRawRPCRequest:hello requestID:tunnel.reqID flags:SSBMuxRPCFlagTypeBinary | SSBMuxRPCFlagStream];
    }
}

- (void)handleIncomingTunnelStream:(NSData *)data fromPeer:(NSString *)peerId {
    SSBTunnelState *tunnel = self.activeTunnels[peerId];
    if (!tunnel) {
        [self log:[NSString stringWithFormat:@"Received tunneled data for unknown peer: %@", peerId]];
        return;
    }

    if (tunnel.isEstablished) {
        // Full duplex Box Stream is ready - Task 3.5
        // In a full implementation, we would feed this to an inner MuxRPC parser.
        // For now, we log and notify the delegate.
        [self log:[NSString stringWithFormat:@"Received encrypted tunneled data from %@ (%lu bytes)", peerId, (unsigned long)data.length]];
        return;
    }

    // Inner Handshake Orchestration
    if (data.length == 64) {
        // Received Server Hello
        if ([tunnel.shs processHello:data]) {
            NSData *auth = [tunnel.shs createAuth];
            if (auth) {
                [self log:[NSString stringWithFormat:@"Sending inner SHS Auth to %@", peerId]];
                [self sendRawRPCRequest:auth requestID:tunnel.reqID flags:SSBMuxRPCFlagTypeBinary | SSBMuxRPCFlagStream];
            }
        } else {
            [self log:@"Failed to process inner Server Hello"];
        }
    } else if (data.length == 80) {
        // Received Server Accept
        if ([tunnel.shs processAccept:data]) {
            [self log:[NSString stringWithFormat:@"Inner SHS complete for tunnel to %@", peerId]];
            
            // Initialize Box Stream over tunnel
            tunnel.boxStream = [[SSBBoxStream alloc] initWithClientToServerKey:tunnel.shs.clientToServerKey
                                                             serverToClientKey:tunnel.shs.serverToClientKey
                                                           clientToServerNonce:tunnel.shs.clientToServerNonce
                                                           serverToClientNonce:tunnel.shs.serverToClientNonce];
            tunnel.isEstablished = YES;
            
            // Notify delegate that the secure tunnel is ready
            if ([self.delegate respondsToSelector:@selector(roomClient:didEstablishTunnelWithPeer:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate roomClient:self didEstablishTunnelWithPeer:peerId];
                });
            }
        } else {
            [self log:@"Failed to process inner Server Accept"];
        }
    } else {
        [self log:[NSString stringWithFormat:@"Received unexpected handshake data length (%lu) from %@", (unsigned long)data.length, peerId]];
    }
}

- (nullable SSBMessage *)publishPostWithText:(NSString *)text error:(NSError **)error {
    NSDictionary *content = [SSBMessageCodec postContentWithText:text];
    return [self publishLocalMessageWithContent:content error:error];
}

- (nullable SSBMessage *)publishLocalContact:(NSString *)targetPubKey following:(BOOL)following error:(NSError **)error {
    // Self-follow validation
    NSString *myId = [self localPublicID];
    if ([targetPubKey isEqualToString:myId]) {
        if (error) *error = [NSError errorWithDomain:@"SSB" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Cannot follow yourself"}];
        return nil;
    }
    
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:targetPubKey following:following];
    SSBMessage *msg = [self publishLocalMessageWithContent:content error:error];
    if (msg) {
        [self.feedStore setFollowing:following forAuthor:targetPubKey atSequence:msg.sequence];
    }
    return msg;
}

- (nullable SSBMessage *)publishAboutWithName:(nullable NSString *)name description:(nullable NSString *)desc error:(NSError **)error {
    NSString *myId = [self localPublicID];
    NSDictionary *content = [SSBMessageCodec aboutContentForFeed:myId name:name description:desc];
    return [self publishLocalMessageWithContent:content error:error];
}

- (nullable SSBMessage *)publishLocalMessageWithContent:(NSDictionary *)content error:(NSError **)error {
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
        if (error) *error = [NSError errorWithDomain:@"SSB" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign message"}];
        return nil;
    }
    
    NSString *msgKey = [SSBMessageCodec computeMessageKey:signedValue];
    if (!msgKey) {
        if (error) *error = [NSError errorWithDomain:@"SSB" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute message key"}];
        return nil;
    }
    
    NSData *valueJSON = [SSBMessageCodec encodeLegacyValue:signedValue includeSignature:YES];
    
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = msgKey;
    msg.author = myId;
    msg.sequence = nextSeq;
    msg.previousKey = prevKey;
    msg.claimedTimestamp = [signedValue[@"timestamp"] longLongValue];
    msg.receivedAt = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    msg.contentType = content[@"type"];
    msg.valueJSON = valueJSON;
    msg.content = content;
    
    if (![self.feedStore appendMessage:msg error:error]) {
        return nil;
    }
    
    [self log:[NSString stringWithFormat:@"Published %@ message (seq %ld): %@", content[@"type"], (long)nextSeq, msgKey]];
    return msg;
}

- (void)replicateFromPeer:(NSString *)peerID viaRoom:(NSString *)roomHost {
    [self log:[NSString stringWithFormat:@"Starting replication from %@", peerID]];
    
    // Request the peer's own feed
    [self replicateFeed:peerID fromPeer:peerID];
    
    // Also replicate feeds we follow
    NSArray *followed = [self.feedStore followedAuthors];
    for (NSString *author in followed) {
        [self replicateFeed:author fromPeer:peerID];
    }
}

- (void)replicateFeed:(NSString *)feedAuthor fromPeer:(NSString *)peerID {
    SSBFeedState *state = [self.feedStore feedStateForAuthor:feedAuthor];
    NSInteger startSeq = state ? state.maxSequence + 1 : 1;
    
    NSDictionary *args = @{
        @"id": feedAuthor,
        @"seq": @(startSeq),
        @"limit": @100,
        @"live": @NO,
        @"keys": @YES,
        @"values": @YES
    };
    
    [self log:[NSString stringWithFormat:@"Requesting feed %@ from seq %ld", feedAuthor, (long)startSeq]];
    
    // Check if server supports createHistoryStream
    BOOL supportsHistory = self.serverManifest[@"createHistoryStream"] != nil;
    if (!supportsHistory) {
        [self log:[NSString stringWithFormat:@"Skipping replication for %@: server does not support createHistoryStream", feedAuthor]];
        return;
    }
    
    __block NSInteger replicatedCount = 0;
    
    [self sendRPCRequest:@[@"createHistoryStream"] args:@[ args ] type:@"source" completion:^(id _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"Replication error for %@: %@", feedAuthor, error.localizedDescription]];
            return;
        }
        
        if ([response isKindOfClass:[NSDictionary class]]) {
            NSDictionary *envelope = (NSDictionary *)response;
            NSString *key = envelope[@"key"];
            NSDictionary *value = envelope[@"value"];
            
            if (key && value) {
                // Verify the message signature
                if (![SSBMessageCodec verifyMessage:value]) {
                    [self log:[NSString stringWithFormat:@"Rejected invalid message: %@", key]];
                    return;
                }
                
                NSDictionary *content = value[@"content"];
                NSData *valueJSON = [SSBMessageCodec encodeLegacyValue:value includeSignature:YES];
                
                SSBMessage *msg = [[SSBMessage alloc] init];
                msg.key = key;
                msg.author = value[@"author"];
                msg.sequence = [value[@"sequence"] integerValue];
                msg.previousKey = [value[@"previous"] isEqual:[NSNull null]] ? nil : value[@"previous"];
                msg.claimedTimestamp = [value[@"timestamp"] longLongValue];
                msg.receivedAt = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
                msg.contentType = [content isKindOfClass:[NSDictionary class]] ? content[@"type"] : nil;
                msg.valueJSON = valueJSON;
                msg.content = [content isKindOfClass:[NSDictionary class]] ? content : nil;
                
                NSError *storeErr = nil;
                if ([self.feedStore appendMessage:msg error:&storeErr]) {
                    replicatedCount++;
                    
                    // If it's a contact message from our feed, update follow graph
                    if ([msg.author isEqualToString:[self localPublicID]] && [msg.contentType isEqualToString:@"contact"]) {
                        NSString *target = content[@"contact"];
                        BOOL following = [content[@"following"] boolValue];
                        if (target) {
                            [self.feedStore setFollowing:following forAuthor:target atSequence:msg.sequence];
                        }
                    }
                }
            }
        }
        
        if (isEndOrError && replicatedCount > 0) {
            [self log:[NSString stringWithFormat:@"Replicated %ld messages from %@", (long)replicatedCount, feedAuthor]];
            if ([self.delegate respondsToSelector:@selector(roomClient:didReplicateMessagesFromPeer:count:)]) {
                [self.delegate roomClient:self didReplicateMessagesFromPeer:feedAuthor count:replicatedCount];
            }
        }
    }];
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

- (void)redeemInvite:(NSString *)token completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Redeeming invite token...");
    
    // Room v1: invite.use with the token
    [self sendRPCRequest:@[@"invite", @"use"] args:@[ @{@"feed": [self localPublicID]} ] type:@"async" completion:completion];
}

- (NSString *)localPublicID {
    NSData *pkData = [self.localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
    return [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
}

- (NSData *)publicKeyFromId:(NSString *)peerId {
    if (![peerId hasPrefix:@"@"] || ![peerId hasSuffix:@".ed25519"]) {
        return nil;
    }
    
    // Extract everything between @ and .ed25519
    // @ (1 char) ... .ed25519 (8 chars)
    NSString *base64 = [peerId substringWithRange:NSMakeRange(1, peerId.length - 9)];
    
    // Scuttlebutt base64 often omits '=' padding
    if (base64.length == 43) {
        base64 = [base64 stringByAppendingString:@"="];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

- (void)listAliasesWithCompletion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Listing aliases...");
    [self sendRPCRequest:@[@"room", @"listAliases"] args:@[] type:@"async" completion:completion];
}

- (void)registerAlias:(NSString *)alias signature:(NSString *)signature completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Registering alias: %@", alias);
    [self sendRPCRequest:@[@"room", @"registerAlias"] args:@[ alias, signature ] type:@"async" completion:completion];
}

- (void)revokeAlias:(NSString *)alias completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    os_log_info(ssb_room_log, "Revoking alias: %@", alias);
    [self sendRPCRequest:@[@"room", @"revokeAlias"] args:@[ alias ] type:@"async" completion:completion];
}

- (void)publishContact:(NSString *)targetPubKey following:(BOOL)following completion:(nullable SSBRPCCallback)completion {
    NSError *error = nil;
    SSBMessage *msg = [self publishLocalContact:targetPubKey following:following error:&error];
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (msg) {
                completion(@{@"key": msg.key, @"sequence": @(msg.sequence)}, YES, nil);
            } else {
                completion(nil, YES, error ?: [NSError errorWithDomain:@"SSB" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Publish failed"}]);
            }
        });
    }
}

- (void)fetchFeedForPeer:(NSString *)peerID limit:(NSInteger)limit completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    
    NSDictionary *args = @{
        @"id": peerID,
        @"limit": @(limit),
        @"reverse": @YES,
        @"live": @NO
    };
    
    // Check for createHistoryStream support
    if (self.serverManifest && !self.serverManifest[@"createHistoryStream"]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, YES, [NSError errorWithDomain:@"SSB" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Server does not support createHistoryStream"}]);
            });
        }
        return;
    }
    
    [self sendRPCRequest:@[@"createHistoryStream"] args:@[ args ] type:@"source" completion:completion];
}

- (void)fetchProfileForPeer:(NSString *)peerID completion:(nullable SSBRPCCallback)completion {
    if (!self.isConnected) return;
    
    // First try room.metadata if available (specific to room plugins)
    [self sendRPCRequest:@[@"room", @"metadata"] args:@[ peerID ] type:@"async" completion:^(id  _Nullable response, BOOL isEnd, NSError * _Nullable error) {
        if (!error && response && ![response isEqual:[NSNull null]]) {
            if (completion) completion(response, isEnd, error);
        } else {
            // Fallback: try to get about messages from the feed
            NSDictionary *args = @{
                @"id": peerID,
                @"limit": @1,
                @"reverse": @YES,
                @"type": @"about"
            };
            // This fallback might not work on all room servers, but it's a standard SSB call
            if (self.serverManifest && !self.serverManifest[@"createHistoryStream"]) {
                if (completion) completion(nil, YES, [NSError errorWithDomain:@"SSB" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Server does not support createHistoryStream"}]);
                return;
            }
            [self sendRPCRequest:@[@"createHistoryStream"] args:@[ args ] type:@"source" completion:completion];
        }
    }];
}

@end
