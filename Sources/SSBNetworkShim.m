#import "SSBNetworkCompat.h"

#import <sys/socket.h>
#import <sys/types.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <string.h>

#ifndef __APPLE__

#pragma mark - Helpers

static dispatch_queue_t SSBNWShimDefaultQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.scuttlebutt.network.shim", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSData *SSBNWNSDataFromDispatchData(dispatch_data_t data) {
    if (!data) {
        return [NSData data];
    }

    const void *bytes = NULL;
    size_t length = 0;
    dispatch_data_t contiguous = dispatch_data_create_map(data, &bytes, &length);
    (void)contiguous;
    return [NSData dataWithBytes:bytes length:length];
}

static dispatch_data_t SSBNWDispatchDataFromNSData(NSData *data, dispatch_queue_t queue) {
    if (!data) {
        return NULL;
    }

    return dispatch_data_create(data.bytes, data.length, queue ?: SSBNWShimDefaultQueue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
}

static NSError *SSBNWPOSIXError(NSString *description, int code) {
    int resolved = (code == 0) ? EINVAL : code;
    NSString *desc = description;
    if (desc.length == 0) {
        desc = [NSString stringWithUTF8String:strerror(resolved)] ?: @"POSIX error";
    }

    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:resolved
                           userInfo:@{ NSLocalizedDescriptionKey: desc }];
}

static NSString *SSBNWStringFromCKey(const char *key) {
    if (!key) {
        return nil;
    }
    return [NSString stringWithUTF8String:key];
}

#pragma mark - Runtime Classes

@class SSBNWConnection;
@class SSBNWFramerOptions;
@class SSBNWFramerInstance;
@class SSBNWFramerMessage;

@interface SSBNWEndpoint : NSObject
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, copy) NSString *port;
@property (nonatomic, assign) struct sockaddr_storage resolvedAddr;
@property (nonatomic, assign) socklen_t resolvedAddrLen;
@property (nonatomic, assign) int socketFamily;
- (instancetype)initWithHostname:(NSString *)hostname port:(NSString *)port;
- (BOOL)resolvedAddress:(struct sockaddr_storage *)storage length:(socklen_t *)length;
@end

@implementation SSBNWEndpoint

- (instancetype)initWithHostname:(NSString *)hostname port:(NSString *)port {
    self = [super init];
    if (self) {
        _hostname = [hostname copy] ?: @"127.0.0.1";
        _port = [port copy] ?: @"0";
        _socketFamily = AF_INET;
        _resolvedAddrLen = 0;
    }
    return self;
}

- (BOOL)resolveIfNeeded {
    if (self.resolvedAddrLen > 0) {
        return YES;
    }

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *results = NULL;
    int rc = getaddrinfo(self.hostname.UTF8String, self.port.UTF8String, &hints, &results);
    if (rc != 0 || !results) {
        return NO;
    }

    memcpy(&_resolvedAddr, results->ai_addr, results->ai_addrlen);
    _resolvedAddrLen = (socklen_t)results->ai_addrlen;
    _socketFamily = results->ai_family;
    freeaddrinfo(results);
    return YES;
}

- (BOOL)resolvedAddress:(struct sockaddr_storage *)storage length:(socklen_t *)length {
    if (![self resolveIfNeeded]) {
        return NO;
    }

    if (storage) {
        memcpy(storage, &_resolvedAddr, _resolvedAddrLen);
    }
    if (length) {
        *length = _resolvedAddrLen;
    }
    return YES;
}

@end

@interface SSBNWTCPOptions : NSObject
@property (nonatomic, assign) BOOL noDelay;
@end

@implementation SSBNWTCPOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _noDelay = YES;
    }
    return self;
}

@end

@interface SSBNWFramerDefinition : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, copy) nw_framer_start_handler_t startHandler;
- (instancetype)initWithIdentifier:(NSString *)identifier
                             flags:(uint32_t)flags
                      startHandler:(nw_framer_start_handler_t)startHandler;
@end

@implementation SSBNWFramerDefinition

- (instancetype)initWithIdentifier:(NSString *)identifier
                             flags:(uint32_t)flags
                      startHandler:(nw_framer_start_handler_t)startHandler {
    self = [super init];
    if (self) {
        _identifier = [identifier copy] ?: @"";
        _flags = flags;
        _startHandler = [startHandler copy];
    }
    return self;
}

@end

@interface SSBNWFramerOptions : NSObject
@property (nonatomic, strong) SSBNWFramerDefinition *definition;
@property (nonatomic, strong) NSMutableDictionary *values;
- (instancetype)initWithDefinition:(SSBNWFramerDefinition *)definition;
- (SSBNWFramerOptions *)copyForConnection;
@end

@implementation SSBNWFramerOptions

- (instancetype)initWithDefinition:(SSBNWFramerDefinition *)definition {
    self = [super init];
    if (self) {
        _definition = definition;
        _values = [NSMutableDictionary dictionary];
    }
    return self;
}

- (SSBNWFramerOptions *)copyForConnection {
    SSBNWFramerOptions *copy = [[SSBNWFramerOptions alloc] initWithDefinition:self.definition];
    [copy.values addEntriesFromDictionary:self.values];
    return copy;
}

@end

@interface SSBNWProtocolStack : NSObject
@property (nonatomic, assign) id parameters;
@end

@implementation SSBNWProtocolStack
@end

@interface SSBNWParameters : NSObject
@property (nonatomic, copy) nw_parameters_configure_protocol_block_t configureTLS;
@property (nonatomic, copy) nw_parameters_configure_protocol_block_t configureTCP;
@property (nonatomic, strong) SSBNWTCPOptions *tcpOptions;
@property (nonatomic, strong) NSMutableArray *applicationProtocols;
@property (nonatomic, strong) SSBNWProtocolStack *protocolStack;
@property (nonatomic, strong) SSBNWEndpoint *localEndpoint;
@end

@implementation SSBNWParameters

- (instancetype)init {
    self = [super init];
    if (self) {
        _tcpOptions = [[SSBNWTCPOptions alloc] init];
        _applicationProtocols = [NSMutableArray array];
        _protocolStack = [[SSBNWProtocolStack alloc] init];
        _protocolStack.parameters = self;
    }
    return self;
}

@end

@interface SSBNWContentContext : NSObject
@property (nonatomic, strong) NSMutableDictionary *metadataByDefinitionIdentifier;
- (void)setMetadata:(id)metadata forDefinitionIdentifier:(NSString *)identifier;
- (id)metadataForDefinitionIdentifier:(NSString *)identifier;
@end

@implementation SSBNWContentContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _metadataByDefinitionIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setMetadata:(id)metadata forDefinitionIdentifier:(NSString *)identifier {
    if (!identifier || !metadata) {
        return;
    }
    [self.metadataByDefinitionIdentifier setObject:metadata forKey:identifier];
}

- (id)metadataForDefinitionIdentifier:(NSString *)identifier {
    if (!identifier) {
        return nil;
    }
    return [self.metadataByDefinitionIdentifier objectForKey:identifier];
}

@end

@interface SSBNWFramerMessage : NSObject
@property (nonatomic, strong) NSMutableDictionary *values;
@property (nonatomic, strong) NSData *payloadData;
@end

