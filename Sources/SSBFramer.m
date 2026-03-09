#import "SSBFramer.h"
#import "SSBConnectionFSM.h"
#import <Network/Network.h>
#import <os/log.h>

static const char *kSSBFramerProtocolName = "SSB";
static os_log_t ssb_framer_log;

@implementation SSBFramer

+ (void)initialize {
    if (self == [SSBFramer class]) {
        ssb_framer_log = os_log_create("com.scuttlebutt.network", "Framer");
    }
}

+ (nw_protocol_definition_t)createFramerDefinition {
    nw_protocol_definition_t definition = nw_framer_create_definition(kSSBFramerProtocolName, NW_FRAMER_CREATE_FLAGS_DEFAULT, ^nw_framer_start_result_t(nw_framer_t framer) {
        os_log_info(ssb_framer_log, "Framer started");
        
        // ARC will automatically retain 'fsm' for any blocks that capture it
        SSBConnectionFSM *fsm = [[SSBConnectionFSM alloc] init];
        
        nw_framer_set_input_handler(framer, ^size_t(nw_framer_t inner_framer) {
            size_t required_bytes = 0;
            
            switch (fsm.currentState) {
                case SSBConnectionStateInit:
                    required_bytes = 64;
                    break;
                case SSBConnectionStateSHSHelloReceived:
                    required_bytes = 64;
                    break;
                case SSBConnectionStateSHSAuthReceived:
                    required_bytes = 112;
                    break;
                case SSBConnectionStateSHSAcceptReceived:
                    required_bytes = 80;
                    break;
                case SSBConnectionStateBoxStream:
                    required_bytes = 34;
                    break;
                default:
                    required_bytes = 0;
                    break;
            }
            
            if (required_bytes == 0) return 0;
            
            __block bool parsing_success = false;
            
            bool parsed = nw_framer_parse_input(inner_framer, required_bytes, required_bytes, NULL, ^size_t(uint8_t * _Nullable buffer, size_t buffer_length, bool is_complete) {
                if (buffer == NULL || buffer_length < required_bytes) {
                    return 0; // Wait for more
                }
                os_log_debug(ssb_framer_log, "Parsed %zu bytes for state %ld", required_bytes, (long)fsm.currentState);
                parsing_success = true;
                return required_bytes; // Consume bytes
            });
            
            if (parsed && parsing_success) {
                [fsm advanceState];
                return 0; // Hint 0 means call me as soon as anything is available
            }
            
            // Wait for required_bytes
            return required_bytes;
        });
        
        nw_framer_set_output_handler(framer, ^(nw_framer_t inner_framer, nw_framer_message_t message, size_t message_length, bool is_complete) {
            os_log_debug(ssb_framer_log, "Framer output handling %zu bytes, FSM state %ld", message_length, (long)fsm.currentState);
            // In a real implementation we would encrypt and frame here
            // But we must consume the message length to tell the framer it is handled
            // Without having parsed anything, we shouldn't just write. This is a stub.
            // nw_framer_write_output(inner_framer, ...);
        });
        
        nw_framer_set_stop_handler(framer, ^bool(nw_framer_t inner_framer) {
            os_log_info(ssb_framer_log, "Framer stopped, FSM state %ld", (long)fsm.currentState);
            return true;
        });
        
        return nw_framer_start_result_ready;
    });
    
    return definition;
}

@end
