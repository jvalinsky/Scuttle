#import "SSBMuxRPCFramer.h"
#import "SSBMuxRPC.h"
#import "SSBLogCompat.h"
#import "SSBLogger.h"

static const char *kSSBMuxRPCFramerName = "SSBMuxRPC";
static os_log_t ssb_rpc_log;

@interface SSBLogger (SSBMuxRPCFramerTrace)
+ (void)ssb_emitProtocolTraceEvent:(NSDictionary<NSString *, id> *)event;
@end

typedef NS_ENUM(NSInteger, SSBMuxRPCState) {
    SSBMuxRPCStateHeader,
    SSBMuxRPCStateBody
};

static NSString *SSBMuxRPCStateName(SSBMuxRPCState state) {
    switch (state) {
        case SSBMuxRPCStateHeader: return @"header";
        case SSBMuxRPCStateBody: return @"body";
    }
    return @"unknown";
}

static const uint8_t kSSBMuxRPCEmptyPayloadByte = 0;
static const char *kSSBMuxRPCSyntheticZeroLengthBodyKey = "SyntheticZeroLengthBody";

@interface SSBMuxRPCContext : NSObject
@property (nonatomic, assign) SSBMuxRPCState state;
@property (nonatomic, assign) SSBMuxRPCFlags flags;
@property (nonatomic, assign) int32_t reqNum;
@property (nonatomic, assign) uint32_t bodyLen;
@property (nonatomic, copy) NSString *connectionID;
@end

@implementation SSBMuxRPCContext 
- (instancetype)init { self = [super init]; if (self) { _state = SSBMuxRPCStateHeader; } return self; }
@end

static void SSBMuxRPCEmitTrace(NSString *connectionID,
                               NSString *direction,
                               SSBMuxRPCState state,
                               int32_t requestNumber,
                               NSString *message,
                               NSDictionary<NSString *, id> *extras) {
    NSMutableDictionary<NSString *, id> *event = [NSMutableDictionary dictionary];
    event[@"component"] = @"muxrpc.framer";
    event[@"connectionID"] = connectionID ?: @"muxrpc";
    event[@"direction"] = direction ?: @"internal";
    event[@"framerState"] = SSBMuxRPCStateName(state);
    event[@"requestID"] = @(requestNumber);
    event[@"peerID"] = @"<transport-peer>";
    event[@"message"] = message ?: @"";
    if (extras.count > 0) {
        [event addEntriesFromDictionary:extras];
    }
    [SSBLogger ssb_emitProtocolTraceEvent:event];
}

@implementation SSBMuxRPCFramer

+ (void)initialize {
    if (self == [SSBMuxRPCFramer class]) {
        ssb_rpc_log = os_log_create("com.scuttlebutt.network", "MuxRPCFramer");
    }
}