@implementation SSBNWFramerMessage

- (instancetype)init {
    self = [super init];
    if (self) {
        _values = [NSMutableDictionary dictionary];
    }
    return self;
}

@end

@interface SSBNWDeliveredMessage : NSObject
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) SSBNWContentContext *context;
@property (nonatomic, assign) BOOL isComplete;
@end

@implementation SSBNWDeliveredMessage
@end

@interface SSBNWPendingReceive : NSObject
@property (nonatomic, assign) uint32_t minimumLength;
@property (nonatomic, assign) uint32_t maximumLength;
@property (nonatomic, assign) BOOL messageMode;
@property (nonatomic, copy) nw_connection_receive_completion_t completion;
@end

@implementation SSBNWPendingReceive
@end

@interface SSBNWPendingSend : NSObject
@property (nonatomic, strong) NSData *payload;
@property (nonatomic, strong) id context;
@property (nonatomic, assign) BOOL isComplete;
@property (nonatomic, copy) nw_connection_send_completion_t completion;
@end

@implementation SSBNWPendingSend
@end

@interface SSBNWSendChunk : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) NSUInteger offset;
@end

@implementation SSBNWSendChunk
@end

@interface SSBNWFramerInstance : NSObject
@property (nonatomic, strong) SSBNWFramerDefinition *definition;
@property (nonatomic, strong) SSBNWFramerOptions *options;
@property (nonatomic, assign) SSBNWConnection *connection;
@property (nonatomic, assign) SSBNWFramerInstance *upper;
@property (nonatomic, assign) SSBNWFramerInstance *lower;
@property (nonatomic, strong) NSMutableData *inboundSourceBuffer;
@property (nonatomic, copy) nw_framer_input_handler_t inputHandler;
@property (nonatomic, copy) nw_framer_output_handler_t outputHandler;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL startInvoked;
@property (nonatomic, strong) NSData *activeOutputData;
@property (nonatomic, assign) NSUInteger activeOutputOffset;
@property (nonatomic, strong) SSBNWFramerMessage *activeOutputMessage;
@property (nonatomic, assign) BOOL activeOutputComplete;
@end

@implementation SSBNWFramerInstance
@end

@interface SSBNWConnection : NSObject {
    dispatch_queue_t _queue;
    dispatch_source_t _connectSource;
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
}
@property (nonatomic, strong) SSBNWEndpoint *endpoint;
@property (nonatomic, strong) SSBNWParameters *parameters;
@property (nonatomic, assign) int sockfd;
@property (nonatomic, assign) BOOL socketIsAdopted;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL stackBuilt;
@property (nonatomic, copy) nw_connection_state_changed_handler_t stateHandler;
@property (nonatomic, assign) nw_connection_state_t state;
@property (nonatomic, strong) NSError *terminalError;
@property (nonatomic, strong) NSMutableData *socketReadBuffer;
@property (nonatomic, strong) NSMutableArray *writeQueue;
@property (nonatomic, strong) NSMutableArray *deliveredQueue;
@property (nonatomic, strong) NSMutableArray *pendingReceives;
@property (nonatomic, strong) NSMutableArray *pendingSends;
@property (nonatomic, strong) NSArray *framerStackTopToBottom;
@property (nonatomic, strong) NSArray *framerStackBottomToTop;
@property (nonatomic, strong) SSBNWFramerInstance *topFramer;
@property (nonatomic, strong) SSBNWFramerInstance *bottomFramer;
- (instancetype)initOutboundWithEndpoint:(SSBNWEndpoint *)endpoint parameters:(SSBNWParameters *)parameters;
- (instancetype)initAdoptedSocket:(int)sockfd endpoint:(SSBNWEndpoint *)endpoint parameters:(SSBNWParameters *)parameters;
- (dispatch_queue_t)queue;
- (void)setQueue:(dispatch_queue_t)queue;
- (void)setState:(nw_connection_state_t)state error:(nw_error_t)error;
- (void)start;
- (void)cancel;
- (void)failWithError:(NSError *)error;
- (void)buildFramerStackIfNeeded;
- (void)startFramersIfNeeded;
- (void)armReadSource;
- (void)armConnectSource;
- (void)armWriteSourceIfNeeded;
- (void)drainSocketWrites;
- (void)readFromSocket;
- (void)pumpInboundFramers;
- (void)enqueueDeliveredData:(NSData *)data context:(SSBNWContentContext *)context isComplete:(BOOL)isComplete;
- (void)drainPendingReceives;
- (void)enqueueReceiveWithMinimumLength:(uint32_t)minimumLength
                          maximumLength:(uint32_t)maximumLength
                            messageMode:(BOOL)messageMode
                             completion:(nw_connection_receive_completion_t)completion;
- (void)enqueueSocketWriteData:(NSData *)data;
- (BOOL)allFramersReady;
- (void)promoteReadyIfPossible;
- (void)failPendingSendsWithError:(NSError *)error;
- (void)flushPendingSends;
- (void)sendData:(NSData *)payload
         context:(nw_content_context_t)context
      isComplete:(BOOL)isComplete
      completion:(nw_connection_send_completion_t)completion;
- (void)routeOutboundData:(NSData *)data
               fromFramer:(SSBNWFramerInstance *)framer
                  message:(SSBNWFramerMessage *)message
               isComplete:(BOOL)isComplete;
@end

@implementation SSBNWConnection

- (instancetype)initOutboundWithEndpoint:(SSBNWEndpoint *)endpoint parameters:(SSBNWParameters *)parameters {
    self = [super init];
    if (self) {
        _endpoint = endpoint;
        _parameters = parameters ?: [[SSBNWParameters alloc] init];
        _sockfd = -1;
        _socketIsAdopted = NO;
        _started = NO;
        _stackBuilt = NO;
        _state = nw_connection_state_invalid;
        _socketReadBuffer = [NSMutableData data];
        _writeQueue = [NSMutableArray array];
        _deliveredQueue = [NSMutableArray array];
        _pendingReceives = [NSMutableArray array];
        _pendingSends = [NSMutableArray array];
        _queue = SSBNWShimDefaultQueue();
    }
    return self;
}

- (instancetype)initAdoptedSocket:(int)sockfd endpoint:(SSBNWEndpoint *)endpoint parameters:(SSBNWParameters *)parameters {
    self = [self initOutboundWithEndpoint:endpoint parameters:parameters];
    if (self) {
        _sockfd = sockfd;
        _socketIsAdopted = YES;
    }
    return self;
}

- (void)dealloc {
    [self cancel];
}

- (dispatch_queue_t)queue {
    return _queue;
}

- (void)setQueue:(dispatch_queue_t)queue {
    if (queue) {
        _queue = queue;
    }
}

- (void)cleanupSourcesAndSocket {
    if (_connectSource) {
        dispatch_source_cancel(_connectSource);
        _connectSource = nil;
    }
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    if (_writeSource) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
    }
    if (_sockfd >= 0) {
        close(_sockfd);
        _sockfd = -1;
    }
}

- (void)failPendingReceivesWithError:(NSError *)error {
    while (self.pendingReceives.count > 0) {
        SSBNWPendingReceive *pending = [self.pendingReceives objectAtIndex:0];
        [self.pendingReceives removeObjectAtIndex:0];
        if (pending.completion) {
            pending.completion(NULL, NULL, false, error);
        }
    }
}

