#import "SSBHTTPAuth.h"
#import "SSBURI.h"
#import "tweetnacl.h"
#import "SSBLogCompat.h"
#import <Security/Security.h>

static os_log_t httpAuth_log;

@interface SSBHTTPAuthSolution ()
@property (nonatomic, assign, readwrite) BOOL isUsed;
@property (nonatomic, copy, readwrite) NSString *clientId;
@property (nonatomic, copy, readwrite) NSString *clientChallenge;
@end

NSString * const SSBHTTPAuthErrorDomain = @"SSBHTTPAuth";

static const NSUInteger kNonceBytesLength = 32;

@implementation SSBHTTPAuthToken

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithToken:(NSString *)token
                    clientId:(NSString *)clientId
                   serverId:(NSString *)serverId
                   createdAt:(NSDate *)createdAt
                   expiresAt:(nullable NSDate *)expiresAt {
    self = [super init];
    if (self) {
        _token = [token copy];
        _clientId = [clientId copy];
        _serverId = [serverId copy];
        _createdAt = createdAt;
        _expiresAt = expiresAt;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _token = [coder decodeObjectOfClass:[NSString class] forKey:@"token"];
        _clientId = [coder decodeObjectOfClass:[NSString class] forKey:@"clientId"];
        _serverId = [coder decodeObjectOfClass:[NSString class] forKey:@"serverId"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _expiresAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"expiresAt"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_token forKey:@"token"];
    [coder encodeObject:_clientId forKey:@"clientId"];
    [coder encodeObject:_serverId forKey:@"serverId"];
    [coder encodeObject:_createdAt forKey:@"createdAt"];
    [coder encodeObject:_expiresAt forKey:@"expiresAt"];
}

- (BOOL)isExpired {
    if (!_expiresAt) {
        return NO;
    }
    return [[NSDate date] compare:_expiresAt] == NSOrderedDescending;
}

@end

@implementation SSBHTTPAuthSolution

- (instancetype)initWithServerChallenge:(NSString *)serverChallenge
                         clientChallenge:(NSString *)clientChallenge
                               clientId:(NSString *)clientId
                              createdAt:(NSDate *)createdAt
                              expiresAt:(nullable NSDate *)expiresAt {
    self = [super init];
    if (self) {
        _serverChallenge = [serverChallenge copy];
        _clientChallenge = [clientChallenge copy];
        _clientId = [clientId copy];
        _createdAt = createdAt;
        _expiresAt = expiresAt;
        _isUsed = NO;
    }
    return self;
}

- (BOOL)isExpired {
    if (!_expiresAt) {
        return NO;
    }
    return [[NSDate date] compare:_expiresAt] == NSOrderedDescending;
}

@end

@interface SSBHTTPAuth ()
@property (nonatomic, copy, readwrite) NSString *serverId;
@property (nonatomic, strong, readwrite) NSData *serverPublicKey;
@property (nonatomic, strong, readwrite) NSData *serverSecretKey;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBHTTPAuthSolution *> *pendingSolutions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBHTTPAuthToken *> *tokensByString;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<SSBHTTPAuthToken *> *> *tokensByClientId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *serverInitiatedAuths;
@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_semaphore_t> *sseSemaphores;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sseResults;
@property (nonatomic, SSB_STRONG_DISPATCH) dispatch_queue_t authQueue;
@end

@implementation SSBHTTPAuth

+ (void)initialize {
    if (self == [SSBHTTPAuth class]) {
        httpAuth_log = os_log_create("SSB", "HTTPAuth");
    }
}

+ (instancetype)sharedAuth {
    static SSBHTTPAuth *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        os_log_info(httpAuth_log, "SSBHTTPAuth shared instance requested but not initialized - returning nil");
    });
    return sharedInstance;
}

- (instancetype)initWithServerId:(NSString *)serverId
                  serverPubKey:(NSData *)serverPubKey
                  serverSecretKey:(NSData *)serverSecretKey {
    self = [super init];
    if (self) {
        _serverId = [serverId copy];
        _serverPublicKey = [serverPubKey copy];
        _serverSecretKey = [serverSecretKey copy];
        _solutionExpirationInterval = 60 * 5;
        _tokenExpirationInterval = 60 * 60 * 24 * 30;
        
        _pendingSolutions = [NSMutableDictionary dictionary];
        _tokensByString = [NSMutableDictionary dictionary];
        _tokensByClientId = [NSMutableDictionary dictionary];
        _serverInitiatedAuths = [NSMutableDictionary dictionary];
        _sseSemaphores = [NSMutableDictionary dictionary];
        _sseResults = [NSMutableDictionary dictionary];
        _authQueue = dispatch_queue_create("com.ssb.httpauth", DISPATCH_QUEUE_SERIAL);
        
        os_log_info(httpAuth_log, "SSBHTTPAuth initialized with serverId: %{public}@", serverId);
    }
    return self;
}

