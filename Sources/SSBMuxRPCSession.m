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
    NSLog(@"[ROOM_DIAG] Session: handleIncomingMessage called: req=%d", message.requestNumber);
    BOOL isStream = (message.flags & SSBMuxRPCFlagStream) != 0;
    BOOL isEndErr = (message.flags & SSBMuxRPCFlagEndErr) != 0;
    
    if (message.requestNumber < 0) {
        // Response to our request
        int32_t reqNum = -message.requestNumber;
        NSLog(@"[ROOM_DIAG] Session: Handling RESPONSE for req=%d (raw=%d) flags=%u bodyLen=%lu", reqNum, message.requestNumber, message.flags, (unsigned long)message.body.length);
        
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            NSError *err = nil;
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:NSJSONReadingAllowFragments error:&err];
            if (err) NSLog(@"[ROOM_DIAG] Session ERROR: JSON parse failed: %@", err);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        NSLog(@"[ROOM_DIAG] Session: Parsed body: %@", parsedBody);
        
        __block SSBRPCCallback callback = nil;
        dispatch_sync(self.accessQueue, ^{
            callback = self.pendingRequests[@(reqNum)];
        });

        if (!callback) {
            NSLog(@"[ROOM_DIAG] Session: NO CALLBACK FOUND for req=%d.", reqNum);
        }
        
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
                    callback(nil, error);
                } else if (!isStream) {
                    callback(parsedBody, nil);
                } else if (parsedBody && ![parsedBody isEqual:@YES]) {
                    // For legacy streams, the final value might come with EndErr: true
                    callback(parsedBody, nil);
                }
            }
            
            // Only remove callback if this is NOT a stream, OR if it's the end of a stream
            if (!isStream || isEndErr) {
                dispatch_async(self.accessQueue, ^{
                    [self.pendingRequests removeObjectForKey:@(reqNum)];
                });
            }
        } else {
            if (callback) {
                callback(parsedBody, nil);
                if (!isStream) {
                    dispatch_async(self.accessQueue, ^{
                        [self.pendingRequests removeObjectForKey:@(reqNum)];
                    });
                }
            }
        }
    } else {
        // Request from remote
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:NSJSONReadingAllowFragments error:nil];
            NSLog(@"[RPCSession] Parsed REMOTE REQUEST payload: %@", parsedBody);
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        } else {
            parsedBody = message.body;
        }
        
        if (self.receiveRequestBlock) {
            NSLog(@"[RPCSession] Dispatching REMOTE REQUEST: req=%d flags=%d", message.requestNumber, message.flags);
            self.receiveRequestBlock(parsedBody, message.requestNumber, message.flags);
        }
    }
}

@end