#import "SSBSecurityFramer.h"
#import "SSBSecretHandshake.h"
#import "SSBBoxStream.h"
#import "SSBLogCompat.h"
#import "SSBLogger.h"

static const char *kSSBSecurityFramerName = "SSBSecurity";
static const char *kSSBSecurityLocalKey = "LocalKey";
static const char *kSSBSecurityRemoteKey = "RemoteKey";
static const char *kSSBSecurityAsClient = "AsClient";
static os_log_t ssb_sec_log;

typedef NS_ENUM(NSInteger, SSBSecurityState) {
    SSBSecurityStateHandshakeHelloWait, // New state for server
    SSBSecurityStateHandshakeHelloSent,
    SSBSecurityStateHandshakeAuthWait,  // New state for server
    SSBSecurityStateHandshakeAcceptWait,
    SSBSecurityStateBoxHeader,
    SSBSecurityStateBoxBody
};

@interface SSBLogger (SSBSecurityTrace)
+ (void)ssb_emitProtocolTraceEvent:(NSDictionary<NSString *, id> *)event;
@end

static NSString *SSBSecurityStateName(SSBSecurityState state) {
    switch (state) {
        case SSBSecurityStateHandshakeHelloWait: return @"hello.wait";
        case SSBSecurityStateHandshakeHelloSent: return @"hello.sent";
        case SSBSecurityStateHandshakeAuthWait: return @"auth.wait";
        case SSBSecurityStateHandshakeAcceptWait: return @"accept.wait";
        case SSBSecurityStateBoxHeader: return @"box.header";
        case SSBSecurityStateBoxBody: return @"box.body";
    }
    return @"unknown";
}

static NSString *SSBSecurityPeerIDFromKey(NSData *key) {
    if (key.length != 32) {
        return @"<unknown-peer>";
    }
    return [NSString stringWithFormat:@"@%@.ed25519", [key base64EncodedStringWithOptions:0]];
}

static void SSBSecurityEmitTrace(NSString *connectionID,
                                 NSString *direction,
                                 NSString *peerID,
                                 SSBSecurityState state,
                                 NSString *message,
                                 NSDictionary<NSString *, id> *extras) {
    NSMutableDictionary<NSString *, id> *event = [NSMutableDictionary dictionary];
    event[@"component"] = @"security.framer";
    event[@"connectionID"] = connectionID ?: @"security";
    event[@"direction"] = direction ?: @"internal";
    event[@"peerID"] = peerID ?: @"<unknown-peer>";
    event[@"framerState"] = SSBSecurityStateName(state);
    event[@"message"] = message ?: @"";
    if (extras.count > 0) {
        [event addEntriesFromDictionary:extras];
    }
    [SSBLogger ssb_emitProtocolTraceEvent:event];
}

@interface SSBSecurityContext : NSObject
@property (nonatomic, strong) SSBSecretHandshake *handshake;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, assign) SSBSecurityState state;
@property (nonatomic, strong) NSMutableArray *outputBuffer;
@property (nonatomic, assign) size_t pendingBodyLen;
@property (nonatomic, strong) NSData *pendingBodyMac;
@property (nonatomic, copy) NSString *connectionID;
@property (nonatomic, copy) NSString *peerID;
@end

@implementation SSBSecurityContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _outputBuffer = [NSMutableArray array];
    }
    return self;
}
@end

@implementation SSBSecurityFramer