#pragma mark - Nonce Generation

- (NSString *)generateNonce {
    NSMutableData *nonceData = [NSMutableData dataWithLength:kNonceBytesLength];
    int result = SecRandomCopyBytes(kSecRandomDefault, kNonceBytesLength, nonceData.mutableBytes);
    if (result != errSecSuccess) {
        os_log_error(httpAuth_log, "Failed to generate random nonce: %d", result);
        return nil;
    }
    return [nonceData base64EncodedStringWithOptions:0];
}

- (NSData *)nonceDataFromBase64:(NSString *)base64 nonce:(NSString * _Nullable * _Nullable)outNonce error:(NSError **)error {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data || data.length != kNonceBytesLength) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidNonce
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid nonce: must be 32 bytes in base64"}];
        }
        return nil;
    }
    if (outNonce) {
        *outNonce = base64;
    }
    return data;
}

#pragma mark - Signature

- (nullable NSString *)signMessage:(NSString *)message withSecretKey:(NSData *)secretKey error:(NSError **)error {
    if (secretKey.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid secret key length"}];
        }
        return nil;
    }
    
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (!messageData) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode message"}];
        }
        return nil;
    }
    
    NSMutableData *signatureData = [NSMutableData dataWithLength:64];
    unsigned long long sigLen = 0;
    
    int result = crypto_sign_ed25519(signatureData.mutableBytes, &sigLen,
                                     messageData.bytes, messageData.length,
                                     secretKey.bytes);
    
    if (result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        }
        return nil;
    }
    
    return [signatureData base64EncodedStringWithOptions:0];
}

- (BOOL)verifySignature:(NSString *)signature forMessage:(NSString *)message withPublicKey:(NSData *)publicKey error:(NSError **)error {
    if (publicKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid public key length"}];
        }
        return NO;
    }
    
    NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signature options:0];
    if (!signatureData || signatureData.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature format"}];
        }
        return NO;
    }
    
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (!messageData) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode message"}];
        }
        return NO;
    }
    
    NSMutableData *verifiedData = [NSMutableData dataWithLength:messageData.length + 64];
    unsigned long long verifiedLen = 0;
    
    int result = crypto_sign_ed25519_open(verifiedData.mutableBytes, &verifiedLen,
                                          signatureData.bytes, signatureData.length,
                                          publicKey.bytes);
    
    if (result != 0) {
        os_log_info(httpAuth_log, "Signature verification failed");
        return NO;
    }
    
    NSData *computedMessage = [verifiedData subdataWithRange:NSMakeRange(0, verifiedLen)];
    return [computedMessage isEqualToData:messageData];
}

#pragma mark - Client-Initiated (Server calls client)

- (void)requestSolutionForServerChallenge:(NSString *)serverChallenge
                            clientChallenge:(NSString *)clientChallenge
                                  clientId:(NSString *)clientId
                                completion:(SSBHTTPAuthSolutionBlock)completion {
    void (^signAndComplete)(void) = ^{
        dispatch_async(self.authQueue, ^{
            NSError *error = nil;
            
            NSString *signatureMessage = [self signatureMessageWithServerId:self.serverId
                                                                    clientId:clientId
                                                              serverChallenge:serverChallenge
                                                              clientChallenge:clientChallenge];
            
            NSData *clientSecretKey = [self secretKeyForClientId:clientId error:&error];
            if (!clientSecretKey) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }
            
            NSString *solution = [self signMessage:signatureMessage withSecretKey:clientSecretKey error:&error];
            if (!solution) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }
            
            os_log_info(httpAuth_log, "Generated solution for client %{public}@", clientId);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(solution, nil);
            });
        });
    };
    
    if ([self.delegate respondsToSelector:@selector(httpAuth:requestConsentForServerId:clientId:completion:)]) {
        [self.delegate httpAuth:self requestConsentForServerId:self.serverId clientId:clientId completion:^(BOOL approved, NSError * _Nullable error) {
            if (approved) {
                signAndComplete();
            } else {
                NSError *consentError = error ?: [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                                      code:SSBHTTPAuthErrorConsentDenied
                                                                  userInfo:@{NSLocalizedDescriptionKey: @"User denied consent"}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, consentError);
                });
            }
        }];
    } else {
        signAndComplete();
    }
}

