#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SSBTransportConnectionState) {
    SSBTransportConnectionStateInvalid = 0,
    SSBTransportConnectionStateWaiting = 1,
    SSBTransportConnectionStatePreparing = 2,
    SSBTransportConnectionStateReady = 3,
    SSBTransportConnectionStateFailed = 4,
    SSBTransportConnectionStateCancelled = 5,
};

typedef NS_ENUM(NSUInteger, SSBTransportListenerState) {
    SSBTransportListenerStateInvalid = 0,
    SSBTransportListenerStateWaiting = 1,
    SSBTransportListenerStateReady = 2,
    SSBTransportListenerStateFailed = 3,
    SSBTransportListenerStateCancelled = 4,
};

FOUNDATION_EXPORT NSString * const SSBTransportMetadataFlagsKey;
FOUNDATION_EXPORT NSString * const SSBTransportMetadataRequestNumberKey;

@protocol SSBTransportConnection;
@protocol SSBTransportListener;

typedef void (^SSBTransportConnectionStateHandler)(id<SSBTransportConnection> connection,
                                                   SSBTransportConnectionState state,
                                                   NSError * _Nullable error);
typedef void (^SSBTransportConnectionReceiveHandler)(NSData * _Nullable content,
                                                     NSDictionary<NSString *, id> * _Nullable metadata,
                                                     BOOL isComplete,
                                                     NSError * _Nullable error);
typedef void (^SSBTransportConnectionSendHandler)(NSError * _Nullable error);
typedef void (^SSBTransportListenerStateHandler)(id<SSBTransportListener> listener,
                                                 SSBTransportListenerState state,
                                                 NSError * _Nullable error);
typedef void (^SSBTransportListenerNewConnectionHandler)(id<SSBTransportConnection> connection);

@interface SSBTransportEndpoint : NSObject

@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, assign, readonly) uint16_t port;

+ (instancetype)endpointWithHost:(NSString *)host port:(uint16_t)port;
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SSBTransportConnectionOptions : NSObject

@property (nonatomic, assign) BOOL enableTCPNoDelay;
@property (nonatomic, assign) BOOL enableSecurityFramer;
@property (nonatomic, assign) BOOL enableMuxRPCFramer;
@property (nonatomic, assign) BOOL actingAsClient;
@property (nonatomic, strong, nullable) NSData *localIdentitySecret;
@property (nonatomic, strong, nullable) NSData *remotePublicKey;

@end

@protocol SSBTransportConnection <NSObject>

@property (nonatomic, assign, readonly) SSBTransportConnectionState state;
@property (nonatomic, strong, readonly, nullable) SSBTransportEndpoint *endpoint;

- (void)setStateChangedHandler:(nullable SSBTransportConnectionStateHandler)handler;
- (void)start;
- (void)cancel;
- (void)receiveMessageWithCompletion:(SSBTransportConnectionReceiveHandler)completion;
- (void)receiveMinimumLength:(uint32_t)minimumLength
               maximumLength:(uint32_t)maximumLength
                  completion:(SSBTransportConnectionReceiveHandler)completion;
- (void)sendData:(NSData *)data
      isComplete:(BOOL)isComplete
      completion:(nullable SSBTransportConnectionSendHandler)completion;

@end

@protocol SSBTransportListener <NSObject>

@property (nonatomic, assign, readonly) SSBTransportListenerState state;
@property (nonatomic, assign, readonly) uint16_t port;

- (void)setStateChangedHandler:(nullable SSBTransportListenerStateHandler)handler;
- (void)setNewConnectionHandler:(nullable SSBTransportListenerNewConnectionHandler)handler;
- (void)start;
- (void)cancel;

@end

@protocol SSBTransportBackend <NSObject>

- (id<SSBTransportConnection>)connectionToEndpoint:(SSBTransportEndpoint *)endpoint
                                           options:(nullable SSBTransportConnectionOptions *)options
                                             queue:(dispatch_queue_t)queue;
- (id<SSBTransportConnection>)adoptConnection:(id)nativeConnection
                                        queue:(dispatch_queue_t)queue;
- (id<SSBTransportListener>)listenerOnEndpoint:(SSBTransportEndpoint *)endpoint
                                         queue:(dispatch_queue_t)queue;

@end

@interface SSBTransport : NSObject

+ (id<SSBTransportBackend>)defaultBackend;

@end

@interface SSBAppleTransportBackend : NSObject <SSBTransportBackend>
@end

@interface SSBLinuxTransportBackend : NSObject <SSBTransportBackend>
@end

NS_ASSUME_NONNULL_END
