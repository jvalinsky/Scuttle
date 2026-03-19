#import "SSBMuxRPCSession.h"
#import "SSBMuxRPC.h"
#import "SSBLogCompat.h"
#import <stdatomic.h>

static os_log_t rpc_log;
static const void *SSBMuxRPCSessionAccessQueueKey = &SSBMuxRPCSessionAccessQueueKey;

@interface SSBMuxRPCSession ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallback> *pendingRequests;
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
    } else if (data) {
        flags |= SSBMuxRPCFlagTypeJSON;
        bodyData = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
    }
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:requestID body:bodyData];
    if (self.sendMessageBlock) {
        self.sendMessageBlock(msg);
    }
}

- (void)handleIncomingMessage:(SSBMuxRPCMessage *)message {
    os_log_debug(rpc_log, "handleIncomingMessage called: req=%d flags=%u", message.requestNumber, message.flags);
    BOOL isStream = (message.flags & SSBMuxRPCFlagStream) != 0;
    BOOL isEndErr = (message.flags & SSBMuxRPCFlagEndErr) != 0;
    
    int32_t reqID = message.requestNumber;
    __block SSBRPCCallback callback = nil;
    [self performAccessQueueSync:^{
        callback = self.pendingRequests[@(reqID)];
        if (!callback && reqID < 0) {
            callback = self.pendingRequests[@(-reqID)];
        }
    }];

    if (callback) {
        // Response to our request
        os_log_debug(rpc_log, "Handling RESPONSE for ID %d flags=%u", reqID, message.flags);
        
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            NSError *err = nil;
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:NSJSONReadingAllowFragments error:&err];
            if (err) os_log_error(rpc_log, "JSON parse failed: %{public}@", err);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        os_log_debug(rpc_log, "Parsed body: %{public}@", parsedBody);
        
        if (isEndErr) {
            BOOL isError = NO;
            NSError *error = nil;
            if ([parsedBody isKindOfClass:[NSDictionary class]] && parsedBody[@"name"] && [parsedBody[@"name"] containsString:@"Error"]) {
                isError = YES;
                error = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{NSLocalizedDescriptionKey: parsedBody[@"message"] ?: @"Unknown RPC Error"}];
            } else if ([parsedBody isKindOfClass:[NSString class]]) {
                NSString *strBody = (NSString *)parsedBody;
                if ([strBody rangeOfString:@"Error" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    isError = YES;
                    error = [NSError errorWithDomain:@"SSBMuxRPC" code:-1 userInfo:@{NSLocalizedDescriptionKey: strBody}];
                }
            }
            
            if (callback) {
                if (isError) {
                    os_log_debug(rpc_log, "Executing callback for ID %d (error)", reqID);
                    callback(nil, error);
                    os_log_debug(rpc_log, "Completed callback for ID %d (error)", reqID);
                } else if (!isStream) {
                    os_log_debug(rpc_log, "Executing callback for ID %d (non-stream final value)", reqID);
                    callback(parsedBody, nil);
                    os_log_debug(rpc_log, "Completed callback for ID %d (non-stream final value)", reqID);
                } else if (parsedBody && ![parsedBody isEqual:@YES]) {
                    // For legacy streams, the final value might come with EndErr: true
                    os_log_debug(rpc_log, "Executing callback for ID %d (stream final value with EndErr)", reqID);
                    callback(parsedBody, nil);
                    os_log_debug(rpc_log, "Completed callback for ID %d (stream final value with EndErr)", reqID);
                }
            }
            
            // Only remove callback if this is NOT a stream, OR if it's the end of a stream
            // (i.e., if it's a stream and not EndErr, we keep the callback for more data)
            dispatch_async(self.accessQueue, ^{
                [self.pendingRequests removeObjectForKey:@(reqID)];
            });
        } else {
            if (callback) {
                os_log_debug(rpc_log, "Executing callback for ID %d (stream data)", reqID);
                callback(parsedBody, nil);
                os_log_debug(rpc_log, "Completed callback for ID %d (stream data)", reqID);
                if (!isStream) {
                    dispatch_async(self.accessQueue, ^{
                        [self.pendingRequests removeObjectForKey:@(reqID)];
                    });
                }
            }
        }
    } else {
        // Request from remote
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:NSJSONReadingAllowFragments error:nil];
            os_log_debug(rpc_log, "Parsed REMOTE REQUEST payload: %{public}@", parsedBody);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        if (self.receiveRequestBlock) {
            os_log_debug(rpc_log, "Dispatching REMOTE REQUEST: req=%d flags=%d", message.requestNumber, message.flags);
            self.receiveRequestBlock(parsedBody, message.requestNumber, message.flags);
        }
    }
}

@end
