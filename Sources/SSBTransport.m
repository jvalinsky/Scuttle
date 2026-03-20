#import "SSBTransport.h"
#import "SSBNetworkCompat.h"
#import "SSBSecurityFramer.h"
#import "SSBMuxRPCFramer.h"

NSString * const SSBTransportMetadataFlagsKey = @"Flags";
NSString * const SSBTransportMetadataRequestNumberKey = @"RequestNumber";

static NSError * _Nullable SSBTransportNSErrorFromNWError(nw_error_t error) {
    if (!error) {
        return nil;
    }

    id candidate = error;
    if ([candidate isKindOfClass:[NSError class]]) {
        return (NSError *)candidate;
    }

    return [NSError errorWithDomain:@"SSBTransport"
                               code:1
                           userInfo:@{
                               NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@", candidate ?: @"Unknown transport error"],
                           }];
}

static SSBTransportConnectionState SSBTransportConnectionStateFromNWState(nw_connection_state_t state) {
    switch (state) {
        case nw_connection_state_waiting:
            return SSBTransportConnectionStateWaiting;
        case nw_connection_state_preparing:
            return SSBTransportConnectionStatePreparing;
        case nw_connection_state_ready:
            return SSBTransportConnectionStateReady;
        case nw_connection_state_failed:
            return SSBTransportConnectionStateFailed;
        case nw_connection_state_cancelled:
            return SSBTransportConnectionStateCancelled;
        case nw_connection_state_invalid:
        default:
            return SSBTransportConnectionStateInvalid;
    }
}

static SSBTransportListenerState SSBTransportListenerStateFromNWState(nw_listener_state_t state) {
    switch (state) {
        case nw_listener_state_waiting:
            return SSBTransportListenerStateWaiting;
        case nw_listener_state_ready:
            return SSBTransportListenerStateReady;
        case nw_listener_state_failed:
            return SSBTransportListenerStateFailed;
        case nw_listener_state_cancelled:
            return SSBTransportListenerStateCancelled;
        case nw_listener_state_invalid:
        default:
            return SSBTransportListenerStateInvalid;
    }
}

static NSData * _Nullable SSBTransportNSDataFromDispatchData(dispatch_data_t content) {
    if (!content) {
        return nil;
    }

    const void *buffer = NULL;
    size_t size = 0;
    dispatch_data_t contiguous = dispatch_data_create_map(content, &buffer, &size);
    NSData *data = [NSData dataWithBytes:buffer length:size];
    (void)contiguous;
    return data;
}

@interface SSBTransportEndpoint ()
@property (nonatomic, copy, readwrite) NSString *host;
@property (nonatomic, assign, readwrite) uint16_t port;
@end

@implementation SSBTransportEndpoint

+ (instancetype)endpointWithHost:(NSString *)host port:(uint16_t)port {
    return [[self alloc] initWithHost:host port:port];
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
    }
    return self;
}

@end

@implementation SSBTransportConnectionOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _enableTCPNoDelay = YES;
        _actingAsClient = YES;
    }
    return self;
}

@end

@interface SSBNativeTransportConnection : NSObject <SSBTransportConnection>

- (instancetype)initWithConnection:(nw_connection_t)connection
                           endpoint:(nullable SSBTransportEndpoint *)endpoint
                             options:(nullable SSBTransportConnectionOptions *)options
                               queue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SSBNativeTransportConnection ()
@property (nonatomic, strong) nw_connection_t nativeConnection;
@property (nonatomic, strong, readwrite, nullable) SSBTransportEndpoint *endpoint;
@property (nonatomic, strong) SSBTransportConnectionOptions *options;
@property (nonatomic, assign, readwrite) SSBTransportConnectionState state;
@property (nonatomic, copy, nullable) SSBTransportConnectionStateHandler stateHandler;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SSBNativeTransportConnection

- (instancetype)initWithConnection:(nw_connection_t)connection
                           endpoint:(nullable SSBTransportEndpoint *)endpoint
                             options:(nullable SSBTransportConnectionOptions *)options
                               queue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _nativeConnection = connection;
        _endpoint = endpoint;
        _options = options ?: [[SSBTransportConnectionOptions alloc] init];
        _queue = queue;
        _state = SSBTransportConnectionStateInvalid;
        nw_connection_set_queue(_nativeConnection, queue);
    }
    return self;
}

- (void)setStateChangedHandler:(SSBTransportConnectionStateHandler)handler {
    self.stateHandler = handler;

    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(self.nativeConnection, ^(nw_connection_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = SSBTransportConnectionStateFromNWState(state);
        if (strongSelf.stateHandler) {
            strongSelf.stateHandler(strongSelf, strongSelf.state, SSBTransportNSErrorFromNWError(error));
        }
    });
}

- (void)start {
    nw_connection_start(self.nativeConnection);
}

- (void)cancel {
    nw_connection_cancel(self.nativeConnection);
}