#pragma mark - Server-Initiated (Client calls server)

- (void)receiveSolutionForServerChallenge:(NSString *)serverChallenge
                            clientChallenge:(NSString *)clientChallenge
                                   solution:(NSString *)solution
                                  clientId:(NSString *)clientId
                                completion:(SSBHTTPAuthCompletionBlock)completion {
    dispatch_async(self.authQueue, ^{
        SSBHTTPAuthSolution *authSolution = self.pendingSolutions[serverChallenge];
        
        if (!authSolution) {
            NSError *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                 code:SSBHTTPAuthErrorSolutionNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"No pending solution found for server challenge"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        if ([authSolution isExpired]) {
            [self.pendingSolutions removeObjectForKey:serverChallenge];
            NSError *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                 code:SSBHTTPAuthErrorSolutionExpired
                                             userInfo:@{NSLocalizedDescriptionKey: @"Solution has expired"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        if (![authSolution.clientId isEqualToString:clientId]) {
            NSError *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                 code:SSBHTTPAuthErrorInvalidSignature
                                             userInfo:@{NSLocalizedDescriptionKey: @"Client ID mismatch"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        if (![authSolution.clientChallenge isEqualToString:clientChallenge]) {
            NSError *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                 code:SSBHTTPAuthErrorInvalidSignature
                                             userInfo:@{NSLocalizedDescriptionKey: @"Client challenge mismatch"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        NSString *signatureMessage = [self signatureMessageWithServerId:self.serverId
                                                                clientId:clientId
                                                          serverChallenge:serverChallenge
                                                          clientChallenge:clientChallenge];
        
        NSData *clientPublicKey = [self publicKeyFromClientId:clientId];
        if (!clientPublicKey) {
            NSError *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                                 code:SSBHTTPAuthErrorMissingCredentials
                                             userInfo:@{NSLocalizedDescriptionKey: @"Cannot derive client public key"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        NSError *verifyError = nil;
        BOOL valid = [self verifySignature:solution
                               forMessage:signatureMessage
                           withPublicKey:clientPublicKey
                                     error:&verifyError];
        
        if (!valid) {
            os_log_info(httpAuth_log, "Invalid signature for solution");
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, verifyError);
            });
            return;
        }
        
        authSolution.isUsed = YES;
        [self.pendingSolutions removeObjectForKey:serverChallenge];
        
        NSError *tokenError = nil;
        SSBHTTPAuthToken *token = [self generateTokenForClientId:clientId error:&tokenError];
        
        if (!token) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, tokenError);
            });
            return;
        }
        
        if ([self.delegate respondsToSelector:@selector(httpAuth:didAuthenticateToken:)]) {
            [self.delegate httpAuth:self didAuthenticateToken:token];
        }
        
        os_log_info(httpAuth_log, "Successfully authenticated client %{public}@", clientId);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, nil);
        });
    });
}

#pragma mark - Token Management

- (nullable SSBHTTPAuthToken *)tokenForTokenString:(NSString *)tokenString {
    __block SSBHTTPAuthToken *token = nil;
    dispatch_sync(self.authQueue, ^{
        token = self.tokensByString[tokenString];
        if (token && [token isExpired]) {
            [self.tokensByString removeObjectForKey:tokenString];
            token = nil;
        }
    });
    return token;
}

- (nullable SSBHTTPAuthToken *)generateTokenForClientId:(NSString *)clientId error:(NSError **)error {
    NSString *tokenString = [self generateNonce];
    if (!tokenString) {
        if (error) {
            *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                         code:SSBHTTPAuthErrorTokenGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate token"}];
        }
        return nil;
    }
    
    NSDate *now = [NSDate date];
    NSDate *expiresAt = nil;
    if (self.tokenExpirationInterval > 0) {
        expiresAt = [now dateByAddingTimeInterval:self.tokenExpirationInterval];
    }
    
    SSBHTTPAuthToken *token = [[SSBHTTPAuthToken alloc] initWithToken:tokenString
                                                             clientId:clientId
                                                             serverId:self.serverId
                                                             createdAt:now
                                                             expiresAt:expiresAt];
    
    dispatch_sync(self.authQueue, ^{
        self.tokensByString[tokenString] = token;
        
        NSMutableSet *clientTokens = self.tokensByClientId[clientId];
        if (!clientTokens) {
            clientTokens = [NSMutableSet set];
            self.tokensByClientId[clientId] = clientTokens;
        }
        [clientTokens addObject:token];
    });
    
    os_log_info(httpAuth_log, "Generated token for client %{public}@", clientId);
    
    return token;
}