- (void)failPendingSendsWithError:(NSError *)error {
    while (self.pendingSends.count > 0) {
        SSBNWPendingSend *pending = [self.pendingSends objectAtIndex:0];
        [self.pendingSends removeObjectAtIndex:0];
        if (pending.completion) {
            pending.completion(error);
        }
    }
}

- (void)setState:(nw_connection_state_t)state error:(nw_error_t)error {
    if (_state == state) {
        return;
    }
    _state = state;
    if (_stateHandler) {
        _stateHandler(state, error);
    }
}

- (BOOL)ensureSocketCreated {
    if (self.sockfd >= 0) {
        return YES;
    }

    int family = AF_INET;
    if (self.endpoint) {
        struct sockaddr_storage addr;
        socklen_t len = 0;
        if (![self.endpoint resolvedAddress:&addr length:&len]) {
            return NO;
        }
        family = addr.ss_family;
    }

    int sock = socket(family, SOCK_STREAM, 0);
    if (sock < 0) {
        return NO;
    }

    int flags = fcntl(sock, F_GETFL, 0);
    if (flags < 0) {
        close(sock);
        return NO;
    }
    if (fcntl(sock, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(sock);
        return NO;
    }

    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    self.sockfd = sock;
    return YES;
}

- (BOOL)applySocketOptions {
    if (self.sockfd < 0) {
        return NO;
    }

    if (self.parameters.tcpOptions.noDelay) {
        int one = 1;
        setsockopt(self.sockfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }

    return YES;
}

- (BOOL)bindLocalEndpointIfNeeded {
    SSBNWEndpoint *local = self.parameters.localEndpoint;
    if (!local) {
        return YES;
    }

    struct sockaddr_storage addr;
    socklen_t len = 0;
    if (![local resolvedAddress:&addr length:&len]) {
        return NO;
    }

    if (bind(self.sockfd, (struct sockaddr *)&addr, len) < 0) {
        return NO;
    }

    return YES;
}

- (void)markReadyAndStartIOLoop {
    [self buildFramerStackIfNeeded];
    [self startFramersIfNeeded];
    [self armReadSource];
    [self promoteReadyIfPossible];
}

- (void)start {
    dispatch_async(self.queue, ^{
        if (self.started) {
            return;
        }
        self.started = YES;

        [self setState:nw_connection_state_preparing error:nil];

        if (![self ensureSocketCreated]) {
            [self failWithError:SSBNWPOSIXError(@"Failed to create socket", errno)];
            return;
        }

        if (![self applySocketOptions]) {
            [self failWithError:SSBNWPOSIXError(@"Failed to configure socket", errno)];
            return;
        }

        if (self.socketIsAdopted) {
            [self setState:nw_connection_state_waiting error:nil];
            [self markReadyAndStartIOLoop];
            return;
        }

        if (![self.endpoint isKindOfClass:[SSBNWEndpoint class]]) {
            [self failWithError:SSBNWPOSIXError(@"Missing or invalid endpoint", EINVAL)];
            return;
        }

        if (![self bindLocalEndpointIfNeeded]) {
            [self failWithError:SSBNWPOSIXError(@"Failed to bind local endpoint", errno)];
            return;
        }

        struct sockaddr_storage remoteAddress;
        socklen_t remoteLength = 0;
        if (![self.endpoint resolvedAddress:&remoteAddress length:&remoteLength]) {
            [self failWithError:SSBNWPOSIXError(@"Failed to resolve remote endpoint", EHOSTUNREACH)];
            return;
        }

        int rc = connect(self.sockfd, (struct sockaddr *)&remoteAddress, remoteLength);
        if (rc == 0) {
            [self setState:nw_connection_state_waiting error:nil];
            [self markReadyAndStartIOLoop];
            return;
        }

        if (errno != EINPROGRESS) {
            [self failWithError:SSBNWPOSIXError(@"Connect failed", errno)];
            return;
        }

        [self setState:nw_connection_state_waiting error:nil];
        [self armConnectSource];
    });
}

- (void)armConnectSource {
    if (self.sockfd < 0 || _connectSource) {
        return;
    }

    _connectSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)self.sockfd, 0, self.queue);
    dispatch_source_set_event_handler(_connectSource, ^{
        if (self.sockfd < 0) {
            return;
        }

        int soError = 0;
        socklen_t len = sizeof(soError);
        if (getsockopt(self.sockfd, SOL_SOCKET, SO_ERROR, &soError, &len) < 0) {
            soError = errno;
        }

        dispatch_source_cancel(self->_connectSource);
        self->_connectSource = nil;

        if (soError != 0) {
            [self failWithError:SSBNWPOSIXError(@"Connect failed", soError)];
            return;
        }

        [self markReadyAndStartIOLoop];
    });
    dispatch_source_set_cancel_handler(_connectSource, ^{});
    dispatch_resume(_connectSource);
}

- (void)cancel {
    dispatch_async(self.queue, ^{
        if (self.state == nw_connection_state_cancelled) {
            return;
        }

        NSError *cancelError = SSBNWPOSIXError(@"Connection cancelled", ECANCELED);
        self.terminalError = cancelError;
        [self setState:nw_connection_state_cancelled error:cancelError];
        [self cleanupSourcesAndSocket];
        [self failPendingReceivesWithError:cancelError];
        [self failPendingSendsWithError:cancelError];
    });
}

- (void)failWithError:(NSError *)error {
    NSError *resolvedError = error ?: SSBNWPOSIXError(@"Connection failed", EIO);
    self.terminalError = resolvedError;
    [self setState:nw_connection_state_failed error:resolvedError];
    [self cleanupSourcesAndSocket];
    [self failPendingReceivesWithError:resolvedError];
    [self failPendingSendsWithError:resolvedError];
}

- (void)buildFramerStackIfNeeded {
    if (self.stackBuilt) {
        return;
    }
    self.stackBuilt = YES;

    NSArray *configured = self.parameters.applicationProtocols;
    if (configured.count == 0) {
        self.topFramer = nil;
        self.bottomFramer = nil;
        self.framerStackTopToBottom = @[];
        self.framerStackBottomToTop = @[];
        return;
    }

    NSMutableArray *instances = [NSMutableArray arrayWithCapacity:configured.count];
    for (id entry in configured) {
        if (![entry isKindOfClass:[SSBNWFramerOptions class]]) {
            continue;
        }
        SSBNWFramerOptions *templateOptions = (SSBNWFramerOptions *)entry;
        SSBNWFramerInstance *instance = [[SSBNWFramerInstance alloc] init];
        instance.connection = self;
        instance.options = [templateOptions copyForConnection];
        instance.definition = instance.options.definition;
        [instances addObject:instance];
    }

    if (instances.count == 0) {
        self.topFramer = nil;
        self.bottomFramer = nil;
        self.framerStackTopToBottom = @[];
        self.framerStackBottomToTop = @[];
        return;
    }

    for (NSUInteger i = 0; i < instances.count; i++) {
        SSBNWFramerInstance *instance = [instances objectAtIndex:i];
        instance.upper = (i == 0) ? nil : [instances objectAtIndex:(i - 1)];
        instance.lower = (i + 1 < instances.count) ? [instances objectAtIndex:(i + 1)] : nil;
        if (instance.lower) {
            instance.inboundSourceBuffer = [NSMutableData data];
        } else {
            instance.inboundSourceBuffer = self.socketReadBuffer;
        }
    }

    self.topFramer = [instances objectAtIndex:0];
    self.bottomFramer = [instances lastObject];
    self.framerStackTopToBottom = [instances copy];

    NSMutableArray *bottomToTop = [NSMutableArray arrayWithCapacity:instances.count];
    for (SSBNWFramerInstance *instance in [instances reverseObjectEnumerator]) {
        [bottomToTop addObject:instance];
    }
    self.framerStackBottomToTop = [bottomToTop copy];
}

