#import "SSBNetworkCompat.h"
#import "SSBCommonCryptoCompat.h"
#import <objc/runtime.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <netdb.h>
#include <poll.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>

#ifndef __APPLE__

#pragma mark - Shim Queue & Maps

static dispatch_queue_t _shimQueue = nil;
static NSMutableDictionary *_connectionMap = nil;
static NSMutableDictionary *_framerContextMap = nil;
static NSMutableDictionary *_framerBufferMap = nil;

static dispatch_queue_t shim_queue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _shimQueue = dispatch_queue_create("com.ssbc.network.shim", DISPATCH_QUEUE_SERIAL);
        _connectionMap = [NSMutableDictionary dictionary];
        _framerContextMap = [NSMutableDictionary dictionaryWithCapacity:8];
        _framerBufferMap = [NSMutableDictionary dictionaryWithCapacity:8];
    });
    return _shimQueue;
}

#pragma mark - SSBEndpoint

@interface SSBEndpoint : NSObject
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, copy) NSString *port;
@property (nonatomic, assign) int socketFamily;
@property (nonatomic, assign) struct sockaddr_storage resolvedAddr;
@property (nonatomic, assign) socklen_t addrLen;
- (instancetype)initWithHostname:(NSString *)h port:(NSString *)p;
@end

@implementation SSBEndpoint
- (instancetype)initWithHostname:(NSString *)h port:(NSString *)p {
    self = [super init];
    if (self) {
        _hostname = [h copy];
        _port = [p copy];
        _socketFamily = AF_INET;
        [self resolve];
    }
    return self;
}
- (BOOL)resolve {
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int ret = getaddrinfo(_hostname.UTF8String, _port.UTF8String, &hints, &res);
    if (ret != 0 || !res) return NO;
    memcpy(&_resolvedAddr, res->ai_addr, res->ai_addrlen);
    _addrLen = (socklen_t)res->ai_addrlen;
    _socketFamily = res->ai_family;
    freeaddrinfo(res);
    return YES;
}
@end

#pragma mark - SSBParameters

@interface SSBParameters : NSObject
@property (nonatomic, copy) nw_parameters_configure_protocol_block_t configureTLS;
@property (nonatomic, copy) nw_parameters_configure_protocol_block_t configureTCP;
@property (nonatomic, strong) NSMutableArray *protocolStack;
@property (nonatomic, assign) BOOL noDelay;
- (instancetype)init;
@end

@implementation SSBParameters
- (instancetype)init {
    self = [super init];
    if (self) {
        _protocolStack = [NSMutableArray array];
        _noDelay = YES;
    }
    return self;
}
@end

#pragma mark - SSBFramerContext

@interface SSBFramerContext : NSObject
@property (nonatomic, strong) id framer;
@property (nonatomic, copy) nw_framer_start_handler_t startHandler;
@property (nonatomic, copy) nw_framer_input_handler_t inputHandler;
@property (nonatomic, copy) nw_framer_output_handler_t outputHandler;
@property (nonatomic, strong) SSBFramerContext *nextFramer;
@property (nonatomic, strong) NSMutableData *inputBuffer;
@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, copy) void (^feedHandler)(const uint8_t *bytes, size_t len);
- (instancetype)init;
@end

@implementation SSBFramerContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _inputBuffer = [NSMutableData data];
        _isReady = NO;
    }
    return self;
}
@end

#pragma mark - SSBConnection

@interface SSBConnection : NSObject {
    dispatch_queue_t _queue;
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
}
@property (nonatomic, assign) int sockfd;
@property (nonatomic, strong) SSBEndpoint *endpoint;
@property (nonatomic, strong) SSBParameters *parameters;
@property (nonatomic, copy) nw_connection_state_changed_handler_t stateHandler;
@property (nonatomic, assign) nw_connection_state_t state;
@property (nonatomic, strong) NSMutableData *socketReadBuffer;
@property (nonatomic, strong) NSMutableArray *socketWriteQueue;
@property (nonatomic, assign) BOOL writePending;
@property (nonatomic, strong) SSBFramerContext *topFramer;
@property (nonatomic, strong) SSBFramerContext *bottomFramer;
@property (nonatomic, strong) nw_connection_receive_completion_t receiveCompletion;
- (void)close;
- (void)setState:(nw_connection_state_t)state;
- (void)enqueueWrite:(dispatch_data_t)data;
- (void)writeToSocket:(const uint8_t *)bytes length:(size_t)len;
- (void)feedFramer:(SSBFramerContext *)ctx bytes:(const uint8_t *)bytes length:(size_t)len;
- (size_t)readFromSocketBlocking:(size_t)minBytes;
@end

