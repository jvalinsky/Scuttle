#import "SSBMuxRPCFramer.h"
#import "SSBMuxRPC.h"
#import <os/log.h>

static const char *kSSBMuxRPCFramerName = "SSBMuxRPC";
static os_log_t ssb_rpc_log;

typedef NS_ENUM(NSInteger, SSBMuxRPCState) {
    SSBMuxRPCStateHeader,
    SSBMuxRPCStateBody
};

@interface SSBMuxRPCContext : NSObject
@property (nonatomic, assign) SSBMuxRPCState state;
@property (nonatomic, assign) SSBMuxRPCFlags flags;
@property (nonatomic, assign) int32_t reqNum;
@property (nonatomic, assign) uint32_t bodyLen;
@end

@implementation SSBMuxRPCContext 
- (instancetype)init { self = [super init]; if (self) { _state = SSBMuxRPCStateHeader; } return self; }
@end

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
            
            nw_framer_set_input_handler(framer, ^size_t(nw_framer_t inner_framer) {
                // NSLog(@"[MuxRPCFramer] Input handler called");
                while (true) {
                    if (context.state == SSBMuxRPCStateHeader) {
                        size_t headerReq = 9;
                        __block BOOL success = NO;
                        __block SSBMuxRPCFlags flags;
                        __block int32_t reqNum;
                        size_t parsed = nw_framer_parse_input(inner_framer, headerReq, headerReq, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
                            if (buffer_length >= headerReq) {
                                context.bodyLen = [SSBMuxRPCMessage parseHeader:[NSData dataWithBytes:buffer length:headerReq] 
                                                                       outFlags:&flags 
                                                               outRequestNumber:&reqNum];
                                context.flags = flags;
                                context.reqNum = reqNum;
                                success = YES;
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
                            nw_framer_deliver_input(inner_framer, NULL, 0, message, true);
                            success = YES;
                            NSLog(@"[MuxRPCFramer] DELIVERED empty message: flags=%u req=%d", context.flags, context.reqNum);
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
    NSLog(@"[MuxRPCFramer] handleOutput: passing through %zu bytes", messageLength);
    nw_framer_parse_output(framer, messageLength, messageLength, NULL, ^size_t(uint8_t *buffer, size_t buffer_length, bool is_complete) {
        nw_framer_write_output_data(framer, dispatch_data_create(buffer, buffer_length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT));
        return buffer_length;
    });
}

+ (nw_protocol_options_t)createOptions {
    nw_protocol_options_t options = nw_framer_create_options([self createDefinition]);
    return options;
}

@end