- (void)startFramersIfNeeded {
    for (SSBNWFramerInstance *instance in self.framerStackTopToBottom) {
        if (instance.startInvoked) {
            continue;
        }
        instance.startInvoked = YES;

        if (!instance.definition.startHandler) {
            instance.ready = YES;
            continue;
        }

        nw_framer_start_result_t result = instance.definition.startHandler((nw_framer_t)instance);
        if (result == nw_framer_start_result_ready) {
            instance.ready = YES;
        }
    }
}

- (void)armReadSource {
    if (self.sockfd < 0 || _readSource) {
        return;
    }

    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)self.sockfd, 0, self.queue);
    dispatch_source_set_event_handler(_readSource, ^{
        [self readFromSocket];
    });
    dispatch_source_set_cancel_handler(_readSource, ^{});
    dispatch_resume(_readSource);
}

- (void)armWriteSourceIfNeeded {
    if (self.sockfd < 0 || _writeSource || self.writeQueue.count == 0) {
        return;
    }

    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)self.sockfd, 0, self.queue);
    dispatch_source_set_event_handler(_writeSource, ^{
        [self drainSocketWrites];
    });
    dispatch_source_set_cancel_handler(_writeSource, ^{});
    dispatch_resume(_writeSource);
}

- (void)drainSocketWrites {
    if (self.sockfd < 0) {
        return;
    }

    while (self.writeQueue.count > 0) {
        SSBNWSendChunk *chunk = [self.writeQueue objectAtIndex:0];
        if (chunk.offset >= chunk.data.length) {
            [self.writeQueue removeObjectAtIndex:0];
            continue;
        }

        const uint8_t *bytes = (const uint8_t *)chunk.data.bytes + chunk.offset;
        size_t remaining = chunk.data.length - chunk.offset;
        ssize_t sent = send(self.sockfd, bytes, remaining, 0);
        if (sent > 0) {
            chunk.offset += (NSUInteger)sent;
            if (chunk.offset >= chunk.data.length) {
                [self.writeQueue removeObjectAtIndex:0];
            }
            continue;
        }

        if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            break;
        }

        [self failWithError:SSBNWPOSIXError(@"Socket write failed", (sent < 0) ? errno : EPIPE)];
        return;
    }

    if (self.writeQueue.count == 0 && _writeSource) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
    }
}

- (void)readFromSocket {
    if (self.sockfd < 0) {
        return;
    }

    BOOL didReceiveBytes = NO;
    while (true) {
        uint8_t buffer[16384];
        ssize_t count = recv(self.sockfd, buffer, sizeof(buffer), 0);
        if (count > 0) {
            didReceiveBytes = YES;
            if (self.bottomFramer) {
                [self.socketReadBuffer appendBytes:buffer length:(NSUInteger)count];
            } else {
                NSData *chunkData = [NSData dataWithBytes:buffer length:(NSUInteger)count];
                [self enqueueDeliveredData:chunkData context:nil isComplete:false];
            }
            continue;
        }

        if (count == 0) {
            NSError *cancelError = SSBNWPOSIXError(@"Peer closed connection", ECONNRESET);
            self.terminalError = cancelError;
            [self setState:nw_connection_state_cancelled error:cancelError];
            [self cleanupSourcesAndSocket];
            [self failPendingReceivesWithError:cancelError];
            return;
        }

        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
        }

        [self failWithError:SSBNWPOSIXError(@"Socket read failed", errno)];
        return;
    }

    if (self.bottomFramer && didReceiveBytes) {
        [self pumpInboundFramers];
    }
}

- (void)pumpInboundFramers {
    if (!self.bottomFramer || self.framerStackBottomToTop.count == 0) {
        return;
    }

    NSUInteger guard = 0;
    while (guard < 512) {
        guard += 1;
        BOOL progressed = NO;

        for (SSBNWFramerInstance *instance in self.framerStackBottomToTop) {
            if (!instance.inputHandler) {
                continue;
            }

            NSUInteger beforeCurrent = instance.inboundSourceBuffer.length;
            NSUInteger beforeUpper = instance.upper ? instance.upper.inboundSourceBuffer.length : 0;
            NSUInteger beforeDelivered = self.deliveredQueue.count;

            (void)instance.inputHandler((nw_framer_t)instance);

            NSUInteger afterCurrent = instance.inboundSourceBuffer.length;
            NSUInteger afterUpper = instance.upper ? instance.upper.inboundSourceBuffer.length : 0;
            NSUInteger afterDelivered = self.deliveredQueue.count;

            if (beforeCurrent != afterCurrent || beforeUpper != afterUpper || beforeDelivered != afterDelivered) {
                progressed = YES;
            }
        }

        if (!progressed) {
            break;
        }
    }

    [self promoteReadyIfPossible];
}

- (void)enqueueDeliveredData:(NSData *)data context:(SSBNWContentContext *)context isComplete:(BOOL)isComplete {
    SSBNWDeliveredMessage *message = [[SSBNWDeliveredMessage alloc] init];
    message.data = [NSMutableData dataWithData:data ?: [NSData data]];
    message.context = context;
    message.isComplete = isComplete;
    [self.deliveredQueue addObject:message];
    [self drainPendingReceives];
}

- (void)drainPendingReceives {
    while (self.pendingReceives.count > 0 && self.deliveredQueue.count > 0) {
        SSBNWPendingReceive *pending = [self.pendingReceives objectAtIndex:0];
        SSBNWDeliveredMessage *delivered = [self.deliveredQueue objectAtIndex:0];

        NSUInteger available = delivered.data.length;
        if (!pending.messageMode && available < pending.minimumLength) {
            break;
        }

        NSUInteger maxLength = (pending.maximumLength == 0) ? available : MIN((NSUInteger)pending.maximumLength, available);
        if (maxLength == 0 && !pending.messageMode) {
            break;
        }

        NSData *slice = [NSData dataWithBytes:delivered.data.bytes length:maxLength];
        [self.pendingReceives removeObjectAtIndex:0];

        BOOL completeForCallback = delivered.isComplete && (maxLength == available);
        if (maxLength < available) {
            [delivered.data replaceBytesInRange:NSMakeRange(0, maxLength) withBytes:NULL length:0];
            delivered.isComplete = NO;
        } else {
            [self.deliveredQueue removeObjectAtIndex:0];
        }

        dispatch_data_t payload = SSBNWDispatchDataFromNSData(slice, self.queue);
        if (pending.completion) {
            pending.completion(payload,
                               (nw_content_context_t)delivered.context,
                               completeForCallback,
                               nil);
        }
    }
}