@implementation SSBConnection
- (instancetype)init {
    self = [super init];
    if (self) {
        _sockfd = -1;
        _state = nw_connection_state_invalid;
        _socketReadBuffer = [NSMutableData data];
        _socketWriteQueue = [NSMutableArray array];
        _writePending = NO;
    }
    return self;
}
- (void)dealloc { [self close]; }
- (void)close {
    if (_sockfd >= 0) { close(_sockfd); _sockfd = -1; }
    [self disableSources];
}
- (void)disableSources {
    if (_readSource) { dispatch_source_cancel(_readSource); _readSource = NULL; }
    if (_writeSource) { dispatch_source_cancel(_writeSource); _writeSource = NULL; }
    _writePending = NO;
}
- (void)setState:(nw_connection_state_t)state {
    if (_state == state) return;
    _state = state;
    if (_stateHandler) _stateHandler(state, nil);
}
- (void)enqueueWrite:(dispatch_data_t)data {
    const void *bytes = NULL;
    size_t len = 0;
    dispatch_data_create_map(data, &bytes, &len);
    NSData *nsdata = [NSData dataWithBytes:bytes length:len];
    [_socketWriteQueue addObject:nsdata];
    [self armWriteSource];
}
- (dispatch_queue_t)queue { return _queue; }
- (void)setQueue:(dispatch_queue_t)q { _queue = q; }
- (void)writeToSocket:(const uint8_t *)bytes length:(size_t)len {
    if (_sockfd < 0 || len == 0) return;
    dispatch_data_t d = dispatch_data_create(bytes, len, _queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    [self enqueueWrite:d];
}
- (void)armWriteSource {
    if (_sockfd < 0 || _writePending) return;
    _writePending = YES;
    if (!_writeSource) {
        _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, _queue);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_writeSource, ^{ [weakSelf handleWrite]; });
        dispatch_source_set_cancel_handler(_writeSource, ^{});
        dispatch_resume(_writeSource);
    } else {
        dispatch_resume(_writeSource);
    }
}
- (void)handleWrite {
    if (_sockfd < 0 || _socketWriteQueue.count == 0) {
        [self disableSources];
        return;
    }
    NSData *front = _socketWriteQueue.firstObject;
    ssize_t sent = send(_sockfd, front.bytes, front.length, 0);
    if (sent > 0) {
        if ((size_t)sent < front.length) {
            _socketWriteQueue[0] = [NSData dataWithBytes:(const uint8_t *)front.bytes + sent length:front.length - (size_t)sent];
        } else {
            [_socketWriteQueue removeObjectAtIndex:0];
        }
        if (_socketWriteQueue.count == 0) [self disableSources];
    } else if (sent < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
        [self setState:nw_connection_state_failed];
        [self close];
    }
}
- (size_t)readFromSocketBlocking:(size_t)minBytes {
    if (_sockfd < 0) return 0;
    while (_socketReadBuffer.length < minBytes) {
        uint8_t buf[16384];
        ssize_t n = recv(_sockfd, buf, sizeof(buf), 0);
        if (n > 0) {
            [_socketReadBuffer appendBytes:buf length:n];
        } else if (n == 0) {
            return _socketReadBuffer.length;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            struct pollfd pfd = { .fd = _sockfd, .events = POLLIN };
            if (poll(&pfd, 1, -1) <= 0) return _socketReadBuffer.length;
        } else {
            return _socketReadBuffer.length;
        }
    }
    return _socketReadBuffer.length;
}
- (void)readFromSocket {
    if (_sockfd < 0) return;
    uint8_t buf[16384];
    ssize_t n = recv(_sockfd, buf, sizeof(buf), 0);
    if (n > 0) {
        [_socketReadBuffer appendBytes:buf length:n];
        [self pumpTopFramer];
    } else if (n == 0) {
        [self setState:nw_connection_state_cancelled];
        [self close];
    } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
        [self setState:nw_connection_state_failed];
        [self close];
    }
}
- (void)feedFramer:(SSBFramerContext *)ctx bytes:(const uint8_t *)bytes length:(size_t)len {
    [ctx.inputBuffer appendBytes:bytes length:len];
}
- (void)pumpTopFramer {
    if (!_topFramer || !_topFramer.inputHandler) return;
    if (_socketReadBuffer.length == 0) return;

    while (true) {
        size_t consumed = _topFramer.inputHandler(_topFramer.framer);
        if (consumed > 0 && consumed <= _socketReadBuffer.length) {
            [_socketReadBuffer replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
        }
        if (consumed == 0 || _socketReadBuffer.length == 0) break;
    }
}
- (void)armReadSource {
    if (_sockfd < 0) return;
    if (!_readSource) {
        _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sockfd, 0, _queue);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_readSource, ^{ [weakSelf readFromSocket]; });
        dispatch_source_set_cancel_handler(_readSource, ^{});
        dispatch_resume(_readSource);
    }
}
@end