+ (void)flushBufferedOutputForFramer:(nw_framer_t)framer context:(SSBSecurityContext *)context {
    if (context.outputBuffer.count == 0 || !context.boxStream) {
        return;
    }

    NSArray *bufferedItems = [context.outputBuffer copy];
    [context.outputBuffer removeAllObjects];

    for (NSDictionary *item in bufferedItems) {
        NSData *data = item[@"data"];
        if (![data isKindOfClass:[NSData class]]) {
            continue;
        }

        NSData *encrypted = [context.boxStream encryptPayload:data];
        if (!encrypted) {
            SSBSecurityEmitTrace(context.connectionID,
                                 @"outbound",
                                 context.peerID,
                                 context.state,
                                 @"Failed to flush buffered outbound payload",
                                 @{ @"bodyLength": @(data.length) });
            continue;
        }

        dispatch_data_t encryptedData = dispatch_data_create(encrypted.bytes, encrypted.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_framer_write_output_data(framer, encryptedData);
        SSBSecurityEmitTrace(context.connectionID,
                             @"outbound",
                             context.peerID,
                             context.state,
                             @"Flushed buffered outbound payload",
                             @{ @"bodyLength": @(data.length),
                                @"wireLength": @(encrypted.length) });
    }
}

+ (void)initialize {
    if (self == [SSBSecurityFramer class]) {
        ssb_sec_log = os_log_create("com.scuttlebutt.network", "SecurityFramer");
    }
}

+ (nw_protocol_definition_t)createDefinition {
    static nw_protocol_definition_t definition = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definition = nw_framer_create_definition(kSSBSecurityFramerName, NW_FRAMER_CREATE_FLAGS_DEFAULT, ^nw_framer_start_result_t(nw_framer_t framer) {
            SSBSecurityContext *context = [[SSBSecurityContext alloc] init];
            
            nw_protocol_options_t options = nw_framer_copy_options(framer);
            
            NSData *localKey = nw_framer_options_copy_object_value(options, kSSBSecurityLocalKey);
            NSData *remoteKey = nw_framer_options_copy_object_value(options, kSSBSecurityRemoteKey);
            NSNumber *asClientNum = nw_framer_options_copy_object_value(options, kSSBSecurityAsClient);
            BOOL asClient = asClientNum ? [asClientNum boolValue] : YES; 
            context.connectionID = [[NSUUID UUID] UUIDString];
            context.peerID = SSBSecurityPeerIDFromKey(remoteKey);
            SSBSecurityEmitTrace(context.connectionID,
                                 asClient ? @"outbound" : @"inbound",
                                 context.peerID,
                                 context.state,
                                 @"Security framer started",
                                 @{ @"asClient": @(asClient),
                                    @"localKeyLength": @(localKey.length),
                                    @"remoteKeyLength": @(remoteKey.length) });
            
            if (!localKey || (!remoteKey && asClient)) {
                os_log_error(ssb_sec_log, "Missing keys in security framer options");
                SSBSecurityEmitTrace(context.connectionID, @"internal", context.peerID, context.state, @"Missing required key material", nil);
                return nw_framer_start_result_ready;
            }
            
            context.handshake = [[SSBSecretHandshake alloc] initWithRole:asClient
                                                           localIdentity:localKey
                                                         remotePublicKey:remoteKey];
            
            if (asClient) {
                NSData *hello = [context.handshake createHello];
                if (!hello) return nw_framer_start_result_ready;
                dispatch_data_t helloData = dispatch_data_create(hello.bytes, hello.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, helloData);
                context.state = SSBSecurityStateHandshakeHelloSent;
                SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Queued client hello", @{ @"wireLength": @(hello.length) });
            } else {
                context.state = SSBSecurityStateHandshakeHelloWait;
                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Waiting for client hello", nil);
            }
            
            nw_framer_set_input_handler(framer, ^size_t(nw_framer_t inner_framer) {
                return [self handleInput:inner_framer context:context];
            });
            
            nw_framer_set_output_handler(framer, ^(nw_framer_t inner_framer, nw_framer_message_t message, size_t message_length, bool is_complete) {
                [self handleOutput:inner_framer message:message messageLength:message_length context:context];
            });
            
            return nw_framer_start_result_will_mark_ready;
        });
    });
    return definition;
}