- (void)enqueueReceiveWithMinimumLength:(uint32_t)minimumLength
                          maximumLength:(uint32_t)maximumLength
                            messageMode:(BOOL)messageMode
                             completion:(nw_connection_receive_completion_t)completion {
    if (!completion) {
        return;
    }

    if (self.state == nw_connection_state_failed || self.state == nw_connection_state_cancelled) {
        completion(NULL, NULL, false, self.terminalError);
        return;
    }

    SSBNWPendingReceive *pending = [[SSBNWPendingReceive alloc] init];
    pending.minimumLength = minimumLength;
    pending.maximumLength = maximumLength;
    pending.messageMode = messageMode;
    pending.completion = completion;
    [self.pendingReceives addObject:pending];

    [self drainPendingReceives];
}

- (void)enqueueSocketWriteData:(NSData *)data {
    SSBNWSendChunk *chunk = [[SSBNWSendChunk alloc] init];
    chunk.data = data ?: [NSData data];
    chunk.offset = 0;
    [self.writeQueue addObject:chunk];
    [self armWriteSourceIfNeeded];
    [self drainSocketWrites];
}

- (BOOL)allFramersReady {
    if (self.framerStackTopToBottom.count == 0) {
        return YES;
    }

    for (SSBNWFramerInstance *instance in self.framerStackTopToBottom) {
        if (!instance.ready) {
            return NO;
        }
    }

    return YES;
}

- (void)promoteReadyIfPossible {
    if (self.state == nw_connection_state_ready ||
        self.state == nw_connection_state_failed ||
        self.state == nw_connection_state_cancelled) {
        return;
    }

    if (![self allFramersReady]) {
        return;
    }

    [self setState:nw_connection_state_ready error:nil];
    [self drainPendingReceives];
    [self flushPendingSends];
}

- (void)flushPendingSends {
    while (self.pendingSends.count > 0 && self.state == nw_connection_state_ready) {
        SSBNWPendingSend *pending = [self.pendingSends objectAtIndex:0];
        [self.pendingSends removeObjectAtIndex:0];
        [self sendData:pending.payload
               context:(nw_content_context_t)pending.context
            isComplete:pending.isComplete
            completion:pending.completion];
    }
}

- (void)sendData:(NSData *)payload
         context:(nw_content_context_t)context
      isComplete:(BOOL)isComplete
      completion:(nw_connection_send_completion_t)completion {
    if (self.state == nw_connection_state_failed || self.state == nw_connection_state_cancelled) {
        if (completion) {
            completion(self.terminalError ?: SSBNWPOSIXError(@"Connection is not writable", EPIPE));
        }
        return;
    }

    if (self.state != nw_connection_state_ready) {
        SSBNWPendingSend *pending = [[SSBNWPendingSend alloc] init];
        pending.payload = payload ?: [NSData data];
        pending.context = context;
        pending.isComplete = isComplete;
        pending.completion = completion;
        [self.pendingSends addObject:pending];
        return;
    }

    if (!self.topFramer) {
        [self enqueueSocketWriteData:payload];
        if (completion) {
            completion(nil);
        }
        return;
    }

    SSBNWFramerInstance *top = self.topFramer;

    SSBNWFramerMessage *message = nil;
    if ([context isKindOfClass:[SSBNWFramerMessage class]]) {
        message = (SSBNWFramerMessage *)context;
    } else if ([context isKindOfClass:[SSBNWContentContext class]]) {
        SSBNWContentContext *typedContext = (SSBNWContentContext *)context;
        id metadata = [typedContext metadataForDefinitionIdentifier:top.definition.identifier];
        if ([metadata isKindOfClass:[SSBNWFramerMessage class]]) {
            message = (SSBNWFramerMessage *)metadata;
        }
    }

    if (!message) {
        message = [[SSBNWFramerMessage alloc] init];
    }

    message.payloadData = payload;
    top.activeOutputData = payload;
    top.activeOutputOffset = 0;
    top.activeOutputMessage = message;
    top.activeOutputComplete = isComplete;

    if (top.outputHandler) {
        top.outputHandler((nw_framer_t)top,
                          (nw_framer_message_t)message,
                          payload.length,
                          isComplete);
    } else {
        [self routeOutboundData:payload fromFramer:top message:message isComplete:isComplete];
    }

    if (completion) {
        completion(nil);
    }
}

- (void)routeOutboundData:(NSData *)data
               fromFramer:(SSBNWFramerInstance *)framer
                  message:(SSBNWFramerMessage *)message
               isComplete:(BOOL)isComplete {
    NSData *resolvedData = data ?: [NSData data];
    SSBNWFramerMessage *resolvedMessage = message ?: [[SSBNWFramerMessage alloc] init];
    resolvedMessage.payloadData = resolvedData;

    SSBNWFramerInstance *cursor = framer.lower;
    while (cursor && !cursor.outputHandler) {
        cursor = cursor.lower;
    }

    if (!cursor) {
        [self enqueueSocketWriteData:resolvedData];
        return;
    }

    cursor.activeOutputData = resolvedData;
    cursor.activeOutputOffset = 0;
    cursor.activeOutputMessage = resolvedMessage;
    cursor.activeOutputComplete = isComplete;

    if (cursor.outputHandler) {
        cursor.outputHandler((nw_framer_t)cursor,
                             (nw_framer_message_t)resolvedMessage,
                             resolvedData.length,
                             isComplete);
    } else {
        [self enqueueSocketWriteData:resolvedData];
    }
}

@end

@interface SSBNWListener : NSObject {
    dispatch_queue_t _queue;
    dispatch_source_t _acceptSource;
}
@property (nonatomic, strong) SSBNWParameters *parameters;
@property (nonatomic, assign) int sockfd;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) nw_listener_state_t state;
@property (nonatomic, copy) nw_listener_state_changed_handler_t stateHandler;
@property (nonatomic, copy) nw_listener_new_connection_handler_t newConnectionHandler;
- (instancetype)initWithParameters:(SSBNWParameters *)parameters;
- (dispatch_queue_t)queue;
- (void)setQueue:(dispatch_queue_t)queue;
- (void)setState:(nw_listener_state_t)state error:(nw_error_t)error;
- (void)start;
- (void)cancel;
- (void)armAcceptSource;
- (void)handleAccept;
@end

@implementation SSBNWListener

- (instancetype)initWithParameters:(SSBNWParameters *)parameters {
    self = [super init];
    if (self) {
        _parameters = parameters ?: [[SSBNWParameters alloc] init];
        _sockfd = -1;
        _state = nw_listener_state_invalid;
        _queue = SSBNWShimDefaultQueue();
    }
    return self;
}

- (void)dealloc {
    [self cancel];
}

- (dispatch_queue_t)queue {
    return _queue;
}

- (void)setQueue:(dispatch_queue_t)queue {
    if (queue) {
        _queue = queue;
    }
}

- (void)setState:(nw_listener_state_t)state error:(nw_error_t)error {
    if (_state == state) {
        return;
    }
    _state = state;
    if (_stateHandler) {
        _stateHandler(state, error);
    }
}