#pragma mark - SSBListener

@interface SSBListener : NSObject {
    dispatch_queue_t _queue;
    dispatch_source_t _acceptSource;
}
@property (nonatomic, assign) int sockfd;
@property (nonatomic, copy) nw_listener_state_changed_handler_t stateHandler;
@property (nonatomic, copy) nw_listener_new_connection_handler_t newConnectionHandler;
@property (nonatomic, assign) nw_listener_state_t state;
@property (nonatomic, assign) uint16_t port;
- (void)setState:(nw_listener_state_t)state;
- (void)cancel;
- (void)armAcceptSource;
- (void)handleAccept;
@end

@implementation SSBListener
- (instancetype)init { self = [super init]; if (self) { _sockfd = -1; _state = nw_listener_state_invalid; } return self; }
- (void)dealloc { [self cancel]; }
- (void)cancel {
    if (_acceptSource) { dispatch_source_cancel(_acceptSource); _acceptSource = NULL; }
    if (_sockfd >= 0) { close(_sockfd); _sockfd = -1; }
}
- (void)setState:(nw_listener_state_t)state {
    if (_state == state) return;
    _state = state;
    if (_stateHandler) _stateHandler(state, nil);
}
- (void)handleAccept {
    struct sockaddr_storage clientAddr;
    socklen_t clientLen = sizeof(clientAddr);
    int clientFd = accept(_sockfd, (struct sockaddr *)&clientAddr, &clientLen);
    if (clientFd < 0) return;
    SSBConnection *conn = [[SSBConnection alloc] init];
    conn.sockfd = clientFd;
    conn.queue = _queue;
    if (_newConnectionHandler) _newConnectionHandler((nw_connection_t)conn);
}
- (void)armAcceptSource {
    if (_sockfd < 0) return;
    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sockfd, 0, _queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{ [weakSelf handleAccept]; });
    dispatch_source_set_cancel_handler(_acceptSource, ^{});
    dispatch_resume(_acceptSource);
}
- (dispatch_queue_t)queue { return _queue; }
- (void)setQueue:(dispatch_queue_t)q { _queue = q; }
@end

#pragma mark - Shim Function Implementations

nw_endpoint_t nw_endpoint_create_host(const char *hostname, const char *port) {
    return (nw_endpoint_t)[[SSBEndpoint alloc] initWithHostname:[NSString stringWithUTF8String:hostname]
                                                            port:[NSString stringWithUTF8String:port]];
}

nw_parameters_t nw_parameters_create_secure_tcp(nw_parameters_configure_protocol_block_t configure_tls,
                                               nw_parameters_configure_protocol_block_t configure_tcp) {
    SSBParameters *p = [[SSBParameters alloc] init];
    p.configureTLS = configure_tls;
    p.configureTCP = configure_tcp;
    return (nw_parameters_t)p;
}