- (void)invalidateToken:(SSBHTTPAuthToken *)token {
    dispatch_async(self.authQueue, ^{
        [self.tokensByString removeObjectForKey:token.token];
        
        NSMutableSet *clientTokens = self.tokensByClientId[token.clientId];
        [clientTokens removeObject:token];
        
        if ([self.delegate respondsToSelector:@selector(httpAuth:didInvalidateToken:)]) {
            [self.delegate httpAuth:self didInvalidateToken:token];
        }
        
        os_log_info(httpAuth_log, "Invalidated token for client %{public}@", token.clientId);
    });
}

- (void)invalidateAllTokensForClientId:(NSString *)clientId {
    dispatch_async(self.authQueue, ^{
        NSMutableSet *clientTokens = self.tokensByClientId[clientId];
        if (!clientTokens) {
            return;
        }
        
        for (SSBHTTPAuthToken *token in [clientTokens copy]) {
            [self.tokensByString removeObjectForKey:token.token];
            if ([self.delegate respondsToSelector:@selector(httpAuth:didInvalidateToken:)]) {
                [self.delegate httpAuth:self didInvalidateToken:token];
            }
        }
        
        [clientTokens removeAllObjects];
        
        os_log_info(httpAuth_log, "Invalidated all tokens for client %{public}@", clientId);
    });
}

- (NSArray<SSBHTTPAuthToken *> *)allActiveTokens {
    __block NSArray *tokens = nil;
    dispatch_sync(self.authQueue, ^{
        NSMutableArray *activeTokens = [NSMutableArray array];
        NSDate *now = [NSDate date];
        
        for (NSString *tokenString in self.tokensByString) {
            SSBHTTPAuthToken *token = self.tokensByString[tokenString];
            if (!token.expiresAt || [now compare:token.expiresAt] == NSOrderedAscending) {
                [activeTokens addObject:token];
            } else {
                [self.tokensByString removeObjectForKey:tokenString];
            }
        }
        
        tokens = [activeTokens copy];
    });
    return tokens;
}

#pragma mark - MuxRPC Handlers

- (void)handleRequestSolution:(NSString *)serverChallenge
               clientChallenge:(NSString *)clientChallenge
                    completion:(void (^)(NSString * _Nullable solution, NSError * _Nullable error))completion {
    [self requestSolutionForServerChallenge:serverChallenge
                              clientChallenge:clientChallenge
                                    clientId:@""
                                  completion:completion];
}

- (void)handleSendSolution:(NSString *)serverChallenge
            clientChallenge:(NSString *)clientChallenge
                  solution:(NSString *)solution
                completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    [self receiveSolutionForServerChallenge:serverChallenge
                              clientChallenge:clientChallenge
                                     solution:solution
                                    clientId:@""
                                  completion:completion];
}

- (void)handleInvalidateAllSolutions:(void (^)(BOOL success, NSError * _Nullable error))completion {
    dispatch_async(self.authQueue, ^{
        [self.pendingSolutions removeAllObjects];
        [self.serverInitiatedAuths removeAllObjects];
        
        os_log_info(httpAuth_log, "Invalidated all solutions");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, nil);
        });
    });
}

#pragma mark - Server-Initiated Login Flow

- (NSDictionary *)handleServerInitiatedLoginWithQueryParams:(NSDictionary *)queryParams {
    NSString *serverChallenge = [self generateNonce];
    if (!serverChallenge) {
        return @{@"status": @"error", @"error": @"Failed to generate server challenge"};
    }
    
    dispatch_sync(self.authQueue, ^{
        NSDate *expiresAt = [[NSDate date] dateByAddingTimeInterval:self.solutionExpirationInterval];
        
        SSBHTTPAuthSolution *solution = [[SSBHTTPAuthSolution alloc] initWithServerChallenge:serverChallenge
                                                                              clientChallenge:@""
                                                                                    clientId:@""
                                                                                   createdAt:[NSDate date]
                                                                                   expiresAt:expiresAt];
        
        self.pendingSolutions[serverChallenge] = solution;
    });
    
    NSString *ssbURI = [NSString stringWithFormat:@"ssb:experimental?action=start-http-auth&sid=%@&sc=%@",
                        self.serverId, serverChallenge];
    
    return @{
        @"status": @"waiting",
        @"serverChallenge": serverChallenge,
        @"ssbURI": ssbURI
    };
}