+ (size_t)handleInput:(nw_framer_t)framer context:(SSBSecurityContext *)context {
    os_log_debug(ssb_sec_log, "handleInput called, state=%ld", (long)context.state);
    switch (context.state) {
        case SSBSecurityStateHandshakeHelloWait: {
            size_t req = 64; // Expect Client Hello
            __block BOOL success = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    success = [context.handshake processHello:[NSData dataWithBytes:buffer length:req]];
                    return req;
                }
                return 0;
            });
            if (success) {
                os_log_info(ssb_sec_log, "Client Hello processed. Sending Server Hello.");
                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Processed client hello", nil);
                NSData *hello = [context.handshake createHello];
                dispatch_data_t helloData = dispatch_data_create(hello.bytes, hello.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, helloData);
                context.state = SSBSecurityStateHandshakeAuthWait;
                SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Queued server hello", @{ @"wireLength": @(hello.length) });
                return 0;
            }
            return req;
        }
        case SSBSecurityStateHandshakeHelloSent: {
            size_t req = 64; // Expect Server Hello
            __block BOOL success = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    success = [context.handshake processHello:[NSData dataWithBytes:buffer length:req]];
                    return req;
                }
                return 0;
            });
            if (success) {
                os_log_info(ssb_sec_log, "Server Hello processed. Sending Auth.");
                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Processed server hello", nil);
                NSData *auth = [context.handshake createAuth];
                dispatch_data_t authData = dispatch_data_create(auth.bytes, auth.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, authData);
                context.state = SSBSecurityStateHandshakeAcceptWait;
                SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Queued client auth", @{ @"wireLength": @(auth.length) });
                return 0;
            }
            return req;
        }
        case SSBSecurityStateHandshakeAuthWait: {
            size_t req = 112; // Expect Client Auth
            __block BOOL success = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    success = [context.handshake processAuth:[NSData dataWithBytes:buffer length:req]];
                    return req;
                }
                return 0;
            });
            if (success) {
                os_log_info(ssb_sec_log, "Client Auth processed. Sending Server Accept.");
                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Processed client auth", nil);
                NSData *accept = [context.handshake createAccept];
                dispatch_data_t acceptData = dispatch_data_create(accept.bytes, accept.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, acceptData);
                
                context.boxStream = [[SSBBoxStream alloc] initWithClientToServerKey:context.handshake.clientToServerKey
                                                                  serverToClientKey:context.handshake.serverToClientKey
                                                                clientToServerNonce:context.handshake.clientToServerNonce
                                                                serverToClientNonce:context.handshake.serverToClientNonce];
                context.boxStream.isClient = context.handshake.isClient;
                context.state = SSBSecurityStateBoxHeader;
                nw_framer_mark_ready(framer);
                SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Queued server accept and marked ready", @{ @"wireLength": @(accept.length) });
                [self flushBufferedOutputForFramer:framer context:context];
                return 0;
            }
            return req;
        }
        case SSBSecurityStateHandshakeAcceptWait: {
            size_t req = 80; // Expect Server Accept
            __block BOOL success = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    success = [context.handshake processAccept:[NSData dataWithBytes:buffer length:req]];
                    return req;
                }
                return 0;
            });
            if (success) {
                os_log_info(ssb_sec_log, "Server Accept processed. Handshake COMPLETE.");
                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Processed server accept", nil);
                context.boxStream = [[SSBBoxStream alloc] initWithClientToServerKey:context.handshake.clientToServerKey
                                                                  serverToClientKey:context.handshake.serverToClientKey
                                                                clientToServerNonce:context.handshake.clientToServerNonce
                                                                serverToClientNonce:context.handshake.serverToClientNonce];
                context.boxStream.isClient = context.handshake.isClient;
                context.state = SSBSecurityStateBoxHeader;
                nw_framer_mark_ready(framer); // SHS DONE!
                SSBSecurityEmitTrace(context.connectionID, @"internal", context.peerID, context.state, @"Security handshake complete", nil);
                [self flushBufferedOutputForFramer:framer context:context];
                
                return 0;
            }
            return req;
        }
        case SSBSecurityStateBoxHeader:
        case SSBSecurityStateBoxBody: {
            while (true) {
                if (context.state == SSBSecurityStateBoxHeader) {
                    size_t headerReq = 34; // 18 byte box + 16 byte body MAC
                    __block size_t bodyLen = 0;
                    __block NSData *bodyMac = nil;
                    __block BOOL headerParsed = NO;
                    
                    size_t headerActual = nw_framer_parse_input(framer, headerReq, headerReq, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                        if (buffer_length >= headerReq) {
                            headerParsed = [context.boxStream decryptHeader:[NSData dataWithBytes:buffer length:headerReq] 
                                                                  outLength:&bodyLen 
                                                                 outBodyMac:&bodyMac];
                            if (!headerParsed) {
                                os_log_error(ssb_sec_log, "Box header decrypt FAILED");
                                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Failed to decrypt box header", nil);
                            }
                            return headerReq;
                        }
                        return 0;
                    });
                    
                    if (headerActual == 0) return headerReq;
                    
                    if (headerParsed) {
                        context.pendingBodyLen = bodyLen;
                        context.pendingBodyMac = bodyMac;
                        context.state = SSBSecurityStateBoxBody;
                        // Continue to body
                    } else {
                        return headerReq; // Failed to parse header, wait for more? No, should fail connection.
                    }
                }
                
                if (context.state == SSBSecurityStateBoxBody) {
                    size_t bodyLen = context.pendingBodyLen;
                    if (bodyLen == 0) {
                        os_log_info(ssb_sec_log, "Goodbye packet received");
                        SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Received goodbye frame", nil);
                        nw_framer_mark_failed_with_error(framer, 0); // Goodbye
                        return 0;
                    }
                    __block NSData *decryptedBody = nil;
                    size_t bodyActual = nw_framer_parse_input(framer, bodyLen, bodyLen, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                        if (buffer_length >= bodyLen) {
                            decryptedBody = [context.boxStream decryptBody:[NSData dataWithBytes:buffer length:bodyLen] 
                                                               expectedMac:context.pendingBodyMac];
                            if (!decryptedBody) {
                                os_log_error(ssb_sec_log, "Box body decrypt FAILED");
                                SSBSecurityEmitTrace(context.connectionID, @"inbound", context.peerID, context.state, @"Failed to decrypt box body", nil);
                            }
                            return bodyLen;
                        }
                        return 0;
                    });
                    
                    if (bodyActual == 0) return bodyLen;
                    
                    context.state = SSBSecurityStateBoxHeader;
                    if (decryptedBody) {
                        nw_framer_message_t message = nw_framer_message_create(framer);
                        nw_framer_deliver_input(framer, decryptedBody.bytes, decryptedBody.length, message, true);
                    }
                }
            }
        }
        default: return 0;
    }
}