- (void)cleanup {
    if (_acceptSource) {
        dispatch_source_cancel(_acceptSource);
        _acceptSource = nil;
    }
    if (_sockfd >= 0) {
        close(_sockfd);
        _sockfd = -1;
    }
}

- (void)start {
    dispatch_async(self.queue, ^{
        [self setState:nw_listener_state_waiting error:nil];

        struct sockaddr_storage bindAddr;
        memset(&bindAddr, 0, sizeof(bindAddr));
        socklen_t bindLen = 0;

        SSBNWEndpoint *local = self.parameters.localEndpoint;
        if (local) {
            if (![local resolvedAddress:&bindAddr length:&bindLen]) {
                NSError *error = SSBNWPOSIXError(@"Failed to resolve local bind endpoint", EADDRNOTAVAIL);
                [self setState:nw_listener_state_failed error:error];
                return;
            }
        } else {
            struct sockaddr_in anyAddr;
            memset(&anyAddr, 0, sizeof(anyAddr));
            anyAddr.sin_family = AF_INET;
            anyAddr.sin_addr.s_addr = htonl(INADDR_ANY);
            anyAddr.sin_port = htons(0);
            memcpy(&bindAddr, &anyAddr, sizeof(anyAddr));
            bindLen = sizeof(anyAddr);
        }

        int sock = socket(bindAddr.ss_family, SOCK_STREAM, 0);
        if (sock < 0) {
            NSError *error = SSBNWPOSIXError(@"Failed to create listener socket", errno);
            [self setState:nw_listener_state_failed error:error];
            return;
        }

        int yes = 1;
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        int flags = fcntl(sock, F_GETFL, 0);
        if (flags < 0 || fcntl(sock, F_SETFL, flags | O_NONBLOCK) < 0) {
            int err = errno;
            close(sock);
            NSError *error = SSBNWPOSIXError(@"Failed to configure listener socket", err);
            [self setState:nw_listener_state_failed error:error];
            return;
        }

        if (bind(sock, (struct sockaddr *)&bindAddr, bindLen) < 0) {
            int err = errno;
            close(sock);
            NSError *error = SSBNWPOSIXError(@"Failed to bind listener socket", err);
            [self setState:nw_listener_state_failed error:error];
            return;
        }

        if (listen(sock, 128) < 0) {
            int err = errno;
            close(sock);
            NSError *error = SSBNWPOSIXError(@"Failed to listen on socket", err);
            [self setState:nw_listener_state_failed error:error];
            return;
        }

        struct sockaddr_storage boundAddr;
        socklen_t boundLen = sizeof(boundAddr);
        if (getsockname(sock, (struct sockaddr *)&boundAddr, &boundLen) == 0) {
            if (boundAddr.ss_family == AF_INET) {
                struct sockaddr_in *inAddr = (struct sockaddr_in *)&boundAddr;
                self.port = ntohs(inAddr->sin_port);
            } else if (boundAddr.ss_family == AF_INET6) {
                struct sockaddr_in6 *in6Addr = (struct sockaddr_in6 *)&boundAddr;
                self.port = ntohs(in6Addr->sin6_port);
            }
        }

        self.sockfd = sock;
        [self setState:nw_listener_state_ready error:nil];
        [self armAcceptSource];
    });
}

- (void)cancel {
    dispatch_async(self.queue, ^{
        if (self.state == nw_listener_state_cancelled) {
            return;
        }
        NSError *cancelError = SSBNWPOSIXError(@"Listener cancelled", ECANCELED);
        [self setState:nw_listener_state_cancelled error:cancelError];
        [self cleanup];
    });
}

- (void)armAcceptSource {
    if (self.sockfd < 0 || _acceptSource) {
        return;
    }

    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)self.sockfd, 0, self.queue);
    dispatch_source_set_event_handler(_acceptSource, ^{
        [self handleAccept];
    });
    dispatch_source_set_cancel_handler(_acceptSource, ^{});
    dispatch_resume(_acceptSource);
}

- (void)handleAccept {
    while (true) {
        struct sockaddr_storage peerAddr;
        socklen_t peerLen = sizeof(peerAddr);
        int client = accept(self.sockfd, (struct sockaddr *)&peerAddr, &peerLen);
        if (client < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            NSError *error = SSBNWPOSIXError(@"Accept failed", errno);
            [self setState:nw_listener_state_failed error:error];
            [self cleanup];
            return;
        }

        int flags = fcntl(client, F_GETFL, 0);
        if (flags >= 0) {
            (void)fcntl(client, F_SETFL, flags | O_NONBLOCK);
        }

        char host[NI_MAXHOST];
        char service[NI_MAXSERV];
        memset(host, 0, sizeof(host));
        memset(service, 0, sizeof(service));

        NSString *peerHost = @"127.0.0.1";
        NSString *peerPort = @"0";
        if (getnameinfo((struct sockaddr *)&peerAddr, peerLen,
                        host, sizeof(host),
                        service, sizeof(service),
                        NI_NUMERICHOST | NI_NUMERICSERV) == 0) {
            peerHost = [NSString stringWithUTF8String:host] ?: peerHost;
            peerPort = [NSString stringWithUTF8String:service] ?: peerPort;
        }

        SSBNWEndpoint *peerEndpoint = [[SSBNWEndpoint alloc] initWithHostname:peerHost port:peerPort];
        SSBNWConnection *connection = [[SSBNWConnection alloc] initAdoptedSocket:client
                                                                         endpoint:peerEndpoint
                                                                       parameters:self.parameters];
        [connection setQueue:self.queue];

        if (self.newConnectionHandler) {
            self.newConnectionHandler((nw_connection_t)connection);
        }
    }
}

@end

#pragma mark - Endpoint

nw_endpoint_t nw_endpoint_create_host(const char *hostname, const char *port) {
    NSString *host = hostname ? [NSString stringWithUTF8String:hostname] : @"127.0.0.1";
    NSString *service = port ? [NSString stringWithUTF8String:port] : @"0";
    return (nw_endpoint_t)[[SSBNWEndpoint alloc] initWithHostname:host port:service];
}

#pragma mark - Parameters / Stack

nw_parameters_t nw_parameters_create_secure_tcp(nw_parameters_configure_protocol_block_t configure_tls,
                                                 nw_parameters_configure_protocol_block_t configure_tcp) {
    SSBNWParameters *parameters = [[SSBNWParameters alloc] init];
    parameters.configureTLS = configure_tls;
    parameters.configureTCP = configure_tcp;

    if (configure_tcp) {
        configure_tcp((nw_protocol_options_t)parameters.tcpOptions);
    }

    return (nw_parameters_t)parameters;
}

nw_protocol_stack_t nw_parameters_copy_default_protocol_stack(nw_parameters_t parameters) {
    if (![parameters isKindOfClass:[SSBNWParameters class]]) {
        return nil;
    }
    return (nw_protocol_stack_t)((SSBNWParameters *)parameters).protocolStack;
}

