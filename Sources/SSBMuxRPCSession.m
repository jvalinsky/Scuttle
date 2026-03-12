#import "SSBMuxRPCSession.h"
#import "SSBMuxRPC.h"
#import <os/log.h>

static os_log_t rpc_log;

@interface SSBMuxRPCSession ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallback> *pendingRequests;
@property (nonatomic, assign) int32_t nextRequestID;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
@end

@implementation SSBMuxRPCSession

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
    }
    return self;
}

- (int32_t)sendRequest:(NSArray<NSString *> *)method
               args:(NSArray<id> *)args
               type:(NSString *)type
         completion:(nullable SSBRPCCallback)completion {
    __block int32_t reqNum;
    dispatch_sync(self.accessQueue, ^{
        reqNum = self.nextRequestID++;
        if (completion) {
            self.pendingRequests[@(reqNum)] = [completion copy];
        }
    });

    NSLog(@"[ROOM_DIAG] Session: sendRequest: %@, reqNum: %d", method, reqNum);
    
    NSDictionary *bodyDict = @{
        @"name": method,
        @"args": args,
        @"type": type
    };
    
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:&jsonError];
    
    if (jsonError) {
        os_log_error(rpc_log, "JSON encoding error for RPC request: %{public}@", jsonError);
        dispatch_async(self.accessQueue, ^{
            [self.pendingRequests removeObjectForKey:@(reqNum)];
        });
        if (completion) {
            completion(nil, jsonError);
        }
        return -1;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    NSLog(@"[ROOM_DIAG] Session: JSON payload: %@", jsonString);
    
    SSBMuxRPCFlags flags = SSBMuxRPCFlagTypeJSON;
    if ([type isEqualToString:@"source"] || [type isEqualToString:@"sink"] || [type isEqualToString:@"duplex"]) {
        flags |= SSBMuxRPCFlagStream;
    }
    
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:bodyData];
    
    NSLog(@"[ROOM_DIAG] Session: Sending request %@ req=%d flags=%u", method, reqNum, flags);
    
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
    NSLog(@"[RPCSession %p] handleIncomingMessage called: req=%d flags=%u", self, message.requestNumber, message.flags);
    BOOL isStream = (message.flags & SSBMuxRPCFlagStream) != 0;
    BOOL isEndErr = (message.flags & SSBMuxRPCFlagEndErr) != 0;
    
    int32_t reqID = message.requestNumber;
    __block SSBRPCCallback callback = nil;
    dispatch_sync(self.accessQueue, ^{
        callback = self.pendingRequests[@(reqID)];
        if (!callback && reqID < 0) {
            callback = self.pendingRequests[@(-reqID)];
        }
    });

    if (callback) {
        // Response to our request
        NSLog(@"[RPCSession %p] Handling RESPONSE for ID %d flags=%u (callback=%p)", self, reqID, message.flags, (__bridge void *)callback);
        
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            NSError *err = nil;
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:NSJSONReadingAllowFragments error:&err];
            if (err) NSLog(@"[RPCSession] Session ERROR: JSON parse failed: %@", err);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        NSLog(@"[RPCSession %p] Parsed body: %@", self, parsedBody);
        
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
                    NSLog(@"[RPCSession %p] EXECUTING callback for ID %d (error) callback=%p", self, reqID, (__bridge void *)callback);
                    callback(nil, error);
                    NSLog(@"[RPCSession %p] COMPLETED callback for ID %d (error)", self, reqID);
                } else if (!isStream) {
                    NSLog(@"[RPCSession %p] EXECUTING callback for ID %d (non-stream final value) callback=%p", self, reqID, (__bridge void *)callback);
                    callback(parsedBody, nil);
                    NSLog(@"[RPCSession %p] COMPLETED callback for ID %d (non-stream final value)", self, reqID);
                } else if (parsedBody && ![parsedBody isEqual:@YES]) {
                    // For legacy streams, the final value might come with EndErr: true
                    NSLog(@"[RPCSession %p] EXECUTING callback for ID %d (stream final value with EndErr) callback=%p", self, reqID, (__bridge void *)callback);
                    callback(parsedBody, nil);
                    NSLog(@"[RPCSession %p] COMPLETED callback for ID %d (stream final value with EndErr)", self, reqID);
                }
            }
            
            // Only remove callback if this is NOT a stream, OR if it's the end of a stream
            // (i.e., if it's a stream and not EndErr, we keep the callback for more data)
            dispatch_async(self.accessQueue, ^{
                [self.pendingRequests removeObjectForKey:@(reqID)];
            });
        } else {
            if (callback) {
                NSLog(@"[RPCSession %p] EXECUTING callback for ID %d (stream data) callback=%p", self, reqID, (__bridge void *)callback);
                callback(parsedBody, nil);
                NSLog(@"[RPCSession %p] COMPLETED callback for ID %d (stream data)", self, reqID);
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
            NSLog(@"[RPCSession %p] Parsed REMOTE REQUEST payload: %@", self, parsedBody);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        if (self.receiveRequestBlock) {
            NSLog(@"[RPCSession %p] Dispatching REMOTE REQUEST: req=%d flags=%d", self, message.requestNumber, message.flags);
            self.receiveRequestBlock(parsedBody, message.requestNumber, message.flags);
        }
    }
}

@end