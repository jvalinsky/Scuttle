#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBHTTPAuth;

typedef void (^SSBHTTPAuthSolutionBlock)(NSString * _Nullable solution, NSError * _Nullable error);
typedef void (^SSBHTTPAuthCompletionBlock)(BOOL success, NSError * _Nullable error);
typedef void (^SSBHTTPAuthConsentBlock)(BOOL approved, NSError * _Nullable error);

extern NSString * const SSBHTTPAuthErrorDomain;

typedef NS_ENUM(NSInteger, SSBHTTPAuthError) {
    SSBHTTPAuthErrorInvalidNonce = 1,
    SSBHTTPAuthErrorInvalidSignature = 2,
    SSBHTTPAuthErrorSolutionExpired = 3,
    SSBHTTPAuthErrorSolutionNotFound = 4,
    SSBHTTPAuthErrorTokenGenerationFailed = 5,
    SSBHTTPAuthErrorTokenInvalidated = 6,
    SSBHTTPAuthErrorConsentDenied = 7,
    SSBHTTPAuthErrorMissingCredentials = 8
};

@interface SSBHTTPAuthToken : NSObject <NSSecureCoding>
@property (nonatomic, copy, readonly) NSString *token;
@property (nonatomic, copy, readonly) NSString *clientId;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;
@property (nonatomic, copy, readonly) NSString *serverId;
@end

@interface SSBHTTPAuthSolution : NSObject
@property (nonatomic, copy, readonly) NSString *serverChallenge;
@property (nonatomic, copy, readonly) NSString *clientChallenge;
@property (nonatomic, copy, readonly) NSString *clientId;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;
@property (nonatomic, assign, readonly) BOOL isUsed;
@end

@protocol SSBHTTPAuthDelegate <NSObject>
@optional
- (void)httpAuth:(SSBHTTPAuth *)httpAuth requestConsentForServerId:(NSString *)serverId
        clientId:(NSString *)clientId completion:(SSBHTTPAuthConsentBlock)completion;
- (void)httpAuth:(SSBHTTPAuth *)httpAuth didAuthenticateToken:(SSBHTTPAuthToken *)token;
- (void)httpAuth:(SSBHTTPAuth *)httpAuth didInvalidateToken:(SSBHTTPAuthToken *)token;
- (nullable NSData *)httpAuth:(SSBHTTPAuth *)httpAuth secretKeyForClientId:(NSString *)clientId;
@end

@interface SSBHTTPAuth : NSObject

@property (nonatomic, weak, nullable) id<SSBHTTPAuthDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *serverId;
@property (nonatomic, strong, readonly) NSData *serverPublicKey;
@property (nonatomic, strong, readonly) NSData *serverSecretKey;
@property (nonatomic, assign) NSTimeInterval solutionExpirationInterval;
@property (nonatomic, assign) NSTimeInterval tokenExpirationInterval;

+ (instancetype)sharedAuth;

- (instancetype)initWithServerId:(NSString *)serverId
                  serverPubKey:(NSData *)serverPubKey
                  serverSecretKey:(NSData *)serverSecretKey;

#pragma mark - Nonce Generation

- (NSString *)generateNonce;
- (NSData *)nonceDataFromBase64:(NSString *)base64 nonce:(NSString * _Nullable * _Nullable)outNonce error:(NSError **)error;

#pragma mark - Signature

- (nullable NSString *)signMessage:(NSString *)message withSecretKey:(NSData *)secretKey error:(NSError **)error;
- (BOOL)verifySignature:(NSString *)signature forMessage:(NSString *)message withPublicKey:(NSData *)publicKey error:(NSError **)error;

#pragma mark - Client-Initiated (Server calls client)

- (void)requestSolutionForServerChallenge:(NSString *)serverChallenge
                            clientChallenge:(NSString *)clientChallenge
                                  clientId:(NSString *)clientId
                                completion:(SSBHTTPAuthSolutionBlock)completion;

#pragma mark - Server-Initiated (Client calls server)

- (void)receiveSolutionForServerChallenge:(NSString *)serverChallenge
                            clientChallenge:(NSString *)clientChallenge
                                   solution:(NSString *)solution
                                  clientId:(NSString *)clientId
                                completion:(SSBHTTPAuthCompletionBlock)completion;

#pragma mark - Token Management

- (nullable SSBHTTPAuthToken *)tokenForTokenString:(NSString *)tokenString;
- (nullable SSBHTTPAuthToken *)generateTokenForClientId:(NSString *)clientId error:(NSError **)error;
- (void)invalidateToken:(SSBHTTPAuthToken *)token;
- (void)invalidateAllTokensForClientId:(NSString *)clientId;
- (NSArray<SSBHTTPAuthToken *> *)allActiveTokens;

#pragma mark - MuxRPC Handlers

- (void)handleRequestSolution:(NSString *)serverChallenge
               clientChallenge:(NSString *)clientChallenge
                    completion:(void (^)(NSString * _Nullable solution, NSError * _Nullable error))completion;

- (void)handleSendSolution:(NSString *)serverChallenge
            clientChallenge:(NSString *)clientChallenge
                  solution:(NSString *)solution
                completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)handleInvalidateAllSolutions:(void (^)(BOOL success, NSError * _Nullable error))completion;

#pragma mark - Server-Initiated Login Flow

- (NSDictionary<NSString *, id> *)handleServerInitiatedLoginWithQueryParams:(NSDictionary<NSString *, id> *)queryParams;
- (NSString *)startHTTPServerAuthWithServerChallenge:(NSString *)serverChallenge;
- (nullable NSDictionary<NSString *, id> *)completeServerInitiatedAuthWithServerChallenge:(NSString *)serverChallenge
                                                              clientChallenge:(NSString *)clientChallenge
                                                                     solution:(NSString *)solution
                                                                    clientId:(NSString *)clientId;
- (void)storeClientInfoForServerChallenge:(NSString *)serverChallenge
                                 clientId:(NSString *)clientId
                           clientChallenge:(NSString *)clientChallenge;

#pragma mark - Client-Initiated Login Flow

- (NSDictionary<NSString *, id> *)handleClientInitiatedLoginWithQueryParams:(NSDictionary<NSString *, id> *)queryParams
                                             serverChallenge:(NSString *)serverChallenge
                                                 completion:(void (^)(BOOL success))completion;
- (NSString *)loginURLForClientId:(NSString *)clientId clientChallenge:(NSString *)clientChallenge serverHost:(NSString *)host;

#pragma mark - Helpers

- (NSString *)signatureMessageWithServerId:(NSString *)serverId
                                   clientId:(NSString *)clientId
                             serverChallenge:(NSString *)serverChallenge
                             clientChallenge:(NSString *)clientChallenge;

- (NSString *)serverIdFromPublicKey:(NSData *)publicKey;
- (nullable NSData *)publicKeyFromServerId:(NSString *)serverId;

@end

NS_ASSUME_NONNULL_END