- (NSDictionary<NSString *, id> * _Nullable)metadataFromContentContext:(nw_content_context_t)context {
    if (!self.options.enableMuxRPCFramer || !context) {
        return nil;
    }

    nw_protocol_metadata_t metadata = nw_content_context_copy_protocol_metadata(context, [SSBMuxRPCFramer createDefinition]);
    if (!metadata) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionaryWithCapacity:2];
    id flags = nw_framer_message_copy_object_value((nw_framer_message_t)metadata, SSBTransportMetadataFlagsKey.UTF8String);
    if (flags) {
        result[SSBTransportMetadataFlagsKey] = flags;
    }
    id requestNumber = nw_framer_message_copy_object_value((nw_framer_message_t)metadata, SSBTransportMetadataRequestNumberKey.UTF8String);
    if (requestNumber) {
        result[SSBTransportMetadataRequestNumberKey] = requestNumber;
    }
    return result.count > 0 ? [result copy] : nil;
}

- (void)receiveMessageWithCompletion:(SSBTransportConnectionReceiveHandler)completion {
    nw_connection_receive_message(self.nativeConnection, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        completion(SSBTransportNSDataFromDispatchData(content),
                   [self metadataFromContentContext:context],
                   is_complete,
                   SSBTransportNSErrorFromNWError(error));
    });
}

- (void)receiveMinimumLength:(uint32_t)minimumLength
               maximumLength:(uint32_t)maximumLength
                  completion:(SSBTransportConnectionReceiveHandler)completion {
    nw_connection_receive(self.nativeConnection, minimumLength, maximumLength, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        completion(SSBTransportNSDataFromDispatchData(content),
                   [self metadataFromContentContext:context],
                   is_complete,
                   SSBTransportNSErrorFromNWError(error));
    });
}

- (void)sendData:(NSData *)data
      isComplete:(BOOL)isComplete
      completion:(SSBTransportConnectionSendHandler)completion {
    dispatch_data_t body = dispatch_data_create(data.bytes, data.length, self.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    nw_connection_send(self.nativeConnection, body, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, isComplete, ^(nw_error_t error) {
        if (completion) {
            completion(SSBTransportNSErrorFromNWError(error));
        }
    });
}

@end

@interface SSBNativeTransportListener : NSObject <SSBTransportListener>

- (instancetype)initWithListener:(nw_listener_t)listener
                         backend:(id<SSBTransportBackend>)backend
                           queue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SSBNativeTransportListener ()
@property (nonatomic, strong) nw_listener_t nativeListener;
@property (nonatomic, strong) id<SSBTransportBackend> backend;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign, readwrite) SSBTransportListenerState state;
@property (nonatomic, assign, readwrite) uint16_t port;
@property (nonatomic, copy, nullable) SSBTransportListenerStateHandler stateHandler;
@property (nonatomic, copy, nullable) SSBTransportListenerNewConnectionHandler storedNewConnectionHandler;
@end

@implementation SSBNativeTransportListener

- (instancetype)initWithListener:(nw_listener_t)listener
                         backend:(id<SSBTransportBackend>)backend
                           queue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _nativeListener = listener;
        _backend = backend;
        _queue = queue;
        _state = SSBTransportListenerStateInvalid;
        nw_listener_set_queue(_nativeListener, queue);
    }
    return self;
}

- (void)setStateChangedHandler:(SSBTransportListenerStateHandler)handler {
    self.stateHandler = handler;

    __weak typeof(self) weakSelf = self;
    nw_listener_set_state_changed_handler(self.nativeListener, ^(nw_listener_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = SSBTransportListenerStateFromNWState(state);
        if (strongSelf.state == SSBTransportListenerStateReady) {
            strongSelf.port = nw_listener_get_port(strongSelf.nativeListener);
        }
        if (strongSelf.stateHandler) {
            strongSelf.stateHandler(strongSelf, strongSelf.state, SSBTransportNSErrorFromNWError(error));
        }
    });
}

- (void)setNewConnectionHandler:(SSBTransportListenerNewConnectionHandler)handler {
    self.storedNewConnectionHandler = handler;

    __weak typeof(self) weakSelf = self;
    nw_listener_set_new_connection_handler(self.nativeListener, ^(nw_connection_t connection) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.storedNewConnectionHandler) {
            return;
        }

        id<SSBTransportConnection> adopted = [strongSelf.backend adoptConnection:connection queue:strongSelf.queue];
        strongSelf.storedNewConnectionHandler(adopted);
    });
}

- (void)start {
    nw_listener_start(self.nativeListener);
}

- (void)cancel {
    nw_listener_cancel(self.nativeListener);
}

@end

@interface SSBNativeTransportBackend : NSObject <SSBTransportBackend>
@end

@implementation SSBNativeTransportBackend

