#import "SSBMuxRPCSession.h"
#import "SSBMuxRPC.h"
#import <os/log.h>

static os_log_t rpc_log;

@interface SSBMuxRPCSession ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SSBRPCCallback> *pendingRequests;
@property (nonatomic, assign) int32_t nextRequestID;
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
    }
    return self;
}

- (void)sendRequest:(NSArray<NSString *> *)method
               args:(NSArray<id> *)args
               type:(NSString *)type
         completion:(nullable SSBRPCCallback)completion {
    
    int32_t reqNum = self.nextRequestID++;
    
    NSDictionary *bodyDict = @{
        @"name": method,
        @"args": args,
        @"type": type
    };
    
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:&jsonError];
    
    if (jsonError) {
        os_log_error(rpc_log, "JSON encoding error for RPC request: %{public}@", jsonError);
        if (completion) {
            completion(nil, jsonError);
        }
        return;
    }
    
    SSBMuxRPCFlags flags = SSBMuxRPCFlagTypeJSON;
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:flags requestNumber:reqNum body:bodyData];
    
    if (completion) {
        self.pendingRequests[@(reqNum)] = [completion copy];
    }
    
    if (self.sendMessageBlock) {
        self.sendMessageBlock(msg);
    }
}

- (void)handleIncomingMessage:(SSBMuxRPCMessage *)message {
    BOOL isStream = (message.flags & SSBMuxRPCFlagStream) != 0;
    BOOL isEndErr = (message.flags & SSBMuxRPCFlagEndErr) != 0;
    
    if (message.requestNumber < 0) {
        // Response to our request
        int32_t reqNum = -message.requestNumber; // Requests are positive, responses are negative
        
        id parsedBody = nil;
        if ((message.flags & SSBMuxRPCFlagTypeJSON) && message.body.length > 0) {
            parsedBody = [NSJSONSerialization JSONObjectWithData:message.body options:0 error:nil];
        } else if ((message.flags & SSBMuxRPCFlagTypeString) && message.body.length > 0) {
            parsedBody = [[NSString alloc] initWithData:message.body encoding:NSUTF8StringEncoding];
        }
        
        SSBRPCCallback callback = self.pendingRequests[@(reqNum)];
        
        if (isEndErr) {
            // Check if it's just a normal end of stream
            BOOL isError = NO;
            NSError *error = nil;
            if ([parsedBody isKindOfClass:[NSDictionary class]] && [parsedBody[@"name"] isEqualToString:@"Error"]) {
                isError = YES;
                error = [NSError errorWithDomain:@"SSBMuxRPCErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: parsedBody[@"message"] ?: @"Unknown RPC Error"}];
            } else if ([parsedBody isKindOfClass:[NSNumber class]] && [parsedBody boolValue] == YES) {
                // Just true => stream ended normally
            }
            
            if (callback) {
                if (isError) {
                    callback(nil, error);
                } else if (!isStream) {
                    callback(parsedBody, nil);
                }
            }
            [self.pendingRequests removeObjectForKey:@(reqNum)];
        } else {
            if (callback) {
                callback(parsedBody, nil);
                if (!isStream) {
                    [self.pendingRequests removeObjectForKey:@(reqNum)];
                }
            }
        }
    } else {
        // Incoming request from remote to us
        os_log_debug(rpc_log, "Received incoming request #%d. Not handling yet.", message.requestNumber);
    }
}

@end