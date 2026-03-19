#ifndef SSBNetworkCompat_h
#define SSBNetworkCompat_h

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#ifdef __APPLE__
    #import <Network/Network.h>
#else

NS_ASSUME_NONNULL_BEGIN

/**
 * 2026 Linux/GNUstep Compatibility Shim for Apple's Network.framework
 * This shim provides just enough types and functions to support Scuttle's custom framers.
 * It is intended for linkage ONLY; actual logic is currently stubbed.
 */

// Basic Types
typedef id nw_connection_t;
typedef id nw_parameters_t;
typedef id nw_endpoint_t;
typedef id nw_protocol_options_t;
typedef id nw_protocol_definition_t;
typedef id nw_protocol_stack_t;
typedef id nw_protocol_metadata_t;
typedef id nw_content_context_t;
typedef id nw_framer_t;
typedef id nw_framer_message_t;
typedef id nw_error_t;
typedef id nw_listener_t;

// Enums
typedef enum {
    nw_connection_state_invalid = 0,
    nw_connection_state_waiting = 1,
    nw_connection_state_preparing = 2,
    nw_connection_state_ready = 3,
    nw_connection_state_failed = 4,
    nw_connection_state_cancelled = 5,
} nw_connection_state_t;

typedef enum {
    nw_framer_start_result_ready = 1,
    nw_framer_start_result_will_mark_ready = 2,
} nw_framer_start_result_t;

typedef enum {
    nw_listener_state_invalid = 0,
    nw_listener_state_waiting = 1,
    nw_listener_state_ready = 2,
    nw_listener_state_failed = 3,
    nw_listener_state_cancelled = 4,
} nw_listener_state_t;

// Constants
#define NW_PARAMETERS_DISABLE_PROTOCOL NULL
#define NW_PARAMETERS_DEFAULT_CONFIGURATION NULL
#define NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT NULL
#define NW_FRAMER_CREATE_FLAGS_DEFAULT 0

// Blocks
typedef void (^nw_connection_state_changed_handler_t)(nw_connection_state_t state, nw_error_t _Nullable error);
typedef void (^nw_parameters_configure_protocol_block_t)(nw_protocol_options_t options);
typedef nw_framer_start_result_t (^nw_framer_start_handler_t)(nw_framer_t framer);
typedef size_t (^nw_framer_input_handler_t)(nw_framer_t framer);
typedef void (^nw_framer_output_handler_t)(nw_framer_t framer, nw_framer_message_t message, size_t message_length, bool is_complete);
typedef void (^nw_connection_receive_completion_t)(dispatch_data_t _Nullable content, nw_content_context_t _Nullable context, bool is_complete, nw_error_t _Nullable error);
typedef void (^nw_connection_send_completion_t)(nw_error_t _Nullable error);
typedef size_t (^nw_framer_parse_completion_t)(uint8_t *buffer, size_t buffer_length, bool is_complete);
typedef void (^nw_listener_state_changed_handler_t)(nw_listener_state_t state, nw_error_t _Nullable error);
typedef void (^nw_listener_new_connection_handler_t)(nw_connection_t connection);

// --- Functions ---

// Endpoints
nw_endpoint_t nw_endpoint_create_host(const char *hostname, const char *port);

// Parameters
nw_parameters_t nw_parameters_create_secure_tcp(nw_parameters_configure_protocol_block_t _Nullable configure_tls, nw_parameters_configure_protocol_block_t configure_tcp);
nw_protocol_stack_t nw_parameters_copy_default_protocol_stack(nw_parameters_t parameters);
void nw_parameters_set_local_endpoint(nw_parameters_t parameters, nw_endpoint_t _Nullable endpoint);

// Protocol Stack
void nw_protocol_stack_prepend_application_protocol(nw_protocol_stack_t stack, nw_protocol_options_t options);

// Connections
nw_connection_t nw_connection_create(nw_endpoint_t endpoint, nw_parameters_t parameters);
void nw_connection_set_queue(nw_connection_t connection, dispatch_queue_t queue);
void nw_connection_set_state_changed_handler(nw_connection_t connection, nw_connection_state_changed_handler_t handler);
void nw_connection_start(nw_connection_t connection);
void nw_connection_receive_message(nw_connection_t connection, nw_connection_receive_completion_t completion);
void nw_connection_send(nw_connection_t connection, dispatch_data_t content, nw_content_context_t _Nullable context, bool is_complete, nw_connection_send_completion_t completion);
void nw_connection_cancel(nw_connection_t connection);

// Framers
nw_protocol_definition_t nw_framer_create_definition(const char *identifier, uint32_t flags, nw_framer_start_handler_t start_handler);
nw_protocol_options_t nw_framer_create_options(nw_protocol_definition_t definition);
nw_protocol_options_t nw_framer_copy_options(nw_framer_t framer);
void nw_framer_options_set_object_value(nw_protocol_options_t options, const char *key, id _Nullable value);
id _Nullable nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key);
void nw_framer_set_input_handler(nw_framer_t framer, nw_framer_input_handler_t input_handler);
void nw_framer_set_output_handler(nw_framer_t framer, nw_framer_output_handler_t output_handler);
void nw_framer_mark_ready(nw_framer_t framer);
void nw_framer_mark_failed_with_error(nw_framer_t framer, int error_code);
bool nw_framer_parse_input(nw_framer_t framer, size_t minimum_incomplete_length, size_t maximum_length, uint8_t * _Nullable temp_buffer, nw_framer_parse_completion_t parse_completion);
void nw_framer_parse_output(nw_framer_t framer, size_t minimum_incomplete_length, size_t maximum_length, uint8_t * _Nullable temp_buffer, nw_framer_parse_completion_t parse_completion);
void nw_framer_write_output_data(nw_framer_t framer, dispatch_data_t data);
void nw_framer_deliver_input(nw_framer_t framer, const void *input_buffer, size_t input_length, nw_framer_message_t message, bool is_complete);
nw_framer_message_t nw_framer_message_create(nw_framer_t framer);
void nw_framer_message_set_object_value(nw_framer_message_t message, const char *key, id _Nullable value);
id _Nullable nw_framer_message_copy_object_value(nw_framer_message_t message, const char *key);

// Metadata
nw_protocol_metadata_t nw_content_context_copy_protocol_metadata(nw_content_context_t context, nw_protocol_definition_t definition);

// TCP options
void nw_tcp_options_set_no_delay(nw_protocol_options_t options, bool no_delay);

// Listeners
nw_listener_t nw_listener_create(nw_parameters_t parameters);
void nw_listener_set_queue(nw_listener_t listener, dispatch_queue_t queue);
void nw_listener_set_state_changed_handler(nw_listener_t listener, nw_listener_state_changed_handler_t handler);
void nw_listener_set_new_connection_handler(nw_listener_t listener, nw_listener_new_connection_handler_t handler);
void nw_listener_start(nw_listener_t listener);
void nw_listener_cancel(nw_listener_t listener);
uint16_t nw_listener_get_port(nw_listener_t listener);

NS_ASSUME_NONNULL_END

#endif /* __APPLE__ */

#endif /* SSBNetworkCompat_h */