void nw_parameters_set_local_endpoint(nw_parameters_t parameters, nw_endpoint_t endpoint) {
    if (![parameters isKindOfClass:[SSBNWParameters class]]) {
        return;
    }

    SSBNWParameters *typedParameters = (SSBNWParameters *)parameters;
    if ([endpoint isKindOfClass:[SSBNWEndpoint class]]) {
        typedParameters.localEndpoint = (SSBNWEndpoint *)endpoint;
    } else {
        typedParameters.localEndpoint = nil;
    }
}

void nw_protocol_stack_prepend_application_protocol(nw_protocol_stack_t stack, nw_protocol_options_t options) {
    if (![stack isKindOfClass:[SSBNWProtocolStack class]] || ![options isKindOfClass:[SSBNWFramerOptions class]]) {
        return;
    }

    SSBNWProtocolStack *typedStack = (SSBNWProtocolStack *)stack;
    if (![typedStack.parameters isKindOfClass:[SSBNWParameters class]]) {
        return;
    }

    SSBNWParameters *parameters = (SSBNWParameters *)typedStack.parameters;
    [parameters.applicationProtocols insertObject:(SSBNWFramerOptions *)options atIndex:0];
}

void nw_tcp_options_set_no_delay(nw_protocol_options_t options, bool no_delay) {
    if (![options isKindOfClass:[SSBNWTCPOptions class]]) {
        return;
    }
    ((SSBNWTCPOptions *)options).noDelay = no_delay;
}

#pragma mark - Connections

nw_connection_t nw_connection_create(nw_endpoint_t endpoint, nw_parameters_t parameters) {
    SSBNWEndpoint *typedEndpoint = [endpoint isKindOfClass:[SSBNWEndpoint class]] ? (SSBNWEndpoint *)endpoint : nil;
    SSBNWParameters *typedParameters = [parameters isKindOfClass:[SSBNWParameters class]] ? (SSBNWParameters *)parameters : [[SSBNWParameters alloc] init];

    SSBNWConnection *connection = [[SSBNWConnection alloc] initOutboundWithEndpoint:typedEndpoint parameters:typedParameters];
    [connection setQueue:SSBNWShimDefaultQueue()];
    return (nw_connection_t)connection;
}

void nw_connection_set_queue(nw_connection_t connection, dispatch_queue_t queue) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    [typedConnection setQueue:queue ?: SSBNWShimDefaultQueue()];
}

void nw_connection_set_state_changed_handler(nw_connection_t connection,
                                             nw_connection_state_changed_handler_t handler) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    typedConnection.stateHandler = handler;
}

void nw_connection_start(nw_connection_t connection) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    [typedConnection start];
}

void nw_connection_receive_message(nw_connection_t connection,
                                   nw_connection_receive_completion_t completion) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        if (completion) {
            completion(NULL, NULL, false, SSBNWPOSIXError(@"Invalid connection", EINVAL));
        }
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    dispatch_async(typedConnection.queue, ^{
        [typedConnection enqueueReceiveWithMinimumLength:0
                                           maximumLength:UINT32_MAX
                                             messageMode:YES
                                              completion:completion];
    });
}

void nw_connection_receive(nw_connection_t connection,
                           uint32_t minimum_incomplete_length,
                           uint32_t maximum_length,
                           nw_connection_receive_completion_t completion) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        if (completion) {
            completion(NULL, NULL, false, SSBNWPOSIXError(@"Invalid connection", EINVAL));
        }
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    dispatch_async(typedConnection.queue, ^{
        [typedConnection enqueueReceiveWithMinimumLength:minimum_incomplete_length
                                           maximumLength:maximum_length
                                             messageMode:NO
                                              completion:completion];
    });
}

void nw_connection_send(nw_connection_t connection,
                        dispatch_data_t content,
                        nw_content_context_t context,
                        bool is_complete,
                        nw_connection_send_completion_t completion) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        if (completion) {
            completion(SSBNWPOSIXError(@"Invalid connection", EINVAL));
        }
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    NSData *payload = SSBNWNSDataFromDispatchData(content);

    dispatch_async(typedConnection.queue, ^{
        [typedConnection sendData:payload
                          context:context
                       isComplete:is_complete
                       completion:completion];
    });
}

void nw_connection_cancel(nw_connection_t connection) {
    if (![connection isKindOfClass:[SSBNWConnection class]]) {
        return;
    }

    SSBNWConnection *typedConnection = (SSBNWConnection *)connection;
    [typedConnection cancel];
}

#pragma mark - Framer Runtime

nw_protocol_definition_t nw_framer_create_definition(const char *identifier,
                                                     uint32_t flags,
                                                     nw_framer_start_handler_t start_handler) {
    NSString *name = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    SSBNWFramerDefinition *definition = [[SSBNWFramerDefinition alloc] initWithIdentifier:name
                                                                                      flags:flags
                                                                               startHandler:start_handler];
    return (nw_protocol_definition_t)definition;
}

nw_protocol_options_t nw_framer_create_options(nw_protocol_definition_t definition) {
    if (![definition isKindOfClass:[SSBNWFramerDefinition class]]) {
        return nil;
    }

    SSBNWFramerOptions *options = [[SSBNWFramerOptions alloc] initWithDefinition:(SSBNWFramerDefinition *)definition];
    return (nw_protocol_options_t)options;
}

nw_protocol_options_t nw_framer_copy_options(nw_framer_t framer) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return nil;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    return (nw_protocol_options_t)instance.options;
}

void nw_framer_options_set_object_value(nw_protocol_options_t options, const char *key, id value) {
    if (![options isKindOfClass:[SSBNWFramerOptions class]]) {
        return;
    }

    NSString *resolvedKey = SSBNWStringFromCKey(key);
    if (!resolvedKey) {
        return;
    }

    SSBNWFramerOptions *typedOptions = (SSBNWFramerOptions *)options;
    if (value) {
        [typedOptions.values setObject:value forKey:resolvedKey];
    } else {
        [typedOptions.values removeObjectForKey:resolvedKey];
    }
}

id nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key) {
    if (![options isKindOfClass:[SSBNWFramerOptions class]]) {
        return nil;
    }

    NSString *resolvedKey = SSBNWStringFromCKey(key);
    if (!resolvedKey) {
        return nil;
    }

    SSBNWFramerOptions *typedOptions = (SSBNWFramerOptions *)options;
    return [typedOptions.values objectForKey:resolvedKey];
}

void nw_framer_set_input_handler(nw_framer_t framer, nw_framer_input_handler_t input_handler) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    ((SSBNWFramerInstance *)framer).inputHandler = input_handler;
}

void nw_framer_set_output_handler(nw_framer_t framer, nw_framer_output_handler_t output_handler) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    ((SSBNWFramerInstance *)framer).outputHandler = output_handler;
}

void nw_framer_mark_ready(nw_framer_t framer) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    instance.ready = YES;
    [instance.connection promoteReadyIfPossible];
}

void nw_framer_mark_failed_with_error(nw_framer_t framer, int error_code) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    SSBNWConnection *connection = instance.connection;
    if (!connection) {
        return;
    }
    [connection failWithError:SSBNWPOSIXError(@"Framer marked connection as failed", error_code)];
}