- (NSString *)startHTTPServerAuthWithServerChallenge:(NSString *)serverChallenge {
    return [NSString stringWithFormat:@"%@/login?ssb-http-auth=1&sc=%@",
            self.serverId, serverChallenge];
}

- (nullable NSDictionary *)completeServerInitiatedAuthWithServerChallenge:(NSString *)serverChallenge
                                                              clientChallenge:(NSString *)clientChallenge
                                                                     solution:(NSString *)solution
                                                                    clientId:(NSString *)clientId {
    __block NSDictionary *result = nil;
    
    dispatch_sync(self.authQueue, ^{
        SSBHTTPAuthSolution *authSolution = self.pendingSolutions[serverChallenge];
        
        if (!authSolution) {
            result = @{@"status": @"error", @"error": @"No pending solution found"};
            return;
        }
        
        if ([authSolution isExpired]) {
            [self.pendingSolutions removeObjectForKey:serverChallenge];
            result = @{@"status": @"error", @"error": @"Solution has expired"};
            return;
        }
        
        NSString *signatureMessage = [self signatureMessageWithServerId:self.serverId
                                                                clientId:clientId
                                                          serverChallenge:serverChallenge
                                                          clientChallenge:clientChallenge];
        
        NSData *clientPublicKey = [self publicKeyFromClientId:clientId];
        if (!clientPublicKey) {
            result = @{@"status": @"error", @"error": @"Cannot derive client public key"};
            return;
        }
        
        NSError *verifyError = nil;
        BOOL valid = [self verifySignature:solution
                               forMessage:signatureMessage
                           withPublicKey:clientPublicKey
                                     error:&verifyError];
        
        if (!valid) {
            result = @{@"status": @"error", @"error": @"Invalid signature"};
            return;
        }
        
        authSolution.isUsed = YES;
        [self.pendingSolutions removeObjectForKey:serverChallenge];
        
        NSError *tokenError = nil;
        SSBHTTPAuthToken *token = [self generateTokenForClientId:clientId error:&tokenError];
        
        if (!token) {
            result = @{@"status": @"error", @"error": tokenError.localizedDescription ?: @"Token generation failed"};
            return;
        }
        
        if ([self.delegate respondsToSelector:@selector(httpAuth:didAuthenticateToken:)]) {
            [self.delegate httpAuth:self didAuthenticateToken:token];
        }
        
        result = @{
            @"status": @"success",
            @"token": token.token,
            @"clientId": clientId
        };
    });
    
    return result;
}

- (void)storeClientInfoForServerChallenge:(NSString *)serverChallenge
                                 clientId:(NSString *)clientId
                           clientChallenge:(NSString *)clientChallenge {
    dispatch_async(self.authQueue, ^{
        SSBHTTPAuthSolution *solution = self.pendingSolutions[serverChallenge];
        if (solution) {
            solution.clientId = clientId;
            solution.clientChallenge = clientChallenge;
            
            self.serverInitiatedAuths[serverChallenge] = @{
                @"clientId": clientId,
                @"clientChallenge": clientChallenge
            };
        }
    });
}

#pragma mark - Client-Initiated Login Flow

- (NSDictionary *)handleClientInitiatedLoginWithQueryParams:(NSDictionary *)queryParams
                                             serverChallenge:(NSString *)serverChallenge
                                                 completion:(void (^)(BOOL success))completion {
    NSString *clientId = queryParams[@"cid"];
    NSString *clientChallenge = queryParams[@"cc"];
    
    if (!clientId || !clientChallenge) {
        return @{@"status": @"error", @"error": @"Missing required parameters"};
    }
    
    if (!serverChallenge) {
        serverChallenge = [self generateNonce];
        if (!serverChallenge) {
            return @{@"status": @"error", @"error": @"Failed to generate server challenge"};
        }
    }
    
    [self handleRequestSolution:serverChallenge
                 clientChallenge:clientChallenge
                      completion:^(NSString * _Nullable solution, NSError * _Nullable error) {
        if (solution) {
            completion(YES);
        } else {
            completion(NO);
        }
    }];
    
    return @{
        @"status": @"pending",
        @"serverChallenge": serverChallenge
    };
}

