#import "SSBProtocolFramer.h"
#import "SSBSecretHandshake.h"
#import "SSBBoxStream.h"
#import "SSBMuxRPC.h"
#import <os/log.h>

static const char *kSSBFramerName = "com.scuttlebutt.framer";
static os_log_t ssb_framer_log;

typedef NS_ENUM(NSInteger, SSBFramerState) {
    SSBFramerStateHandshakeInit = 0,
    SSBFramerStateHandshakeHelloWait,
    SSBFramerStateHandshakeAuthWait,
    SSBFramerStateHandshakeAcceptWait,
    SSBFramerStateBoxStreamReady
};

@interface SSBFramerContext : NSObject
@property (nonatomic, strong) SSBSecretHandshake *handshake;
@property (nonatomic, strong) SSBBoxStream *boxStream;
@property (nonatomic, assign) SSBFramerState state;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SSBFramerContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _state = SSBFramerStateHandshakeInit;
        _queue = dispatch_queue_create("com.scuttlebutt.framer.context", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
@end

@implementation SSBProtocolFramer

+ (void)initialize {
    if (self == [SSBProtocolFramer class]) {
        ssb_framer_log = os_log_create("com.scuttlebutt.network", "Framer");
    }
}

+ (nw_protocol_definition_t)framerDefinition {
    return nw_framer_create_definition(kSSBFramerName, NW_FRAMER_CREATE_FLAGS_DEFAULT, ^nw_framer_start_result_t(nw_framer_t framer) {
        os_log_info(ssb_framer_log, "SSB Framer started");
        
        SSBFramerContext *context = [[SSBFramerContext alloc] init];
        
        // Retain the context on the framer
        nw_framer_set_context(framer, (__bridge_retained void *)context);
        
        nw_framer_set_cleanup_handler(framer, ^(nw_framer_t inner_framer) {
            void *rawContext = nw_framer_get_context(inner_framer);
            if (rawContext) {
                CFRelease(rawContext);
            }
        });
        
        nw_protocol_metadata_t metadata = nw_framer_get_parameters(framer);
        nw_protocol_options_t options = nw_parameters_copy_protocol_options_custom(metadata, kSSBFramerName);
        SSBProtocolOptions *ssbOptions = [SSBProtocolOptions optionsFromProtocolOptions:options];
        
        if (!ssbOptions) {
            os_log_error(ssb_framer_log, "Missing SSBProtocolOptions");
            return nw_framer_start_result_unknown;
        }
        
        context.handshake = [[SSBSecretHandshake alloc] initWithRole:YES
                                                       localIdentity:ssbOptions.localSecretKey
                                                     remotePublicKey:ssbOptions.remotePublicKey
                                                   networkIdentifier:ssbOptions.networkIdentifier];
        
        // 1. Send Hello
        NSData *helloPacket = [context.handshake createClientHello];
        if (!helloPacket) {
            return nw_framer_start_result_unknown;
        }
        
        dispatch_data_t outData = dispatch_data_create(helloPacket.bytes, helloPacket.length, context.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_framer_write_output_data(framer, outData);
        context.state = SSBFramerStateHandshakeHelloWait;
        
        // 2. Setup Handshake receive logic
        nw_framer_set_input_handler(framer, ^size_t(nw_framer_t inner_framer) {
            return [self handleInput:inner_framer context:context];
        });
        
        nw_framer_set_output_handler(framer, ^(nw_framer_t inner_framer, nw_framer_message_t message, size_t message_length, bool is_complete) {
            [self handleOutput:inner_framer message:message messageLength:message_length context:context];
        });
        
        return nw_framer_start_result_ready;
    });
}

+ (size_t)handleInput:(nw_framer_t)framer context:(SSBFramerContext *)context {
    switch (context.state) {
        case SSBFramerStateHandshakeHelloWait: {
            size_t req = 64;
            __block BOOL parsed = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    NSData *data = [NSData dataWithBytes:buffer length:req];
                    parsed = [context.handshake verifyServerHello:data];
                    return req;
                }
                return 0;
            });
            if (parsed) {
                NSData *authPacket = [context.handshake createClientAuth];
                dispatch_data_t outData = dispatch_data_create(authPacket.bytes, authPacket.length, context.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                nw_framer_write_output_data(framer, outData);
                context.state = SSBFramerStateHandshakeAcceptWait;
                return 0; // Check input immediately again
            }
            return req;
        }
            
        case SSBFramerStateHandshakeAcceptWait: {
            size_t req = 80;
            __block BOOL parsed = NO;
            nw_framer_parse_input(framer, req, req, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= req) {
                    NSData *data = [NSData dataWithBytes:buffer length:req];
                    parsed = [context.handshake verifyServerAccept:data];
                    return req;
                }
                return 0;
            });
            if (parsed) {
                context.boxStream = [context.handshake createBoxStream];
                context.state = SSBFramerStateBoxStreamReady;
                nw_framer_mark_ready(framer); // We are fully connected to the application
                return 0; // Check for Box Stream headers
            }
            return req;
        }
            
        case SSBFramerStateBoxStreamReady: {
            // Box Stream parsing
            // 1. Read 34 byte header
            size_t headerReq = 34;
            __block size_t bodyLen = 0;
            __block NSData *bodyMac = nil;
            __block BOOL parsedHeader = NO;
            
            nw_framer_parse_input(framer, headerReq, headerReq, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                if (buffer_length >= headerReq) {
                    NSData *headerData = [NSData dataWithBytes:buffer length:headerReq];
                    parsedHeader = [context.boxStream decryptHeader:headerData outLength:&bodyLen outBodyMac:&bodyMac];
                    return headerReq;
                }
                return 0;
            });
            
            if (parsedHeader) {
                // If body length is 0 and mac is all zeros, it's a goodbye packet
                if (bodyLen == 0) {
                    // TODO: check goodbye MAC
                    nw_framer_mark_failed_with_error(framer, 0); // Graceful close
                    return 0;
                }
                
                // 2. Parse body
                __block BOOL parsedBody = NO;
                nw_framer_parse_input(framer, bodyLen, bodyLen, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                    if (buffer_length >= bodyLen) {
                        NSData *bodyData = [NSData dataWithBytes:buffer length:bodyLen];
                        NSData *decryptedBody = [context.boxStream decryptBody:bodyData expectedMac:bodyMac];
                        if (decryptedBody) {
                            nw_framer_message_t msg = nw_framer_message_create(framer);
                            dispatch_data_t outData = dispatch_data_create(decryptedBody.bytes, decryptedBody.length, context.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                            nw_framer_deliver_input(framer, outData, msg, true);
                            parsedBody = YES;
                            return bodyLen;
                        } else {
                            os_log_error(ssb_framer_log, "BoxStream body decryption failed");
                        }
                    }
                    return 0;
                });
                
                if (parsedBody) {
                    return 0; // Check for next packet
                } else {
                    return bodyLen; // Need more bytes for body
                }
            }
            return headerReq;
        }
            
        default:
            return 0;
    }
}

+ (void)handleOutput:(nw_framer_t)framer message:(nw_framer_message_t)message messageLength:(size_t)messageLength context:(SSBFramerContext *)context {
    if (context.state != SSBFramerStateBoxStreamReady) {
        os_log_error(ssb_framer_log, "Attempted to send before BoxStream ready");
        return;
    }
    
    // Output comes in as a blob of decrypted data. We must BoxStream encrypt it.
    // In Network.framework, we receive chunks of data and we can consume them
    nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
        NSData *payload = [NSData dataWithBytes:buffer length:buffer_length];
        NSData *encryptedPacket = [context.boxStream encryptPayload:payload];
        
        if (encryptedPacket) {
            dispatch_data_t outData = dispatch_data_create(encryptedPacket.bytes, encryptedPacket.length, context.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_framer_write_output_data(framer, outData);
            return buffer_length;
        }
        return 0;
    });
}

+ (nw_protocol_options_t)createOptionsWithSSBOptions:(SSBProtocolOptions *)options {
    nw_protocol_options_t nw_opts = nw_framer_create_options([self framerDefinition]);
    [options applyToProtocolOptions:nw_opts];
    return nw_opts;
}

@end