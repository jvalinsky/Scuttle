#import "SSBMuxRPCSession.h"
#import "SSBMuxRPC.h"
#import "SSBLogCompat.h"
#import <stdatomic.h>
#import <stdlib.h>

static os_log_t rpc_log;
static const void *SSBMuxRPCSessionAccessQueueKey = &SSBMuxRPCSessionAccessQueueKey;

@interface SSBMuxRPCSession ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallback> *pendingRequests;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeIncomingRequests;
@property (nonatomic, assign) _Atomic int32_t nextRequestID;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t accessQueue;
@end

@implementation SSBMuxRPCSession

- (void)performAccessQueueSync:(dispatch_block_t)block {
    if (dispatch_get_specific(SSBMuxRPCSessionAccessQueueKey)) {
        block();
        return;
    }
    dispatch_sync(self.accessQueue, block);
}

+ (void)initialize {
    if (self == [SSBMuxRPCSession class]) {
        rpc_log = os_log_create("com.scuttlebutt.network", "MuxRPC");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pendingRequests = [NSMutableDictionary dictionary];
        _activeIncomingRequests = [NSMutableSet set];
        _nextRequestID = 1;
        _accessQueue = dispatch_queue_create("com.scuttlebutt.muxrpc.session", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_accessQueue,
                                    SSBMuxRPCSessionAccessQueueKey,
                                    (void *)SSBMuxRPCSessionAccessQueueKey,
                                    NULL);
    }
    return self;
}

- (int32_t)sendRequest:(NSArray<NSString *> *)method
               args:(NSArray<id> *)args
               type:(NSString *)type
         completion:(nullable SSBRPCCallback)completion {
    int32_t reqNum = atomic_fetch_add_explicit(&_nextRequestID, 1, memory_order_relaxed);
    if (completion) {
        [self performAccessQueueSync:^{
            self.pendingRequests[@(reqNum)] = [completion copy];
        }];
    }

    os_log_debug(rpc_log, "Session: sendRequest: %{public}@, reqNum: %d", method, reqNum);
    
    NSDictionary *bodyDict = @{
        @"name": method,
        @"args": args,
        @"type": type
    };
    
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:&jsonError];
    
    if (jsonError) {
        os_log_error(rpc_log, "JSON encoding error for RPC request: %{public}@", jsonError);
        [self performAccessQueueSync:^{
            [self.pendingRequests removeObjectForKey:@(reqNum)];
        }];
        if (completion) {
            completion(nil, jsonError);
        }
        return -1;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    os_log_debug(rpc_log, "Session: JSON payload: %{public}@", jsonString);
    
    SSBMuxRPCFlags flags = SSBMuxRPCFlagTypeJSON;
    if ([type isEqualToString:@"source"] || [type isEqualToString:@"sink"] || [type isEqualToString:@"duplex"]) {
        flags |= SSBMuxRPCFlagStream;
    }
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:bodyData];
    
    os_log_debug(rpc_log, "Session: Sending request %{public}@ req=%d flags=%u", method, reqNum, flags);
    
    if (self.sendMessageBlock) {
        self.sendMessageBlock(msg);
    }
    
    return reqNum;
}

- (void)sendData:(id)data forRequest:(int32_t)requestID isEnd:(BOOL)isEnd {
    SSBMuxRPCFlags flags = SSBMuxRPCFlagStream;
    if (isEnd) flags |= SSBMuxRPCFlagEndErr;
    
    NSData *bodyData = nil;
    if ([data isKindOfClass:[NSData class]]) {
        bodyData = data;
    } else if ([data isKindOfClass:[NSString class]]) {
        flags |= SSBMuxRPCFlagTypeString;
        bodyData = [(NSString *)data dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([data isKindOfClass:[NSNumber class]]) {
        // NSJSONSerialization rejects top-level scalars; encode manually.
        flags |= SSBMuxRPCFlagTypeJSON;
        NSString *fragment = [(NSNumber *)data boolValue] ? @"true" : @"false";
        bodyData = [fragment dataUsingEncoding:NSUTF8StringEncoding];
    } else if (data) {
        flags |= SSBMuxRPCFlagTypeJSON;
        bodyData = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
    }
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:requestID body:bodyData];
    if (self.sendMessageBlock) {
        self.sendMessageBlock(msg);
    }
}

- (id _Nullable)parsedBodyForMessage:(SSBMuxRPCMessage *)message {
    if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
        NSError *err = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:message.body
                                                    options:NSJSONReadingAllowFragments
                                                      error:&err];
        if (err) {
            NSLog(@"[DEBUG_MuxRPC] JSON parse failed fallback to NSData for reqNum %d: %@", message.requestNumber, err.localizedDescription);
            return message.body;
        }
        return parsed;
    }

    if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
        return [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
    }

    return message.body;
}

- (BOOL)isRequestEnvelopePayload:(id _Nullable)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *dict = (NSDictionary *)payload;
    return [dict[@"name"] isKindOfClass:[NSArray class]] &&
           [dict[@"args"] isKindOfClass:[NSArray class]];
}