nw_protocol_stack_t nw_parameters_copy_default_protocol_stack(nw_parameters_t parameters) {
    return (nw_protocol_stack_t)parameters;
}

void nw_parameters_set_local_endpoint(nw_parameters_t parameters, nw_endpoint_t endpoint) {}

void nw_protocol_stack_prepend_application_protocol(nw_protocol_stack_t stack, nw_protocol_options_t options) {
    SSBParameters *p = (SSBParameters *)stack;
    if (p.protocolStack) [p.protocolStack insertObject:options atIndex:0];
}

nw_connection_t nw_connection_create(nw_endpoint_t endpoint, nw_parameters_t parameters) {
    SSBEndpoint *ep = (SSBEndpoint *)endpoint;
    SSBParameters *params = (SSBParameters *)parameters;
    SSBConnection *conn = [[SSBConnection alloc] init];
    conn.endpoint = ep;
    conn.parameters = params;
    int sock = socket(ep.socketFamily, SOCK_STREAM, 0);
    if (sock < 0) return NULL;
    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    if (params.noDelay) setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    conn.sockfd = sock;
    conn.queue = shim_queue();
    conn.state = nw_connection_state_waiting;
    dispatch_sync(shim_queue(), ^{
        _connectionMap[[NSValue valueWithPointer:(__bridge const void *)conn]] = conn;
    });
    return (nw_connection_t)conn;
}

void nw_connection_set_queue(nw_connection_t connection, dispatch_queue_t queue) {
    SSBConnection *conn = (SSBConnection *)connection;
    if (queue) conn.queue = queue;
}

void nw_connection_set_state_changed_handler(nw_connection_t connection,
                                              nw_connection_state_changed_handler_t handler) {
    ((SSBConnection *)connection).stateHandler = handler;
}

void nw_connection_start(nw_connection_t connection) {
    SSBConnection *conn = (SSBConnection *)connection;
    dispatch_async(conn.queue, ^{
        [conn setState:nw_connection_state_preparing];

        SSBEndpoint *ep = conn.endpoint;
        struct sockaddr_storage addr = ep.resolvedAddr;
        socklen_t addrLen = ep.addrLen;
        int ret = connect(conn.sockfd, (struct sockaddr *)&addr, addrLen);
        if (ret < 0 && errno != EINPROGRESS) {
            [conn setState:nw_connection_state_failed];
            return;
        }
        [conn setState:nw_connection_state_waiting];

        dispatch_source_t cs = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, conn.sockfd, 0, conn.queue);
        __weak typeof(conn) weakC = conn;
        dispatch_source_set_event_handler(cs, ^{
            __strong typeof(weakC) c = weakC;
            if (!c) return;
            dispatch_source_cancel(cs);

            int err = 0; socklen_t elen = sizeof(err);
            getsockopt(c.sockfd, SOL_SOCKET, SO_ERROR, &err, &elen);
            if (err != 0) { [c setState:nw_connection_state_failed]; return; }

            SSBParameters *params = (SSBParameters *)c.parameters;
            NSArray *stack = params.protocolStack;
            c.topFramer = nil;
            c.bottomFramer = nil;

            for (id options in stack) {
                SSBFramerContext *(^defBlock)(void) = (id)options;
                SSBFramerContext *ctx = defBlock();
                ctx.inputBuffer = [NSMutableData data];

                dispatch_sync(shim_queue(), ^{
                    _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)ctx.framer]] = ctx;
                    _connectionMap[[NSValue valueWithPointer:(__bridge const void *)ctx.framer]] = c;
                    _framerBufferMap[[NSValue valueWithPointer:(__bridge const void *)ctx.framer]] = ctx.inputBuffer;
                });

                if (!c.topFramer) {
                    c.topFramer = ctx;
                } else {
                    ctx.nextFramer = c.bottomFramer;
                    c.bottomFramer.nextFramer = ctx;
                }
                c.bottomFramer = ctx;

                if (ctx.startHandler) {
                    ctx.startHandler(ctx.framer);
                }
            }

            if (c.topFramer) {
                __weak typeof(c) weakConn = c;
                c.topFramer.feedHandler = ^(const uint8_t *bytes, size_t len) {
                    [weakConn.socketReadBuffer appendBytes:bytes length:len];
                };
            }

            [c setState:nw_connection_state_ready];
            [c armReadSource];
        });
        dispatch_source_set_cancel_handler(cs, ^{});
        dispatch_resume(cs);
    });
}