+ (nw_protocol_definition_t)createDefinition {
    static nw_protocol_definition_t definition = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definition = nw_framer_create_definition(kSSBMuxRPCFramerName, NW_FRAMER_CREATE_FLAGS_DEFAULT, ^nw_framer_start_result_t(nw_framer_t framer) {
            SSBMuxRPCContext *context = [[SSBMuxRPCContext alloc] init];
            context.connectionID = [[NSUUID UUID] UUIDString];
            
            nw_framer_set_input_handler(framer, ^size_t(nw_framer_t inner_framer) {
                // NSLog(@"[MuxRPCFramer] Input handler called");
                while (true) {
                    if (context.state == SSBMuxRPCStateHeader) {
                        size_t headerReq = 9;
                        __block BOOL success = NO;
                        __block SSBMuxRPCFlags flags;
                        __block int32_t reqNum;
                        nw_framer_parse_input(inner_framer, headerReq, headerReq, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                            if (buffer_length >= headerReq) {
                                context.bodyLen = [SSBMuxRPCMessage parseHeader:[NSData dataWithBytes:buffer length:headerReq] 
                                                                       outFlags:&flags 
                                                               outRequestNumber:&reqNum];
                                context.flags = flags;
                                context.reqNum = reqNum;
                                success = YES;
                                SSBMuxRPCEmitTrace(context.connectionID,
                                                   @"inbound",
                                                   context.state,
                                                   reqNum,
                                                   @"Parsed muxrpc header",
                                                   @{ @"flags": @(flags),
                                                      @"bodyLength": @(context.bodyLen) });
                                return headerReq;
                            }
                            return 0;
                        });
                        if (success) {
                            context.state = SSBMuxRPCStateBody;
                        } else {
                            return headerReq;
                        }
                    }
                    
                    if (context.state == SSBMuxRPCStateBody) {
                        size_t bodyReq = context.bodyLen;
                        __block BOOL success = NO;
                        if (bodyReq > 0) {
                            nw_framer_parse_input(inner_framer, bodyReq, bodyReq, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                                if (buffer_length >= bodyReq) {
                                    nw_framer_message_t message = nw_framer_message_create(inner_framer);
                                    nw_framer_message_set_object_value(message, "Flags", @(context.flags));
                                    nw_framer_message_set_object_value(message, "RequestNumber", @(context.reqNum));
                                    nw_framer_deliver_input(inner_framer, buffer, bodyReq, message, true);
                                    SSBMuxRPCEmitTrace(context.connectionID,
                                                       @"inbound",
                                                       context.state,
                                                       context.reqNum,
                                                       @"Delivered muxrpc body",
                                                       @{ @"flags": @(context.flags),
                                                          @"bodyLength": @(bodyReq) });
                                    success = YES;
                                    return bodyReq;
                                }
                                return 0;
                            });
                            if (!success) {
                                return bodyReq;
                            }
                        } else {
                            nw_framer_message_t message = nw_framer_message_create(inner_framer);
                            nw_framer_message_set_object_value(message, "Flags", @(context.flags));
                            nw_framer_message_set_object_value(message, "RequestNumber", @(context.reqNum));
#ifdef __APPLE__
                            /*
                             Network.framework drops metadata for zero-length framer deliveries. Preserve
                             the message boundary with a private placeholder byte and strip it in transport.
                             */
                            nw_framer_message_set_object_value(message, kSSBMuxRPCSyntheticZeroLengthBodyKey, @YES);
                            nw_framer_deliver_input(inner_framer, &kSSBMuxRPCEmptyPayloadByte, 1, message, true);
#else
                            nw_framer_deliver_input(inner_framer, &kSSBMuxRPCEmptyPayloadByte, 0, message, true);
#endif
                            success = YES;
                            SSBMuxRPCEmitTrace(context.connectionID,
                                               @"inbound",
                                               context.state,
                                               context.reqNum,
                                               @"Delivered zero-length muxrpc body",
                                               @{ @"flags": @(context.flags) });
                            os_log_debug(ssb_rpc_log, "DELIVERED empty message: flags=%u req=%d", context.flags, context.reqNum);
                        }
                        
                        if (success) {
                            context.state = SSBMuxRPCStateHeader;
                        }
                    }
                }
            });
            
            nw_framer_set_output_handler(framer, ^(nw_framer_t inner_framer, nw_framer_message_t message, size_t message_length, bool is_complete) {
                [SSBMuxRPCFramer handleOutput:inner_framer message:message messageLength:message_length];
            });

            return nw_framer_start_result_ready;
        });
    });
    return definition;
}

+ (void)handleOutput:(nw_framer_t)framer message:(nw_framer_message_t)message messageLength:(size_t)messageLength {
    os_log_debug(ssb_rpc_log, "handleOutput: passing through %zu bytes", messageLength);
    nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
        SSBMuxRPCFlags flags = 0;
        int32_t requestNumber = 0;
        if (buffer_length >= 9) {
            NSData *header = [NSData dataWithBytes:buffer length:9];
            [SSBMuxRPCMessage parseHeader:header outFlags:&flags outRequestNumber:&requestNumber];
        }
        SSBMuxRPCEmitTrace(nil,
                           @"outbound",
                           SSBMuxRPCStateBody,
                           requestNumber,
                           @"Forwarded muxrpc payload to transport",
                           @{ @"flags": @(flags),
                              @"wireLength": @(buffer_length) });
        nw_framer_write_output_data(framer, dispatch_data_create(buffer, buffer_length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT));
        return buffer_length;
    });
}

+ (nw_protocol_options_t)createOptions {
    nw_protocol_options_t options = nw_framer_create_options([self createDefinition]);
    return options;
}

@end