- (nw_parameters_t)parametersForOptions:(nullable SSBTransportConnectionOptions *)options {
    SSBTransportConnectionOptions *resolvedOptions = options ?: [[SSBTransportConnectionOptions alloc] init];
    nw_parameters_configure_protocol_block_t configureTCP = ^(nw_protocol_options_t tcpOptions) {
        if (resolvedOptions.enableTCPNoDelay) {
            nw_tcp_options_set_no_delay(tcpOptions, true);
        }
    };

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, configureTCP);
    nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(parameters);

    if (resolvedOptions.enableSecurityFramer) {
        nw_protocol_options_t securityOptions = [SSBSecurityFramer createOptionsWithLocalSecretKey:resolvedOptions.localIdentitySecret
                                                                                   remotePublicKey:resolvedOptions.remotePublicKey
                                                                                          asClient:resolvedOptions.actingAsClient];
        nw_protocol_stack_prepend_application_protocol(stack, securityOptions);
    }

    if (resolvedOptions.enableMuxRPCFramer) {
        nw_protocol_stack_prepend_application_protocol(stack, [SSBMuxRPCFramer createOptions]);
    }

    return parameters;
}

- (id<SSBTransportConnection>)connectionToEndpoint:(SSBTransportEndpoint *)endpoint
                                           options:(nullable SSBTransportConnectionOptions *)options
                                             queue:(dispatch_queue_t)queue {
    NSString *portString = [NSString stringWithFormat:@"%u", endpoint.port];
    nw_endpoint_t nativeEndpoint = nw_endpoint_create_host(endpoint.host.UTF8String, portString.UTF8String);
    nw_parameters_t parameters = [self parametersForOptions:options];
    nw_connection_t connection = nw_connection_create(nativeEndpoint, parameters);
    return [[SSBNativeTransportConnection alloc] initWithConnection:connection endpoint:endpoint options:options queue:queue];
}

- (id<SSBTransportConnection>)adoptConnection:(id)nativeConnection
                                        queue:(dispatch_queue_t)queue {
    return [[SSBNativeTransportConnection alloc] initWithConnection:(nw_connection_t)nativeConnection endpoint:nil options:nil queue:queue];
}

- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                         queue:(dispatch_queue_t)queue {
    nw_parameters_t parameters = [self parametersForOptions:nil];
    nw_endpoint_t localEndpoint = nw_endpoint_create_host(endpoint.host.UTF8String,
                                                          [[NSString stringWithFormat:@"%u", endpoint.port] UTF8String]);
    nw_parameters_set_local_endpoint(parameters, localEndpoint);
    nw_listener_t listener = nw_listener_create(parameters);
    return [[SSBNativeTransportListener alloc] initWithListener:listener backend:self queue:queue];
}

@end

@interface SSBAppleTransportBackend ()
@property (nonatomic, strong) SSBNativeTransportBackend *nativeBackend;
@end

@implementation SSBTransport

+ (id<SSBTransportBackend>)defaultBackend {
    static id<SSBTransportBackend> backend = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#ifdef __APPLE__
        backend = [[SSBAppleTransportBackend alloc] init];
#else
        backend = [[SSBLinuxTransportBackend alloc] init];
#endif
    });
    return backend;
}

@end

@implementation SSBAppleTransportBackend

- (instancetype)init {
    self = [super init];
    if (self) {
        _nativeBackend = [[SSBNativeTransportBackend alloc] init];
    }
    return self;
}

- (id<SSBTransportConnection>)connectionToEndpoint:(SSBTransportEndpoint *)endpoint
                                           options:(SSBTransportConnectionOptions *)options
                                             queue:(dispatch_queue_t)queue {
    return [self.nativeBackend connectionToEndpoint:endpoint options:options queue:queue];
}

- (id<SSBTransportConnection>)adoptConnection:(id)nativeConnection
                                        queue:(dispatch_queue_t)queue {
    return [self.nativeBackend adoptConnection:nativeConnection queue:queue];
}

- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                         queue:(dispatch_queue_t)queue {
    return [self.nativeBackend listenerOnEndpoint:endpoint queue:queue];
}

@end

@interface SSBLinuxTransportBackend ()
@property (nonatomic, strong) SSBNativeTransportBackend *nativeBackend;
@end

@implementation SSBLinuxTransportBackend

- (instancetype)init {
    self = [super init];
    if (self) {
        _nativeBackend = [[SSBNativeTransportBackend alloc] init];
    }
    return self;
}

- (id<SSBTransportConnection>)connectionToEndpoint:(SSBTransportEndpoint *)endpoint
                                           options:(SSBTransportConnectionOptions *)options
                                             queue:(dispatch_queue_t)queue {
    return [self.nativeBackend connectionToEndpoint:endpoint options:options queue:queue];
}

- (id<SSBTransportConnection>)adoptConnection:(id)nativeConnection
                                        queue:(dispatch_queue_t)queue {
    return [self.nativeBackend adoptConnection:nativeConnection queue:queue];
}

- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                         queue:(dispatch_queue_t)queue {
    return [self.nativeBackend listenerOnEndpoint:endpoint queue:queue];
}

@end