void nw_connection_receive_message(nw_connection_t connection,
                                   nw_connection_receive_completion_t completion) {
    nw_connection_receive(connection, 1, UINT32_MAX, completion);
}

void nw_connection_receive(nw_connection_t connection,
                           uint32_t minimum_incomplete_length,
                           uint32_t maximum_length,
                           nw_connection_receive_completion_t completion) {
    SSBConnection *conn = (SSBConnection *)connection;
    dispatch_async(conn.queue, ^{
        if (conn.state != nw_connection_state_ready) {
            if (completion) completion(NULL, NULL, false, NULL);
            return;
        }
        if (conn.socketReadBuffer.length >= minimum_incomplete_length) {
            size_t avail = MIN(conn.socketReadBuffer.length, maximum_length);
            NSData *data = [conn.socketReadBuffer subdataWithRange:NSMakeRange(0, avail)];
            [conn.socketReadBuffer replaceBytesInRange:NSMakeRange(0, avail) withBytes:NULL length:0];
            dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, conn.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            if (completion) completion(dd, NULL, false, NULL);
        } else {
            conn.receiveCompletion = completion;
        }
    });
}

void nw_connection_send(nw_connection_t connection,
                        dispatch_data_t content,
                        nw_content_context_t context,
                        bool is_complete,
                        nw_connection_send_completion_t completion) {
    SSBConnection *conn = (SSBConnection *)connection;
    dispatch_async(conn.queue, ^{
        if (conn.state != nw_connection_state_ready && conn.state != nw_connection_state_waiting) {
            if (completion) completion(NULL);
            return;
        }
        const void *bytes = NULL; size_t len = 0;
        dispatch_data_create_map(content, &bytes, &len);
        if (conn.topFramer && conn.topFramer.outputHandler) {
            conn.topFramer.outputHandler(conn.topFramer.framer, NULL, len, true);
        } else {
            NSData *nsdata = [NSData dataWithBytes:bytes length:len];
            [conn enqueueWrite:dispatch_data_create(nsdata.bytes, nsdata.length, conn.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT)];
        }
        if (completion) completion(NULL);
    });
}

void nw_connection_cancel(nw_connection_t connection) {
    SSBConnection *conn = (SSBConnection *)connection;
    dispatch_async(conn.queue, ^{
        [conn setState:nw_connection_state_cancelled];
        [conn close];
    });
}

#pragma mark - Framer Shim

static NSMutableDictionary *_framerDefMap = nil;

static dispatch_queue_t framer_queue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ _framerDefMap = [NSMutableDictionary dictionary]; });
    return shim_queue();
}

nw_protocol_definition_t nw_framer_create_definition(const char *identifier,
                                                      uint32_t flags,
                                                      nw_framer_start_handler_t start_handler) {
    NSString *key = [NSString stringWithUTF8String:identifier];
    __block SSBFramerContext *sharedCtx = nil;
    SSBFramerContext *(^definition)(void) = ^{
        if (!sharedCtx) {
            sharedCtx = [[SSBFramerContext alloc] init];
            sharedCtx.startHandler = start_handler;
        }
        return sharedCtx;
    };
    dispatch_sync(framer_queue(), ^{
        _framerDefMap[key] = [definition copy];
    });
    return (nw_protocol_definition_t)[definition copy];
}

nw_protocol_options_t nw_framer_create_options(nw_protocol_definition_t definition) {
    SSBFramerContext *(^defBlock)(void) = (id)definition;
    return (nw_protocol_options_t)defBlock();
}

nw_protocol_options_t nw_framer_copy_options(nw_framer_t framer) {
    return framer;
}

