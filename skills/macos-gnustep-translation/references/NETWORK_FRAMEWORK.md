# Network.framework Compatibility

## Overview

**Apple's Network.framework is NOT available on Linux.** The Scuttle codebase uses Network.framework extensively for TCP/TLS connections and custom protocol framers.

**Current Status:** All functions are stubs that log "STUB" messages. Real socket-based implementation is needed for networking.

## Shim Files

| File | Purpose |
|------|---------|
| `Sources/SSBNetworkCompat.h` | Type definitions and function declarations |
| `Sources/SSBNetworkShim.m` | Stub implementations |

## Compatibility Header (SSBNetworkCompat.h)

**Location:** `Sources/SSBNetworkCompat.h`

```objc
#ifdef __APPLE__
    #import <Network/Network.h>
#else
    // Types and function declarations for Linux
    #import "SSBNetworkCompat.h"
#endif
```

### Types Defined

```objc
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
```

### Block Types

```objc
typedef void (^nw_connection_state_changed_handler_t)(nw_connection_state_t state, nw_error_t _Nullable error);
typedef void (^nw_connection_receive_completion_t)(dispatch_data_t _Nullable content, nw_content_context_t _Nullable context, bool is_complete, nw_error_t _Nullable error);
typedef void (^nw_connection_send_completion_t)(nw_error_t _Nullable error);
```

## Stubs (SSBNetworkShim.m)

**Location:** `Sources/SSBNetworkShim.m`

All functions currently log "STUB" and return NULL/no-op:

```objc
nw_endpoint_t nw_endpoint_create_host(const char *hostname, const char *port) {
    NSLog(@"STUB: nw_endpoint_create_host(%s, %s)", hostname, port);
    return NULL;
}

void nw_connection_set_state_changed_handler(nw_connection_t connection, nw_connection_state_changed_handler_t handler) {
    NSLog(@"STUB: nw_connection_set_state_changed_handler");
}
```

## Functions Currently Stubbed

### nw_endpoint_* (1 function)

| Function | Stub Status |
|----------|-------------|
| `nw_endpoint_create_host` | ✅ Logged |

### nw_parameters_* (4 functions)

| Function | Stub Status |
|----------|-------------|
| `nw_parameters_create_secure_tcp` | ✅ Logged |
| `nw_parameters_copy_default_protocol_stack` | ✅ Logged |
| `nw_protocol_stack_prepend_application_protocol` | ✅ Logged |
| `nw_parameters_set_local_endpoint` | ❌ Missing |

### nw_connection_* (9 functions)

| Function | Stub Status |
|----------|-------------|
| `nw_connection_create` | ✅ Logged |
| `nw_connection_set_queue` | ✅ Logged |
| `nw_connection_set_state_changed_handler` | ✅ Logged |
| `nw_connection_start` | ✅ Logged |
| `nw_connection_receive_message` | ✅ Logged |
| `nw_connection_receive` | ❌ Missing |
| `nw_connection_send` | ✅ Logged |
| `nw_connection_cancel` | ✅ Logged |

### nw_listener_* (6 functions)

| Function | Stub Status |
|----------|-------------|
| `nw_listener_create` | ❌ Missing |
| `nw_listener_set_queue` | ❌ Missing |
| `nw_listener_set_state_changed_handler` | ❌ Missing |
| `nw_listener_set_new_connection_handler` | ❌ Missing |
| `nw_listener_start` | ❌ Missing |
| `nw_listener_get_port` | ❌ Missing |
| `nw_listener_cancel` | ❌ Missing |

### nw_framer_* (14 functions)

| Function | Stub Status |
|----------|-------------|
| `nw_framer_create_definition` | ✅ Logged |
| `nw_framer_create_options` | ✅ Logged |
| `nw_framer_copy_options` | ✅ Logged |
| `nw_framer_options_set_object_value` | ✅ Logged |
| `nw_framer_options_copy_object_value` | ✅ Logged |
| `nw_framer_set_input_handler` | ✅ Logged |
| `nw_framer_set_output_handler` | ✅ Logged |
| `nw_framer_mark_ready` | ✅ Logged |
| `nw_framer_mark_failed_with_error` | ✅ Logged |
| `nw_framer_parse_input` | ✅ Logged |
| `nw_framer_parse_output` | ✅ Logged |
| `nw_framer_write_output_data` | ✅ Logged |
| `nw_framer_deliver_input` | ✅ Logged |
| `nw_framer_message_create` | ✅ Logged |
| `nw_framer_message_set_object_value` | ✅ Logged |
| `nw_framer_message_copy_object_value` | ✅ Logged |

## Missing Implementation Priority

### HIGH Priority (Required for Basic Networking)

1. **`nw_connection_create`** - Socket-based connection
2. **`nw_connection_start`** - Initiate connection
3. **`nw_connection_receive`** - Receive data
4. **`nw_connection_send`** - Send data
5. **`nw_connection_cancel`** - Close connection

### HIGH Priority (Listeners)

1. **`nw_listener_create`** - Create server socket
2. **`nw_listener_start`** - Bind and listen
3. **`nw_listener_set_new_connection_handler`** - Accept connections

### MEDIUM Priority (Protocol Stack)

1. **`nw_endpoint_create_host`** - Address resolution
2. **`nw_parameters_create_secure_tcp`** - TLS configuration

### LOW Priority (Custom Framers)

1. All `nw_framer_*` functions - Custom protocol parsing

## Socket-Based Alternative

For Linux, use BSD sockets directly:

```objc
#ifndef __APPLE__
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

@interface SSBSocketConnection : NSObject
@property (nonatomic, assign) int socket_fd;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) void (^stateHandler)(nw_connection_state_t state, nw_error_t error);
@property (nonatomic, copy) void (^receiveHandler)(dispatch_data_t data, bool complete);
// ... implementation using BSD sockets
@end
#endif
```

## Usage in Scuttle

### SSBRoomClient.m

```objc
// macOS: Uses Network.framework
#ifdef __APPLE__
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    nw_connection_set_queue(connection, self.clientQueue);
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        // Handle state changes
    });
    nw_connection_start(connection);
#else
    // Linux: Would need socket-based implementation
    NSLog(@"Network connection not available on Linux");
#endif
```

### SSBTunnelConnection.m

```objc
// Listener pattern
#ifdef __APPLE__
    nw_listener_t listener = nw_listener_create(parameters);
    nw_listener_set_queue(listener, queue);
    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        // Accept new connection
    });
    nw_listener_start(listener);
#else
    // Linux: Would need socket-based server
#endif
```

## Future Work

To enable real networking on Linux:

1. Create `SSBSocketConnection` class wrapping BSD sockets
2. Implement `nw_connection_*` functions using the wrapper
3. Create `SSBSocketListener` class wrapping `listen()`/`accept()`
4. Implement `nw_listener_*` functions using the listener
5. Consider TLS support via OpenSSL

## Summary

| Component | macOS | Linux | Status |
|-----------|-------|-------|--------|
| TCP Connections | Network.framework | BSD Sockets | ❌ Not implemented |
| TLS | Network.framework | OpenSSL | ❌ Not implemented |
| Custom Framers | nw_framer_* | N/A | ❌ Stubs only |
| DNS Resolution | nw_endpoint | getaddrinfo | ❌ Not implemented |

**Recommendation:** Implement socket-based networking layer for Linux to enable real peer-to-peer communication.