bool nw_framer_parse_input(nw_framer_t framer,
                           size_t minimum_incomplete_length,
                           size_t maximum_length,
                           uint8_t *temp_buffer,
                           nw_framer_parse_completion_t parse_completion) {
    (void)temp_buffer;

    if (![framer isKindOfClass:[SSBNWFramerInstance class]] || !parse_completion) {
        return false;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    NSMutableData *source = instance.inboundSourceBuffer;
    if (!source) {
        return false;
    }

    if (source.length < minimum_incomplete_length) {
        return false;
    }

    size_t available = source.length;
    size_t offered = MIN(available, maximum_length);
    if (offered == 0 && minimum_incomplete_length > 0) {
        return false;
    }

    uint8_t *buffer = (uint8_t *)source.mutableBytes;
    size_t consumed = parse_completion(buffer, offered, false);
    if (consumed > offered) {
        consumed = offered;
    }

    if (consumed > 0) {
        [source replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
    }

    return true;
}

void nw_framer_parse_output(nw_framer_t framer,
                            size_t minimum_incomplete_length,
                            size_t maximum_length,
                            uint8_t *temp_buffer,
                            nw_framer_parse_completion_t parse_completion) {
    (void)temp_buffer;

    if (![framer isKindOfClass:[SSBNWFramerInstance class]] || !parse_completion) {
        return;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    NSData *activeData = instance.activeOutputData;

    if (!activeData && [instance.activeOutputMessage isKindOfClass:[SSBNWFramerMessage class]]) {
        activeData = instance.activeOutputMessage.payloadData;
        instance.activeOutputData = activeData;
        instance.activeOutputOffset = 0;
    }

    if (!activeData) {
        return;
    }

    if (instance.activeOutputOffset >= activeData.length) {
        return;
    }

    size_t remaining = activeData.length - instance.activeOutputOffset;
    if (remaining < minimum_incomplete_length) {
        return;
    }

    size_t offered = MIN(remaining, maximum_length);
    const uint8_t *bytes = (const uint8_t *)activeData.bytes + instance.activeOutputOffset;
    bool isComplete = instance.activeOutputComplete && (offered == remaining);

    size_t consumed = parse_completion((uint8_t *)bytes, offered, isComplete);
    if (consumed > offered) {
        consumed = offered;
    }
    instance.activeOutputOffset += consumed;
}

void nw_framer_write_output_data(nw_framer_t framer, dispatch_data_t data) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    SSBNWConnection *connection = instance.connection;
    if (!connection) {
        return;
    }

    NSData *payload = SSBNWNSDataFromDispatchData(data);
    [connection routeOutboundData:payload
                       fromFramer:instance
                          message:instance.activeOutputMessage
                       isComplete:instance.activeOutputComplete];
}

void nw_framer_deliver_input(nw_framer_t framer,
                             const void *input_buffer,
                             size_t input_length,
                             nw_framer_message_t message,
                             bool is_complete) {
    if (![framer isKindOfClass:[SSBNWFramerInstance class]]) {
        return;
    }

    SSBNWFramerInstance *instance = (SSBNWFramerInstance *)framer;
    SSBNWConnection *connection = instance.connection;
    if (!connection) {
        return;
    }

    NSData *data = input_buffer ? [NSData dataWithBytes:input_buffer length:input_length] : [NSData data];
    if (instance.upper) {
        if (data.length > 0) {
            [instance.upper.inboundSourceBuffer appendData:data];
        }
        return;
    }

    SSBNWContentContext *context = [[SSBNWContentContext alloc] init];
    if ([message isKindOfClass:[SSBNWFramerMessage class]] && instance.definition.identifier.length > 0) {
        [context setMetadata:message forDefinitionIdentifier:instance.definition.identifier];
    }

    [connection enqueueDeliveredData:data context:context isComplete:is_complete];
}

nw_framer_message_t nw_framer_message_create(nw_framer_t framer) {
    (void)framer;
    return (nw_framer_message_t)[[SSBNWFramerMessage alloc] init];
}

void nw_framer_message_set_object_value(nw_framer_message_t message, const char *key, id value) {
    if (![message isKindOfClass:[SSBNWFramerMessage class]]) {
        return;
    }

    NSString *resolvedKey = SSBNWStringFromCKey(key);
    if (!resolvedKey) {
        return;
    }

    SSBNWFramerMessage *typedMessage = (SSBNWFramerMessage *)message;
    if (value) {
        [typedMessage.values setObject:value forKey:resolvedKey];
    } else {
        [typedMessage.values removeObjectForKey:resolvedKey];
    }
}

id nw_framer_message_copy_object_value(nw_framer_message_t message, const char *key) {
    if (![message isKindOfClass:[SSBNWFramerMessage class]]) {
        return nil;
    }

    NSString *resolvedKey = SSBNWStringFromCKey(key);
    if (!resolvedKey) {
        return nil;
    }

    SSBNWFramerMessage *typedMessage = (SSBNWFramerMessage *)message;
    return [typedMessage.values objectForKey:resolvedKey];
}

nw_protocol_metadata_t nw_content_context_copy_protocol_metadata(nw_content_context_t context,
                                                                 nw_protocol_definition_t definition) {
    if (![context isKindOfClass:[SSBNWContentContext class]]) {
        return nil;
    }

    if (![definition isKindOfClass:[SSBNWFramerDefinition class]]) {
        return nil;
    }

    SSBNWContentContext *typedContext = (SSBNWContentContext *)context;
    SSBNWFramerDefinition *typedDefinition = (SSBNWFramerDefinition *)definition;
    return (nw_protocol_metadata_t)[typedContext metadataForDefinitionIdentifier:typedDefinition.identifier];
}

#pragma mark - Listener API

nw_listener_t nw_listener_create(nw_parameters_t parameters) {
    SSBNWParameters *typedParameters = [parameters isKindOfClass:[SSBNWParameters class]] ? (SSBNWParameters *)parameters : [[SSBNWParameters alloc] init];
    SSBNWListener *listener = [[SSBNWListener alloc] initWithParameters:typedParameters];
    [listener setQueue:SSBNWShimDefaultQueue()];
    return (nw_listener_t)listener;
}

void nw_listener_set_queue(nw_listener_t listener, dispatch_queue_t queue) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return;
    }

    SSBNWListener *typedListener = (SSBNWListener *)listener;
    [typedListener setQueue:queue ?: SSBNWShimDefaultQueue()];
}

void nw_listener_set_state_changed_handler(nw_listener_t listener,
                                           nw_listener_state_changed_handler_t handler) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return;
    }

    ((SSBNWListener *)listener).stateHandler = handler;
}

void nw_listener_set_new_connection_handler(nw_listener_t listener,
                                            nw_listener_new_connection_handler_t handler) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return;
    }

    ((SSBNWListener *)listener).newConnectionHandler = handler;
}

void nw_listener_start(nw_listener_t listener) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return;
    }

    SSBNWListener *typedListener = (SSBNWListener *)listener;
    [typedListener start];
}

void nw_listener_cancel(nw_listener_t listener) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return;
    }

    SSBNWListener *typedListener = (SSBNWListener *)listener;
    [typedListener cancel];
}

uint16_t nw_listener_get_port(nw_listener_t listener) {
    if (![listener isKindOfClass:[SSBNWListener class]]) {
        return 0;
    }

    return ((SSBNWListener *)listener).port;
}

#endif