void nw_framer_options_set_object_value(nw_protocol_options_t options,
                                        const char *key, id value) {}

id nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key) {
    return nil;
}

void nw_framer_set_input_handler(nw_framer_t framer,
                                  nw_framer_input_handler_t input_handler) {
    dispatch_sync(framer_queue(), ^{
        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!ctx) {
            ctx = [[SSBFramerContext alloc] init];
            ctx.framer = framer;
            _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]] = ctx;
        }
        ctx.inputHandler = input_handler;
    });
}

void nw_framer_set_output_handler(nw_framer_t framer,
                                   nw_framer_output_handler_t output_handler) {
    dispatch_sync(framer_queue(), ^{
        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!ctx) {
            ctx = [[SSBFramerContext alloc] init];
            ctx.framer = framer;
            _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]] = ctx;
        }
        ctx.outputHandler = output_handler;
    });
}

void nw_framer_mark_ready(nw_framer_t framer) {
    dispatch_sync(framer_queue(), ^{
        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (ctx) ctx.isReady = YES;
    });
}

void nw_framer_mark_failed_with_error(nw_framer_t framer, int error_code) {
    dispatch_sync(framer_queue(), ^{
        SSBConnection *conn = _connectionMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (conn) [conn setState:nw_connection_state_failed];
    });
}

static NSMutableData *buffer_for_framer(nw_framer_t framer) {
    __block NSMutableData *buf = nil;
    dispatch_sync(framer_queue(), ^{
        SSBConnection *conn = _connectionMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (conn) {
            SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
            if (ctx && ctx.nextFramer) {
                buf = ctx.nextFramer.inputBuffer;
            } else if (conn.topFramer && ctx == conn.topFramer) {
                buf = conn.socketReadBuffer;
            }
        }
    });
    return buf;
}

bool nw_framer_parse_input(nw_framer_t framer,
                             size_t minimum_incomplete_length,
                             size_t maximum_length,
                             uint8_t *temp_buffer,
                             nw_framer_parse_completion_t parse_completion) {
    __block BOOL called = NO;
    __block size_t result = 0;
    dispatch_sync(framer_queue(), ^{
        SSBConnection *conn = _connectionMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!conn) return;
        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        NSMutableData *buf = nil;
        if (ctx && ctx.nextFramer) {
            buf = ctx.nextFramer.inputBuffer;
        } else if (conn.topFramer && ctx == conn.topFramer) {
            buf = conn.socketReadBuffer;
        }
        if (!buf) return;

        while (buf.length < minimum_incomplete_length) {
            uint8_t tmp[16384];
            ssize_t n = recv(conn.sockfd, tmp, sizeof(tmp), 0);
            if (n > 0) {
                [buf appendBytes:tmp length:n];
            } else if (n == 0) {
                break;
            } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
                struct pollfd pfd = { .fd = conn.sockfd, .events = POLLIN };
                if (poll(&pfd, 1, -1) <= 0) break;
            } else {
                break;
            }
        }

        if (buf.length >= minimum_incomplete_length) {
            size_t avail = MIN(buf.length, maximum_length);
            NSData *data = [buf subdataWithRange:NSMakeRange(0, avail)];
            result = parse_completion((uint8_t *)data.bytes, data.length,
                                     buf.length >= minimum_incomplete_length);
            called = YES;
            if (result > 0 && result <= buf.length) {
                [buf replaceBytesInRange:NSMakeRange(0, result) withBytes:NULL length:0];
            }
        }
    });
    return called;
}

void nw_framer_parse_output(nw_framer_t framer,
                              size_t minimum_incomplete_length,
                              size_t maximum_length,
                              uint8_t *temp_buffer,
                              nw_framer_parse_completion_t parse_completion) {
    dispatch_sync(framer_queue(), ^{
        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!ctx || !ctx.outputHandler) return;
        ctx.outputHandler(framer, NULL, maximum_length, true);
    });
}