+ (void)handleOutput:(nw_framer_t)framer message:(nw_framer_message_t)message messageLength:(size_t)messageLength context:(SSBSecurityContext *)context {
    if (context.state < SSBSecurityStateBoxHeader) {
        os_log_debug(ssb_sec_log, "handleOutput BUFFERING message because state is %ld (len=%zu)", (long)context.state, messageLength);
        SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Buffered outbound payload until handshake is ready", @{ @"bodyLength": @(messageLength) });
        __block NSData *bufferedData = nil;
        nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
            if (buffer_length >= messageLength) {
                bufferedData = [NSData dataWithBytes:buffer length:messageLength];
                return messageLength;
            }
            return 0;
        });
        if (bufferedData) {
            [context.outputBuffer addObject:@{ @"data": bufferedData }];
        }
        return;
    }
    
    nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
        NSData *encrypted = [context.boxStream encryptPayload:[NSData dataWithBytes:buffer length:buffer_length]];
        if (encrypted) {
            dispatch_data_t encryptedData = dispatch_data_create(encrypted.bytes, encrypted.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_framer_write_output_data(framer, encryptedData);
            os_log_debug(ssb_sec_log, "Sent encrypted frame of length %lu (original %lu)", (unsigned long)encrypted.length, (unsigned long)buffer_length);
            SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Encrypted outbound payload", @{ @"bodyLength": @(buffer_length), @"wireLength": @(encrypted.length) });
            return buffer_length;
        }
        os_log_error(ssb_sec_log, "Encryption FAILED for payload of length %lu", (unsigned long)buffer_length);
        SSBSecurityEmitTrace(context.connectionID, @"outbound", context.peerID, context.state, @"Failed to encrypt outbound payload", @{ @"bodyLength": @(buffer_length) });
        return 0;
    });
}

+ (nw_protocol_options_t)createOptionsWithLocalSecretKey:(NSData *)localSecretKey
                                         remotePublicKey:(NSData *)remotePublicKey
                                                asClient:(BOOL)asClient {
    nw_protocol_options_t options = nw_framer_create_options([self createDefinition]);
    nw_framer_options_set_object_value(options, kSSBSecurityLocalKey, localSecretKey);
    if (remotePublicKey) {
        nw_framer_options_set_object_value(options, kSSBSecurityRemoteKey, remotePublicKey);
    }
    nw_framer_options_set_object_value(options, kSSBSecurityAsClient, @(asClient));
    return options;
}

@end
