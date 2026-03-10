#import <Foundation/Foundation.h>

#import "SSBMuxRPC.h"

NS_ASSUME_NONNULL_BEGIN

@class SSBMuxRPCMessage;

@interface SSBMuxRPCSession : NSObject

@property (nonatomic, copy, nullable) void (^sendMessageBlock)(SSBMuxRPCMessage *message);
@property (nonatomic, copy, nullable) void (^receiveRequestBlock)(id payload, int32_t requestID, uint8_t flags);

- (void)handleIncomingMessage:(SSBMuxRPCMessage *)message;

- (void)sendRequest:(NSArray<NSString *> *)method
               args:(NSArray<id> *)args
               type:(NSString *)type
         completion:(nullable SSBRPCCallback)completion;

@end

NS_ASSUME_NONNULL_END