void nw_framer_write_output_data(nw_framer_t framer, dispatch_data_t data) {
    dispatch_sync(framer_queue(), ^{
        SSBConnection *conn = _connectionMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!conn) return;
        const void *bytes = NULL; size_t len = 0;
        dispatch_data_create_map(data, &bytes, &len);

        SSBFramerContext *ctx = _framerContextMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (ctx.nextFramer) {
            [ctx.nextFramer.inputBuffer appendBytes:bytes length:len];
            if (ctx.nextFramer.inputHandler) {
                ctx.nextFramer.inputHandler(ctx.nextFramer.framer);
            }
        } else if (conn.bottomFramer && !conn.bottomFramer.nextFramer && conn.bottomFramer == ctx) {
            [conn writeToSocket:bytes length:len];
        } else {
            [conn writeToSocket:bytes length:len];
        }
    });
}

void nw_framer_deliver_input(nw_framer_t framer,
                              const void *input_buffer,
                              size_t input_length,
                              nw_framer_message_t message,
                              bool is_complete) {
    dispatch_sync(framer_queue(), ^{
        SSBConnection *conn = _connectionMap[[NSValue valueWithPointer:(__bridge const void *)framer]];
        if (!conn) return;
        if (conn.receiveCompletion && input_length > 0) {
            NSData *data = [NSData dataWithBytes:input_buffer length:input_length];
            dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, conn.queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_receive_completion_t comp = conn.receiveCompletion;
            conn.receiveCompletion = nil;
            comp(dd, (nw_content_context_t)message, is_complete, NULL);
        }
    });
}

nw_framer_message_t nw_framer_message_create(nw_framer_t framer) {
    return (nw_framer_message_t)[[NSObject alloc] init];
}

void nw_framer_message_set_object_value(nw_framer_message_t message,
                                          const char *key, id value) {
    objc_setAssociatedObject((id)message, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

id nw_framer_message_copy_object_value(nw_framer_message_t message, const char *key) {
    return objc_getAssociatedObject((id)message, key);
}

nw_protocol_metadata_t nw_content_context_copy_protocol_metadata(nw_content_context_t context,
                                                                   nw_protocol_definition_t definition) {
    return context;
}

void nw_tcp_options_set_no_delay(nw_protocol_options_t options, bool no_delay) {
    ((SSBParameters *)options).noDelay = no_delay;
}

#pragma mark - Listener Shim

nw_listener_t nw_listener_create(nw_parameters_t parameters) {
    SSBListener *l = [[SSBListener alloc] init];
    l.queue = shim_queue();
    return (nw_listener_t)l;
}

void nw_listener_set_queue(nw_listener_t listener, dispatch_queue_t queue) {
    SSBListener *l = (SSBListener *)listener;
    if (queue) l.queue = queue;
}

void nw_listener_set_state_changed_handler(nw_listener_t listener,
                                             nw_listener_state_changed_handler_t handler) {
    ((SSBListener *)listener).stateHandler = handler;
}

void nw_listener_set_new_connection_handler(nw_listener_t listener,
                                             nw_listener_new_connection_handler_t handler) {
    ((SSBListener *)listener).newConnectionHandler = handler;
}

void nw_listener_start(nw_listener_t listener) {
    SSBListener *l = (SSBListener *)listener;
    dispatch_async(l.queue, ^{
        [l setState:nw_listener_state_waiting];
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) { [l setState:nw_listener_state_failed]; return; }
        int yes = 1;
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = 0;
        if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
            listen(sock, 128) < 0) {
            close(sock);
            [l setState:nw_listener_state_failed];
            return;
        }
        struct sockaddr_in bound; socklen_t blen = sizeof(bound);
        getsockname(sock, (struct sockaddr *)&bound, &blen);
        l.port = ntohs(bound.sin_port);
        int flags = fcntl(sock, F_GETFL, 0);
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);
        l.sockfd = sock;
        [l setState:nw_listener_state_ready];
        [l armAcceptSource];
    });
}

void nw_listener_cancel(nw_listener_t listener) {
    SSBListener *l = (SSBListener *)listener;
    dispatch_async(l.queue, ^{
        [l setState:nw_listener_state_cancelled];
        [l cancel];
    });
}

uint16_t nw_listener_get_port(nw_listener_t listener) {
    return ((SSBListener *)listener).port;
}

#endif