- (NSString *)loginURLForClientId:(NSString *)clientId clientChallenge:(NSString *)clientChallenge serverHost:(NSString *)host {
    NSString *encodedCid = [clientId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedCc = [clientChallenge stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    return [NSString stringWithFormat:@"https://%@/login?ssb-http-auth=1&cid=%@&cc=%@",
            host, encodedCid, encodedCc];
}

#pragma mark - Helpers

- (NSString *)signatureMessageWithServerId:(NSString *)serverId
                                   clientId:(NSString *)clientId
                             serverChallenge:(NSString *)serverChallenge
                             clientChallenge:(NSString *)clientChallenge {
    return [NSString stringWithFormat:@"=http-auth-sign-in:%@:%@:%@:%@",
            serverId, clientId, serverChallenge, clientChallenge];
}

- (NSString *)serverIdFromPublicKey:(NSData *)publicKey {
    if (publicKey.length != 32) {
        return nil;
    }
    NSString *base64 = [publicKey base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"@%@.ed25519", base64];
}

- (nullable NSData *)publicKeyFromServerId:(NSString *)serverId {
    NSString *cleanId = serverId;
    if ([cleanId hasPrefix:@"@"]) {
        cleanId = [cleanId substringFromIndex:1];
    }
    if ([cleanId hasSuffix:@".ed25519"]) {
        cleanId = [cleanId substringToIndex:cleanId.length - 8];
    }
    
    NSData *data = [[NSData alloc] initWithBase64EncodedString:cleanId options:0];
    if (data.length != 32) {
        return nil;
    }
    return data;
}

- (nullable NSData *)secretKeyForClientId:(NSString *)clientId error:(NSError **)error {
    if ([self.delegate respondsToSelector:@selector(httpAuth:secretKeyForClientId:)]) {
        NSData *secretKey = [self.delegate httpAuth:self secretKeyForClientId:clientId];
        if (secretKey && secretKey.length == 64) {
            return secretKey;
        }
    }
    
    if (error) {
        *error = [NSError errorWithDomain:SSBHTTPAuthErrorDomain
                                     code:SSBHTTPAuthErrorMissingCredentials
                                 userInfo:@{NSLocalizedDescriptionKey: @"No secret key available for client"}];
    }
    return nil;
}

- (nullable NSData *)publicKeyFromClientId:(NSString *)clientId {
    return [self publicKeyFromServerId:clientId];
}

#pragma mark - SSE Support (Server-Initiated)

- (NSString *)generateSSEChannelIdForServerChallenge:(NSString *)serverChallenge {
    NSString *channelId = [self generateNonce];
    if (!channelId) {
        return nil;
    }
    
    dispatch_sync(self.authQueue, ^{
        self.sseSemaphores[channelId] = dispatch_semaphore_create(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self notifySSEChannel:channelId withSuccess:NO redirectURL:nil];
        });
    });
    
    return channelId;
}

- (void)notifySSEChannel:(NSString *)channelId withSuccess:(BOOL)success redirectURL:(nullable NSString *)redirectURL {
    dispatch_async(self.authQueue, ^{
        dispatch_semaphore_t semaphore = self.sseSemaphores[channelId];
        if (semaphore) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            result[@"success"] = @(success);
            if (redirectURL) {
                result[@"redirectURL"] = redirectURL;
            }
            self.sseResults[channelId] = [result copy];
            dispatch_semaphore_signal(semaphore);
        }
    });
}

- (NSDictionary *)waitForSSEAuthWithChannelId:(NSString *)channelId timeout:(NSTimeInterval)timeout {
    __block NSDictionary *result = nil;
    
    dispatch_sync(self.authQueue, ^{
        dispatch_semaphore_t semaphore = self.sseSemaphores[channelId];
        if (!semaphore) {
            result = @{@"status": @"error", @"error": @"No SSE channel found"};
            return;
        }
        
        dispatch_time_t waitTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
        long waitResult = dispatch_semaphore_wait(semaphore, waitTime);
        
        if (waitResult != 0) {
            result = @{@"status": @"timeout", @"error": @"SSE wait timed out"};
        } else {
            result = self.sseResults[channelId] ?: @{@"status": @"error", @"error": @"No result"};
        }
        
        [self.sseSemaphores removeObjectForKey:channelId];
        [self.sseResults removeObjectForKey:channelId];
    });
    
    return result;
}

@end
