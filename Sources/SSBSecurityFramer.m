#import "SSBSecurityFramer.h"
#import "SSBSecretHandshake.h"
#import "SSBBoxStream.h"
#import "SSBLogCompat.h"

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

@interface SSBSecurityContext : NSObject
@property (nonatomic, strong) SSBSecretHandshake *handshake;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, assign) SSBSecurityState state;
@property (nonatomic, strong) NSMutableArray *outputBuffer;
@property (nonatomic, assign) size_t pendingBodyLen;
@property (nonatomic, strong) NSData *pendingBodyMac;
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
            
            if (!localKey || (!remoteKey && asClient)) {
                os_log_error(ssb_sec_log, "Missing keys in security framer options");
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
            } else {
                context.state = SSBSecurityStateHandshakeHelloWait;
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
                NSData *hello = [context.handshake createHello];
                dispatch_data_t helloData = dispatch_data_create(hello.bytes, hello.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, helloData);
                context.state = SSBSecurityStateHandshakeAuthWait;
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
                NSData *auth = [context.handshake createAuth];
                dispatch_data_t authData = dispatch_data_create(auth.bytes, auth.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, authData);
                context.state = SSBSecurityStateHandshakeAcceptWait;
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
                context.boxStream = [[SSBBoxStream alloc] initWithClientToServerKey:context.handshake.clientToServerKey
                                                                  serverToClientKey:context.handshake.serverToClientKey
                                                                clientToServerNonce:context.handshake.clientToServerNonce
                                                                serverToClientNonce:context.handshake.serverToClientNonce];
                context.boxStream.isClient = context.handshake.isClient;
                context.state = SSBSecurityStateBoxHeader;
                nw_framer_mark_ready(framer); // SHS DONE!
                
                // Flush buffer
                for (NSDictionary *item in context.outputBuffer) {
                    NSData *data = item[@"data"];
                    nw_framer_message_t msg = (nw_framer_message_t)item[@"msg"];
                    [SSBSecurityFramer handleOutput:framer message:msg messageLength:data.length context:context];
                }
                [context.outputBuffer removeAllObjects];
                
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
                            }
                            return bodyLen;
                        }
                        return 0;
                    });
                    
                    if (bodyActual == 0) return bodyLen;
                    
                    context.state = SSBSecurityStateBoxHeader;
                    if (decryptedBody) {
                        nw_framer_message_t message = nw_framer_message_create(framer);
                        nw_framer_deliver_input(framer, decryptedBody.bytes, decryptedBody.length, message, false);
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
        __block NSData *bufferedData = nil;
        nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
            if (buffer_length >= messageLength) {
                bufferedData = [NSData dataWithBytes:buffer length:messageLength];
                return messageLength;
            }
            return 0;
        });
        if (bufferedData) {
            [context.outputBuffer addObject:@{@"msg": message, @"data": bufferedData}];
        }
        return;
    }
    
    nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
        NSData *encrypted = [context.boxStream encryptPayload:[NSData dataWithBytes:buffer length:buffer_length]];
        if (encrypted) {
            dispatch_data_t encryptedData = dispatch_data_create(encrypted.bytes, encrypted.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_framer_write_output_data(framer, encryptedData);
            os_log_debug(ssb_sec_log, "Sent encrypted frame of length %lu (original %lu)", (unsigned long)encrypted.length, (unsigned long)buffer_length);
            return buffer_length;
        }
        os_log_error(ssb_sec_log, "Encryption FAILED for payload of length %lu", (unsigned long)buffer_length);
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