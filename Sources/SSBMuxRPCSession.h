#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBMuxRPCMessage;

typedef void (^SSBRPCCallback)(id _Nullable response, NSError * _Nullable error);

@interface SSBMuxRPCSession : NSObject

@property (nonatomic, copy, nullable) void (^sendMessageBlock)(SSBMuxRPCMessage *message);

- (void)handleIncomingMessage:(SSBMuxRPCMessage *)message;

- (void)sendRequest:(NSArray<NSString *> *)method
               args:(NSArray<id> *)args
               type:(NSString *)type
         completion:(nullable SSBRPCCallback)completion;

@end

NS_ASSUME_NONNULL_END
