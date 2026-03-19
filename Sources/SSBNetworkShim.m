#import "SSBNetworkCompat.h"

#ifndef __APPLE__

nw_endpoint_t nw_endpoint_create_host(const char *hostname, const char *port) {
    NSLog(@"STUB: nw_endpoint_create_host(%s, %s)", hostname, port);
    return NULL;
}

nw_parameters_t nw_parameters_create_secure_tcp(nw_parameters_configure_protocol_block_t _Nullable configure_tls, nw_parameters_configure_protocol_block_t configure_tcp) {
    NSLog(@"STUB: nw_parameters_create_secure_tcp");
    return NULL;
}

nw_protocol_stack_t nw_parameters_copy_default_protocol_stack(nw_parameters_t parameters) {
    NSLog(@"STUB: nw_parameters_copy_default_protocol_stack");
    return NULL;
}

void nw_parameters_set_local_endpoint(nw_parameters_t parameters, nw_endpoint_t _Nullable endpoint) {
    NSLog(@"STUB: nw_parameters_set_local_endpoint");
}

void nw_protocol_stack_prepend_application_protocol(nw_protocol_stack_t stack, nw_protocol_options_t options) {
    NSLog(@"STUB: nw_protocol_stack_prepend_application_protocol");
}

nw_connection_t nw_connection_create(nw_endpoint_t endpoint, nw_parameters_t parameters) {
    NSLog(@"STUB: nw_connection_create");
    return NULL;
}

void nw_connection_set_queue(nw_connection_t connection, dispatch_queue_t queue) {
    NSLog(@"STUB: nw_connection_set_queue");
}

void nw_connection_set_state_changed_handler(nw_connection_t connection, nw_connection_state_changed_handler_t handler) {
    NSLog(@"STUB: nw_connection_set_state_changed_handler");
}

void nw_connection_start(nw_connection_t connection) {
    NSLog(@"STUB: nw_connection_start");
}

void nw_connection_receive_message(nw_connection_t connection, nw_connection_receive_completion_t completion) {
    NSLog(@"STUB: nw_connection_receive_message");
}

void nw_connection_send(nw_connection_t connection, dispatch_data_t content, nw_content_context_t _Nullable context, bool is_complete, nw_connection_send_completion_t completion) {
    NSLog(@"STUB: nw_connection_send");
}

void nw_connection_cancel(nw_connection_t connection) {
    NSLog(@"STUB: nw_connection_cancel");
}

nw_protocol_definition_t nw_framer_create_definition(const char *identifier, uint32_t flags, nw_framer_start_handler_t start_handler) {
    NSLog(@"STUB: nw_framer_create_definition(%s)", identifier);
    return NULL;
}

nw_protocol_options_t nw_framer_create_options(nw_protocol_definition_t definition) {
    NSLog(@"STUB: nw_framer_create_options");
    return NULL;
}

nw_protocol_options_t nw_framer_copy_options(nw_framer_t framer) {
    NSLog(@"STUB: nw_framer_copy_options");
    return NULL;
}

void nw_framer_options_set_object_value(nw_protocol_options_t options, const char *key, id _Nullable value) {
    NSLog(@"STUB: nw_framer_options_set_object_value(%s)", key);
}

id _Nullable nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key) {
    NSLog(@"STUB: nw_framer_options_copy_object_value(%s)", key);
    return NULL;
}

void nw_framer_set_input_handler(nw_framer_t framer, nw_framer_input_handler_t input_handler) {
    NSLog(@"STUB: nw_framer_set_input_handler");
}

void nw_framer_set_output_handler(nw_framer_t framer, nw_framer_output_handler_t output_handler) {
    NSLog(@"STUB: nw_framer_set_output_handler");
}

void nw_framer_mark_ready(nw_framer_t framer) {
    NSLog(@"STUB: nw_framer_mark_ready");
}

void nw_framer_mark_failed_with_error(nw_framer_t framer, int error_code) {
    NSLog(@"STUB: nw_framer_mark_failed_with_error(%d)", error_code);
}

bool nw_framer_parse_input(nw_framer_t framer, size_t minimum_incomplete_length, size_t maximum_length, uint8_t * _Nullable temp_buffer, nw_framer_parse_completion_t parse_completion) {
    NSLog(@"STUB: nw_framer_parse_input");
    return false;
}

void nw_framer_parse_output(nw_framer_t framer, size_t minimum_incomplete_length, size_t maximum_length, uint8_t * _Nullable temp_buffer, nw_framer_parse_completion_t parse_completion) {
    NSLog(@"STUB: nw_framer_parse_output");
}

void nw_framer_write_output_data(nw_framer_t framer, dispatch_data_t data) {
    NSLog(@"STUB: nw_framer_write_output_data");
}

void nw_framer_deliver_input(nw_framer_t framer, const void *input_buffer, size_t input_length, nw_framer_message_t message, bool is_complete) {
    NSLog(@"STUB: nw_framer_deliver_input");
}

nw_framer_message_t nw_framer_message_create(nw_framer_t framer) {
    NSLog(@"STUB: nw_framer_message_create");
    return NULL;
}

void nw_framer_message_set_object_value(nw_framer_message_t message, const char *key, id _Nullable value) {
    NSLog(@"STUB: nw_framer_message_set_object_value(%s)", key);
}

id _Nullable nw_framer_message_copy_object_value(nw_framer_message_t message, const char *key) {
    NSLog(@"STUB: nw_framer_message_copy_object_value(%s)", key);
    return NULL;
}

nw_protocol_metadata_t nw_content_context_copy_protocol_metadata(nw_content_context_t context, nw_protocol_definition_t definition) {
    NSLog(@"STUB: nw_content_context_copy_protocol_metadata");
    return NULL;
}

void nw_tcp_options_set_no_delay(nw_protocol_options_t options, bool no_delay) {
    NSLog(@"STUB: nw_tcp_options_set_no_delay");
}

nw_listener_t nw_listener_create(nw_parameters_t parameters) {
    NSLog(@"STUB: nw_listener_create");
    return NULL;
}

void nw_listener_set_queue(nw_listener_t listener, dispatch_queue_t queue) {
    NSLog(@"STUB: nw_listener_set_queue");
}

void nw_listener_set_state_changed_handler(nw_listener_t listener, nw_listener_state_changed_handler_t handler) {
    NSLog(@"STUB: nw_listener_set_state_changed_handler");
}

void nw_listener_set_new_connection_handler(nw_listener_t listener, nw_listener_new_connection_handler_t handler) {
    NSLog(@"STUB: nw_listener_set_new_connection_handler");
}

void nw_listener_start(nw_listener_t listener) {
    NSLog(@"STUB: nw_listener_start");
}

void nw_listener_cancel(nw_listener_t listener) {
    NSLog(@"STUB: nw_listener_cancel");
}

uint16_t nw_listener_get_port(nw_listener_t listener) {
    NSLog(@"STUB: nw_listener_get_port");
    return 0;
}

#endif