- (nullable NSError *)errorFromEndPayload:(id _Nullable)payload {
    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)payload;
        id nameValue = dict[@"name"];
        if ([nameValue isKindOfClass:[NSString class]] &&
            [(NSString *)nameValue rangeOfString:@"Error" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return [NSError errorWithDomain:@"SSBMuxRPC"
                                       code:-1
                                   userInfo:@{NSLocalizedDescriptionKey: dict[@"message"] ?: @"Unknown RPC Error"}];
        }
    } else if ([payload isKindOfClass:[NSString class]]) {
        NSString *text = (NSString *)payload;
        if ([text rangeOfString:@"Error" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return [NSError errorWithDomain:@"SSBMuxRPC"
                                       code:-1
                                   userInfo:@{NSLocalizedDescriptionKey: text}];
        }
    }

    return nil;
}

- (void)handleIncomingMessage:(SSBMuxRPCMessage *)message {
    os_log_debug(rpc_log, "handleIncomingMessage called: req=%d flags=%u", message.requestNumber, message.flags);
    BOOL isStream = (message.flags & SSBMuxRPCFlagStream) != 0;
    BOOL isEndErr = (message.flags & SSBMuxRPCFlagEndErr) != 0;
    int32_t reqID = message.requestNumber;
    NSNumber *absReqKey = @(llabs((long long)reqID));
    id parsedBody = [self parsedBodyForMessage:message];
    BOOL isRequestEnvelope = [self isRequestEnvelopePayload:parsedBody];

    __block SSBRPCCallback callback = nil;
    __block NSNumber *callbackKey = nil;
    __block BOOL isIncomingRequest = NO;
    [self performAccessQueueSync:^{
        if (isRequestEnvelope) {
            [self.activeIncomingRequests addObject:absReqKey];
            isIncomingRequest = YES;
        } else if ([self.activeIncomingRequests containsObject:absReqKey]) {
            isIncomingRequest = YES;
        }

        if (!isIncomingRequest) {
            if (reqID < 0) {
                NSNumber *normalizedKey = @(-reqID);
                callback = self.pendingRequests[normalizedKey];
                if (callback) {
                    callbackKey = normalizedKey;
                }
            } else {
                NSNumber *normalizedKey = @(reqID);
                callback = self.pendingRequests[normalizedKey];
                if (callback) {
                    callbackKey = normalizedKey;
                }
            }
        }
    }];

    if (callback) {
        os_log_debug(rpc_log, "Handling RESPONSE for ID %d flags=%u", reqID, message.flags);
        os_log_debug(rpc_log, "Parsed body: %{public}@", parsedBody);

        if (isEndErr) {
            NSError *error = [self errorFromEndPayload:parsedBody];
            if (error) {
                os_log_debug(rpc_log, "Executing callback for ID %d (error)", reqID);
                callback(nil, error);
                os_log_debug(rpc_log, "Completed callback for ID %d (error)", reqID);
            } else if (!isStream) {
                os_log_debug(rpc_log, "Executing callback for ID %d (non-stream final value)", reqID);
                callback(parsedBody, nil);
                os_log_debug(rpc_log, "Completed callback for ID %d (non-stream final value)", reqID);
            } else if (parsedBody && ![parsedBody isEqual:@YES]) {
                os_log_debug(rpc_log, "Executing callback for ID %d (stream final value with EndErr)", reqID);
                callback(parsedBody, nil);
                os_log_debug(rpc_log, "Completed callback for ID %d (stream final value with EndErr)", reqID);
            } else {
                // Clean stream end: @YES sentinel or empty body. Signal end-of-stream to
                // the consumer with (nil, nil) so source-stream handlers (e.g. blobs.get)
                // know when all chunks have arrived.
                os_log_debug(rpc_log, "Executing callback for ID %d (clean stream end)", reqID);
                callback(nil, nil);
                os_log_debug(rpc_log, "Completed callback for ID %d (clean stream end)", reqID);
            }

            [self performAccessQueueSync:^{
                if (callbackKey) {
                    [self.pendingRequests removeObjectForKey:callbackKey];
                }
            }];
        } else {
            os_log_debug(rpc_log, "Executing callback for ID %d (stream data)", reqID);
            callback(parsedBody, nil);
            os_log_debug(rpc_log, "Completed callback for ID %d (stream data)", reqID);
            if (!isStream) {
                [self performAccessQueueSync:^{
                    if (callbackKey) {
                        [self.pendingRequests removeObjectForKey:callbackKey];
                    }
                }];
            }
        }
        return;
    }

    os_log_debug(rpc_log, "Parsed REMOTE REQUEST payload: %{public}@", parsedBody);
    if (self.receiveRequestBlock) {
        os_log_debug(rpc_log, "Dispatching REMOTE REQUEST: req=%d flags=%d", message.requestNumber, message.flags);
        self.receiveRequestBlock(parsedBody, message.requestNumber, message.flags);
    }

    if (isEndErr || !isStream) {
        [self performAccessQueueSync:^{
            [self.activeIncomingRequests removeObject:absReqKey];
        }];
    }
}

@end
