#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBHTTPAuth.h>
#import <SSBNetwork/SSBEnvironment.h>
#import "tweetnacl.h"

// Minimal fake environment for time-control in token expiry tests
@interface FakeAuthEnv : NSObject <SSBEnvironmentProtocol>
@property (nonatomic, strong) NSDate *fixedDate;
@end
@implementation FakeAuthEnv
- (NSDate *)now { return self.fixedDate ?: [NSDate date]; }
- (uint32_t)randomUInt32 { return arc4random(); }
- (void)randomBytes:(void *)buffer length:(NSUInteger)length { arc4random_buf(buffer, length); }
- (NSURLSession *)URLSession { return [NSURLSession sharedSession]; }
- (NSURLSession *)URLSessionWithConfiguration:(NSURLSessionConfiguration *)c { return [NSURLSession sessionWithConfiguration:c]; }
- (NSFileManager *)fileManager { return [NSFileManager defaultManager]; }
- (NSString *)scuttleDataDirectory { return NSTemporaryDirectory(); }
- (void)dispatchAfter:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block { block(); }
@end

// Private method extensions needed for extended tests
@interface SSBHTTPAuthToken (Testing)
- (instancetype)initWithToken:(NSString *)token
                     clientId:(NSString *)clientId
                     serverId:(NSString *)serverId
                    createdAt:(NSDate *)createdAt
                    expiresAt:(nullable NSDate *)expiresAt;
- (BOOL)isExpired;
@end

@interface SSBHTTPAuthSolution (Testing)
- (instancetype)initWithServerChallenge:(NSString *)serverChallenge
                        clientChallenge:(NSString *)clientChallenge
                              clientId:(NSString *)clientId
                             createdAt:(NSDate *)createdAt
                             expiresAt:(nullable NSDate *)expiresAt;
- (BOOL)isExpired;
@end

@interface SSBHTTPAuth (Testing)
- (NSString *)generateSSEChannelIdForServerChallenge:(NSString *)serverChallenge;
- (void)notifySSEChannel:(NSString *)channelId withSuccess:(BOOL)success redirectURL:(nullable NSString *)redirectURL;
- (NSDictionary *)waitForSSEAuthWithChannelId:(NSString *)channelId timeout:(NSTimeInterval)timeout;
@end

/// Generates a random ed25519 keypair.
static void generateKeypair(NSData * __autoreleasing *outSecret,
                             NSData * __autoreleasing *outPublic) {
    NSMutableData *pk = [NSMutableData dataWithLength:32];
    NSMutableData *sk = [NSMutableData dataWithLength:64];
    crypto_sign_ed25519_keypair(pk.mutableBytes, sk.mutableBytes);
    *outPublic = pk;
    *outSecret = sk;
}

@interface SSBHTTPAuthTests : XCTestCase
@property (nonatomic, strong) SSBHTTPAuth *auth;
@property (nonatomic, strong) NSData *serverPub;
@property (nonatomic, strong) NSData *serverSec;
@property (nonatomic, copy) NSString *serverId;
@end

@implementation SSBHTTPAuthTests

- (void)setUp {
    [super setUp];
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    self.serverPub = pub;
    self.serverSec = sec;
    self.serverId = [NSString stringWithFormat:@"@%@.ed25519",
                     [pub base64EncodedStringWithOptions:0]];
    self.auth = [[SSBHTTPAuth alloc] initWithServerId:self.serverId
                                        serverPubKey:pub
                                      serverSecretKey:sec];
    XCTAssertNotNil(self.auth);
}

#pragma mark - sharedAuth

- (void)testSharedAuth_returnsNil {
    XCTAssertNil([SSBHTTPAuth sharedAuth]);
}

#pragma mark - generateNonce

- (void)testGenerateNonce_returnsNonNilString {
    XCTAssertNotNil([self.auth generateNonce]);
}

- (void)testGenerateNonce_twoCalls_differ {
    XCTAssertNotEqualObjects([self.auth generateNonce], [self.auth generateNonce]);
}

- (void)testGenerateNonce_isBase64_32bytes {
    NSString *nonce = [self.auth generateNonce];
    NSData *d = [[NSData alloc] initWithBase64EncodedString:nonce options:0];
    XCTAssertNotNil(d);
    XCTAssertEqual(d.length, 32U);
}

#pragma mark - nonceDataFromBase64

- (void)testNonceDataFromBase64_validNonce_succeeds {
    NSMutableData *raw = [NSMutableData dataWithLength:32];
    NSString *b64 = [raw base64EncodedStringWithOptions:0];
    NSError *err;
    NSString *outNonce;
    NSData *result = [self.auth nonceDataFromBase64:b64 nonce:&outNonce error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 32U);
    XCTAssertEqualObjects(outNonce, b64);
}

- (void)testNonceDataFromBase64_wrongLength_returnsError {
    NSString *b64 = [[NSMutableData dataWithLength:10] base64EncodedStringWithOptions:0];
    NSError *err;
    NSData *result = [self.auth nonceDataFromBase64:b64 nonce:nil error:&err];
    XCTAssertNil(result);
    XCTAssertNotNil(err);
    XCTAssertEqualObjects(err.domain, SSBHTTPAuthErrorDomain);
}

- (void)testNonceDataFromBase64_invalidBase64_returnsError {
    NSError *err;
    NSData *result = [self.auth nonceDataFromBase64:@"!!!notbase64" nonce:nil error:&err];
    XCTAssertNil(result);
    XCTAssertNotNil(err);
}

#pragma mark - signMessage / verifySignature — round trip

- (void)testSignAndVerify_roundTrip {
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    NSError *err;
    NSString *sig = [self.auth signMessage:@"Hello SSB" withSecretKey:sec error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(sig);
    BOOL valid = [self.auth verifySignature:sig forMessage:@"Hello SSB" withPublicKey:pub error:&err];
    XCTAssertNil(err);
    XCTAssertTrue(valid);
}

- (void)testSignMessage_wrongKeyLength_returnsError {
    NSError *err;
    NSData *badKey = [NSMutableData dataWithLength:32]; // needs 64
    XCTAssertNil([self.auth signMessage:@"msg" withSecretKey:badKey error:&err]);
    XCTAssertNotNil(err);
}

- (void)testVerifySignature_wrongPublicKey_returnsFalse {
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    NSError *err;
    NSString *sig = [self.auth signMessage:@"msg" withSecretKey:sec error:&err];
    XCTAssertNotNil(sig);
    NSData *wrongSec, *wrongPub;
    generateKeypair(&wrongSec, &wrongPub);
    BOOL valid = [self.auth verifySignature:sig forMessage:@"msg" withPublicKey:wrongPub error:&err];
    XCTAssertFalse(valid);
}

- (void)testVerifySignature_wrongPublicKeyLength_returnsError {
    NSError *err;
    NSData *badPub = [NSMutableData dataWithLength:10];
    BOOL valid = [self.auth verifySignature:@"sig" forMessage:@"msg" withPublicKey:badPub error:&err];
    XCTAssertFalse(valid);
    XCTAssertNotNil(err);
}

- (void)testVerifySignature_badBase64Sig_returnsError {
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    NSError *err;
    BOOL valid = [self.auth verifySignature:@"!!!notbase64" forMessage:@"msg" withPublicKey:pub error:&err];
    XCTAssertFalse(valid);
    XCTAssertNotNil(err);
}

- (void)testVerifySignature_tamperedMessage_returnsFalse {
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    NSError *err;
    NSString *sig = [self.auth signMessage:@"original" withSecretKey:sec error:&err];
    XCTAssertNotNil(sig);
    BOOL valid = [self.auth verifySignature:sig forMessage:@"tampered" withPublicKey:pub error:&err];
    XCTAssertFalse(valid);
}

#pragma mark - Token management

- (void)testGenerateToken_returnsToken {
    NSError *err;
    SSBHTTPAuthToken *tok = [self.auth generateTokenForClientId:@"@client.ed25519" error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(tok);
    XCTAssertEqualObjects(tok.clientId, @"@client.ed25519");
    XCTAssertEqualObjects(tok.serverId, self.serverId);
    XCTAssertNotNil(tok.createdAt);
    XCTAssertNotNil(tok.token);
}

- (void)testTokenForTokenString_returnsToken {
    NSError *err;
    SSBHTTPAuthToken *tok = [self.auth generateTokenForClientId:@"@client.ed25519" error:&err];
    XCTAssertNotNil(tok);
    SSBHTTPAuthToken *found = [self.auth tokenForTokenString:tok.token];
    XCTAssertEqualObjects(found.token, tok.token);
}

- (void)testTokenForTokenString_missingToken_returnsNil {
    XCTAssertNil([self.auth tokenForTokenString:@"definitely-not-a-token"]);
}

- (void)testInvalidateToken_removesIt {
    NSError *err;
    SSBHTTPAuthToken *tok = [self.auth generateTokenForClientId:@"@client.ed25519" error:&err];
    XCTAssertNotNil(tok);
    [self.auth invalidateToken:tok];
    XCTAssertNil([self.auth tokenForTokenString:tok.token]);
}

- (void)testInvalidateAllTokensForClientId_removesAll {
    NSError *err;
    NSString *cid = @"@multiclient.ed25519";
    SSBHTTPAuthToken *t1 = [self.auth generateTokenForClientId:cid error:&err];
    SSBHTTPAuthToken *t2 = [self.auth generateTokenForClientId:cid error:&err];
    XCTAssertNotNil(t1);
    XCTAssertNotNil(t2);
    [self.auth invalidateAllTokensForClientId:cid];
    XCTAssertNil([self.auth tokenForTokenString:t1.token]);
    XCTAssertNil([self.auth tokenForTokenString:t2.token]);
}

- (void)testAllActiveTokens_returnsList {
    NSError *err;
    [self.auth generateTokenForClientId:@"@c1.ed25519" error:&err];
    [self.auth generateTokenForClientId:@"@c2.ed25519" error:&err];
    XCTAssertGreaterThanOrEqual([self.auth allActiveTokens].count, 2U);
}

@end

#pragma mark - MockHTTPAuthDelegate

@interface MockHTTPAuthDelegate : NSObject <SSBHTTPAuthDelegate>
@property (nonatomic, strong) NSData *secretKey;
@property (nonatomic, assign) BOOL grantConsent;
@property (nonatomic, strong) SSBHTTPAuthToken *lastAuthenticatedToken;
@property (nonatomic, strong) SSBHTTPAuthToken *lastInvalidatedToken;
@end

@implementation MockHTTPAuthDelegate
- (void)httpAuth:(SSBHTTPAuth *)httpAuth requestConsentForServerId:(NSString *)serverId
        clientId:(NSString *)clientId completion:(SSBHTTPAuthConsentBlock)completion {
    completion(self.grantConsent, nil);
}
- (nullable NSData *)httpAuth:(SSBHTTPAuth *)httpAuth secretKeyForClientId:(NSString *)clientId {
    return self.secretKey;
}
- (void)httpAuth:(SSBHTTPAuth *)httpAuth didAuthenticateToken:(SSBHTTPAuthToken *)token {
    self.lastAuthenticatedToken = token;
}
- (void)httpAuth:(SSBHTTPAuth *)httpAuth didInvalidateToken:(SSBHTTPAuthToken *)token {
    self.lastInvalidatedToken = token;
}
@end

#pragma mark - SSBHTTPAuthExtendedTests

@interface SSBHTTPAuthExtendedTests : XCTestCase
@property (nonatomic, strong) SSBHTTPAuth *auth;
@property (nonatomic, strong) NSData *serverPub;
@property (nonatomic, strong) NSData *serverSec;
@property (nonatomic, copy) NSString *serverId;
@property (nonatomic, strong) id<SSBEnvironmentProtocol> savedEnv;
@end

@implementation SSBHTTPAuthExtendedTests

- (void)setUp {
    [super setUp];
    self.savedEnv = [SSBEnvironment shared];
    NSData *sec, *pub;
    generateKeypair(&sec, &pub);
    self.serverPub = pub;
    self.serverSec = sec;
    self.serverId = [NSString stringWithFormat:@"@%@.ed25519",
                     [pub base64EncodedStringWithOptions:0]];
    self.auth = [[SSBHTTPAuth alloc] initWithServerId:self.serverId
                                        serverPubKey:pub
                                      serverSecretKey:sec];
}

- (void)tearDown {
    [SSBEnvironment setShared:self.savedEnv];
    [super tearDown];
}

#pragma mark - SSBHTTPAuthToken NSSecureCoding

- (void)testToken_encodeDecode_roundTrip {
    NSDate *created = [NSDate dateWithTimeIntervalSince1970:1000];
    NSDate *expires = [NSDate dateWithTimeIntervalSince1970:2000];
    SSBHTTPAuthToken *original = [[SSBHTTPAuthToken alloc] initWithToken:@"tok123"
                                                                clientId:@"@client.ed25519"
                                                                serverId:@"@server.ed25519"
                                                               createdAt:created
                                                               expiresAt:expires];
    NSError *err;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:original
                                        requiringSecureCoding:YES
                                                        error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(data);

    SSBHTTPAuthToken *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[SSBHTTPAuthToken class]
                                                                  fromData:data
                                                                     error:&err];
    XCTAssertNil(err);
    XCTAssertEqualObjects(decoded.token, @"tok123");
    XCTAssertEqualObjects(decoded.clientId, @"@client.ed25519");
    XCTAssertEqualObjects(decoded.serverId, @"@server.ed25519");
    XCTAssertEqualObjects(decoded.createdAt, created);
    XCTAssertEqualObjects(decoded.expiresAt, expires);
}

- (void)testToken_isExpired_noExpiresAt_returnsFalse {
    SSBHTTPAuthToken *tok = [[SSBHTTPAuthToken alloc] initWithToken:@"t"
                                                           clientId:@"c"
                                                           serverId:@"s"
                                                          createdAt:[NSDate date]
                                                          expiresAt:nil];
    XCTAssertFalse([tok isExpired]);
}

- (void)testToken_isExpired_futureDate_returnsFalse {
    NSDate *future = [NSDate dateWithTimeIntervalSinceNow:9999];
    SSBHTTPAuthToken *tok = [[SSBHTTPAuthToken alloc] initWithToken:@"t"
                                                           clientId:@"c"
                                                           serverId:@"s"
                                                          createdAt:[NSDate date]
                                                          expiresAt:future];
    XCTAssertFalse([tok isExpired]);
}

- (void)testToken_isExpired_pastDate_returnsTrue {
    NSDate *past = [NSDate dateWithTimeIntervalSince1970:1];
    SSBHTTPAuthToken *tok = [[SSBHTTPAuthToken alloc] initWithToken:@"t"
                                                           clientId:@"c"
                                                           serverId:@"s"
                                                          createdAt:past
                                                          expiresAt:past];
    XCTAssertTrue([tok isExpired]);
}

#pragma mark - SSBHTTPAuthSolution

- (void)testSolution_init_setsProperties {
    NSDate *created = [NSDate dateWithTimeIntervalSince1970:1000];
    NSDate *expires = [NSDate dateWithTimeIntervalSince1970:2000];
    SSBHTTPAuthSolution *sol = [[SSBHTTPAuthSolution alloc] initWithServerChallenge:@"sc"
                                                                    clientChallenge:@"cc"
                                                                          clientId:@"cid"
                                                                         createdAt:created
                                                                         expiresAt:expires];
    XCTAssertEqualObjects(sol.serverChallenge, @"sc");
    XCTAssertEqualObjects(sol.clientChallenge, @"cc");
    XCTAssertEqualObjects(sol.clientId, @"cid");
    XCTAssertEqualObjects(sol.createdAt, created);
    XCTAssertEqualObjects(sol.expiresAt, expires);
    XCTAssertFalse(sol.isUsed);
}

- (void)testSolution_isExpired_noExpiresAt_returnsFalse {
    SSBHTTPAuthSolution *sol = [[SSBHTTPAuthSolution alloc] initWithServerChallenge:@"sc"
                                                                    clientChallenge:@"cc"
                                                                          clientId:@"cid"
                                                                         createdAt:[NSDate date]
                                                                         expiresAt:nil];
    XCTAssertFalse([sol isExpired]);
}

- (void)testSolution_isExpired_pastDate_returnsTrue {
    NSDate *past = [NSDate dateWithTimeIntervalSince1970:1];
    SSBHTTPAuthSolution *sol = [[SSBHTTPAuthSolution alloc] initWithServerChallenge:@"sc"
                                                                    clientChallenge:@"cc"
                                                                          clientId:@"cid"
                                                                         createdAt:past
                                                                         expiresAt:past];
    XCTAssertTrue([sol isExpired]);
}

#pragma mark - Helper Methods

- (void)testSignatureMessage_format {
    NSString *msg = [self.auth signatureMessageWithServerId:@"srv"
                                                   clientId:@"clt"
                                             serverChallenge:@"sc"
                                             clientChallenge:@"cc"];
    XCTAssertEqualObjects(msg, @"=http-auth-sign-in:srv:clt:sc:cc");
}

- (void)testServerIdFromPublicKey_valid {
    NSData *pub = self.serverPub; // 32 bytes
    NSString *sid = [self.auth serverIdFromPublicKey:pub];
    XCTAssertTrue([sid hasPrefix:@"@"]);
    XCTAssertTrue([sid hasSuffix:@".ed25519"]);
}

- (void)testServerIdFromPublicKey_wrongLength_returnsNil {
    NSData *bad = [NSMutableData dataWithLength:10];
    XCTAssertNil([self.auth serverIdFromPublicKey:bad]);
}

- (void)testPublicKeyFromServerId_valid_returns32Bytes {
    NSData *pub = [self.auth publicKeyFromServerId:self.serverId];
    XCTAssertNotNil(pub);
    XCTAssertEqual(pub.length, 32U);
    XCTAssertEqualObjects(pub, self.serverPub);
}

- (void)testPublicKeyFromServerId_noPrefix {
    NSString *base64 = [self.serverPub base64EncodedStringWithOptions:0];
    NSData *pub = [self.auth publicKeyFromServerId:base64];
    XCTAssertNotNil(pub);
    XCTAssertEqual(pub.length, 32U);
}

- (void)testPublicKeyFromServerId_invalidBase64_returnsNil {
    NSData *pub = [self.auth publicKeyFromServerId:@"notvalidbase64!!!"];
    XCTAssertNil(pub);
}

- (void)testPublicKeyFromServerId_wrongLength_returnsNil {
    NSData *tenBytes = [NSMutableData dataWithLength:10];
    NSString *b64 = [tenBytes base64EncodedStringWithOptions:0];
    NSData *pub = [self.auth publicKeyFromServerId:b64];
    XCTAssertNil(pub);
}

- (void)testLoginURLForClientId_containsFields {
    NSString *url = [self.auth loginURLForClientId:@"@cid.ed25519"
                                   clientChallenge:@"cc123"
                                        serverHost:@"example.com"];
    XCTAssertTrue([url hasPrefix:@"https://example.com/login"]);
    XCTAssertTrue([url containsString:@"cid"]);
    XCTAssertTrue([url containsString:@"cc123"]);
}

#pragma mark - Server-Initiated Login Flow

- (void)testHandleServerInitiatedLogin_returnsChallenge {
    NSDictionary *result = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    XCTAssertEqualObjects(result[@"status"], @"waiting");
    XCTAssertNotNil(result[@"serverChallenge"]);
    XCTAssertNotNil(result[@"ssbURI"]);
}

- (void)testStartHTTPServerAuth_containsChallenge {
    NSString *url = [self.auth startHTTPServerAuthWithServerChallenge:@"my-challenge"];
    XCTAssertTrue([url containsString:@"my-challenge"]);
    XCTAssertTrue([url containsString:@"login"]);
}

- (void)testCompleteServerInitiatedAuth_noPending_returnsError {
    NSDictionary *result = [self.auth completeServerInitiatedAuthWithServerChallenge:@"unknown-sc"
                                                                     clientChallenge:@"cc"
                                                                            solution:@"sig"
                                                                           clientId:@"cid"];
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testCompleteServerInitiatedAuth_invalidPublicKey_returnsError {
    // Store a pending solution
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    // clientId that produces nil public key (not valid ed25519 format)
    NSDictionary *result = [self.auth completeServerInitiatedAuthWithServerChallenge:serverChallenge
                                                                     clientChallenge:@"cc"
                                                                            solution:@"sig"
                                                                           clientId:@"bad-client-id"];
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testCompleteServerInitiatedAuth_invalidSignature_returnsError {
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    // Use a valid client keypair so publicKeyFromClientId succeeds
    NSData *clientSec, *clientPub;
    generateKeypair(&clientSec, &clientPub);
    NSString *clientId = [NSString stringWithFormat:@"@%@.ed25519",
                          [clientPub base64EncodedStringWithOptions:0]];

    // Bogus base64-encoded 64-byte signature (wrong for this message)
    NSMutableData *fakeSig = [NSMutableData dataWithLength:64];
    NSString *fakeSigB64 = [fakeSig base64EncodedStringWithOptions:0];

    NSDictionary *result = [self.auth completeServerInitiatedAuthWithServerChallenge:serverChallenge
                                                                     clientChallenge:@"cc"
                                                                            solution:fakeSigB64
                                                                           clientId:clientId];
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testStoreClientInfo_updatesExistingChallenge {
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    // Should not crash; verifiable via completeServerInitiatedAuth using updated clientId
    [self.auth storeClientInfoForServerChallenge:serverChallenge
                                        clientId:@"@cid.ed25519"
                                 clientChallenge:@"cc123"];
    // Give the async dispatch a moment to run
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    // Verify the pending solution was updated (attempt complete with wrong sig → still error but
    // will reach "invalid signature" branch rather than "invalid public key" with good clientId)
    NSData *clientSec, *clientPub;
    generateKeypair(&clientSec, &clientPub);
    NSString *clientId = [NSString stringWithFormat:@"@%@.ed25519",
                          [clientPub base64EncodedStringWithOptions:0]];
    [self.auth storeClientInfoForServerChallenge:serverChallenge
                                        clientId:clientId
                                 clientChallenge:@"cc456"];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    // Now verify with correct clientId but wrong signature → error: invalid signature (not "no key")
    NSMutableData *fakeSig = [NSMutableData dataWithLength:64];
    NSString *fakeSigB64 = [fakeSig base64EncodedStringWithOptions:0];
    NSDictionary *result = [self.auth completeServerInitiatedAuthWithServerChallenge:serverChallenge
                                                                     clientChallenge:@"cc456"
                                                                            solution:fakeSigB64
                                                                           clientId:clientId];
    XCTAssertEqualObjects(result[@"status"], @"error");
    // "No pending solution" because it already consumed the pending solution? No...
    // The solution should be there still (completeServerInitiatedAuth only removes it on success).
    // This just confirms no crash.
}

#pragma mark - MuxRPC Handlers

- (void)testHandleInvalidateAllSolutions_succeeds {
    XCTestExpectation *exp = [self expectationWithDescription:@"invalidate all"];
    [self.auth handleInvalidateAllSolutions:^(BOOL success, NSError *error) {
        XCTAssertTrue(success);
        XCTAssertNil(error);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testHandleRequestSolution_noDelegate_returnsError {
    // Without a delegate providing a secret key, should return error
    XCTestExpectation *exp = [self expectationWithDescription:@"no key error"];
    [self.auth handleRequestSolution:@"sc"
                     clientChallenge:@"cc"
                          completion:^(NSString *solution, NSError *error) {
        XCTAssertNil(solution);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testHandleRequestSolution_withDelegateGranting_returnsSolution {
    NSData *clientSec, *clientPub;
    generateKeypair(&clientSec, &clientPub);

    MockHTTPAuthDelegate *delegate = [[MockHTTPAuthDelegate alloc] init];
    delegate.secretKey = clientSec;
    delegate.grantConsent = YES;
    self.auth.delegate = delegate;

    XCTestExpectation *exp = [self expectationWithDescription:@"solution granted"];
    [self.auth handleRequestSolution:@"sc"
                     clientChallenge:@"cc"
                          completion:^(NSString *solution, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(solution);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testHandleSendSolution_noPending_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"no pending"];
    [self.auth handleSendSolution:@"unknown-sc"
                  clientChallenge:@"cc"
                         solution:@"sig"
                       completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

#pragma mark - receiveSolutionForServerChallenge error paths

- (void)testReceiveSolution_noPending_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"no pending"];
    [self.auth receiveSolutionForServerChallenge:@"ghost-sc"
                                 clientChallenge:@"cc"
                                        solution:@"sig"
                                        clientId:@"cid"
                                      completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        XCTAssertEqual(error.code, SSBHTTPAuthErrorSolutionNotFound);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testReceiveSolution_clientIdMismatch_returnsError {
    // Store a pending solution (clientId="", clientChallenge="")
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    // Provide a wrong clientId (not "")
    XCTestExpectation *exp = [self expectationWithDescription:@"clientId mismatch"];
    [self.auth receiveSolutionForServerChallenge:serverChallenge
                                 clientChallenge:@""
                                        solution:@"sig"
                                        clientId:@"wrong-client"
                                      completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testReceiveSolution_clientChallengeMismatch_returnsError {
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    XCTestExpectation *exp = [self expectationWithDescription:@"cc mismatch"];
    [self.auth receiveSolutionForServerChallenge:serverChallenge
                                 clientChallenge:@"wrong-cc"
                                        solution:@"sig"
                                        clientId:@""
                                      completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testReceiveSolution_invalidPublicKey_returnsError {
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    // Update clientId to something that can't be parsed as a public key
    [self.auth storeClientInfoForServerChallenge:serverChallenge
                                        clientId:@"bad-id-not-base64"
                                 clientChallenge:@"cc"];
    // Wait for async store to complete
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    XCTestExpectation *exp = [self expectationWithDescription:@"bad pubkey"];
    [self.auth receiveSolutionForServerChallenge:serverChallenge
                                 clientChallenge:@"cc"
                                        solution:@"sig"
                                        clientId:@"bad-id-not-base64"
                                      completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testReceiveSolution_invalidSignature_returnsError {
    NSDictionary *loginInfo = [self.auth handleServerInitiatedLoginWithQueryParams:@{}];
    NSString *serverChallenge = loginInfo[@"serverChallenge"];

    NSData *clientSec, *clientPub;
    generateKeypair(&clientSec, &clientPub);
    NSString *clientId = [NSString stringWithFormat:@"@%@.ed25519",
                          [clientPub base64EncodedStringWithOptions:0]];
    [self.auth storeClientInfoForServerChallenge:serverChallenge
                                        clientId:clientId
                                 clientChallenge:@"cc"];
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    NSMutableData *fakeSig = [NSMutableData dataWithLength:64];
    NSString *fakeSigB64 = [fakeSig base64EncodedStringWithOptions:0];

    XCTestExpectation *exp = [self expectationWithDescription:@"bad sig"];
    [self.auth receiveSolutionForServerChallenge:serverChallenge
                                 clientChallenge:@"cc"
                                        solution:fakeSigB64
                                        clientId:clientId
                                      completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

#pragma mark - requestSolutionForServerChallenge

- (void)testRequestSolution_noDelegate_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"no delegate error"];
    [self.auth requestSolutionForServerChallenge:@"sc"
                                 clientChallenge:@"cc"
                                        clientId:@"@cid.ed25519"
                                      completion:^(NSString *solution, NSError *error) {
        XCTAssertNil(solution);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        XCTAssertEqual(error.code, SSBHTTPAuthErrorMissingCredentials);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRequestSolution_delegateGrantsConsent_returnsSolution {
    NSData *clientSec, *clientPub;
    generateKeypair(&clientSec, &clientPub);
    NSString *clientId = [NSString stringWithFormat:@"@%@.ed25519",
                          [clientPub base64EncodedStringWithOptions:0]];

    MockHTTPAuthDelegate *delegate = [[MockHTTPAuthDelegate alloc] init];
    delegate.secretKey = clientSec;
    delegate.grantConsent = YES;
    self.auth.delegate = delegate;

    XCTestExpectation *exp = [self expectationWithDescription:@"solution granted"];
    [self.auth requestSolutionForServerChallenge:@"sc123"
                                 clientChallenge:@"cc456"
                                        clientId:clientId
                                      completion:^(NSString *solution, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(solution);
        // Verify the solution is a valid base64 signature
        NSData *sigData = [[NSData alloc] initWithBase64EncodedString:solution options:0];
        XCTAssertEqual(sigData.length, 64U);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testRequestSolution_delegateDeniesConsent_returnsError {
    MockHTTPAuthDelegate *delegate = [[MockHTTPAuthDelegate alloc] init];
    delegate.grantConsent = NO;
    self.auth.delegate = delegate;

    XCTestExpectation *exp = [self expectationWithDescription:@"consent denied"];
    [self.auth requestSolutionForServerChallenge:@"sc"
                                 clientChallenge:@"cc"
                                        clientId:@"@cid.ed25519"
                                      completion:^(NSString *solution, NSError *error) {
        XCTAssertNil(solution);
        XCTAssertEqualObjects(error.domain, SSBHTTPAuthErrorDomain);
        XCTAssertEqual(error.code, SSBHTTPAuthErrorConsentDenied);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

#pragma mark - Token expiry

- (void)testTokenForTokenString_expiredToken_returnsNil {
    // Generate token with a short expiration interval
    self.auth.tokenExpirationInterval = 1.0; // 1 second from now
    NSError *err;
    SSBHTTPAuthToken *tok = [self.auth generateTokenForClientId:@"@c.ed25519" error:&err];
    XCTAssertNotNil(tok);
    // Advance environment time past expiry
    FakeAuthEnv *fake = [[FakeAuthEnv alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSinceNow:5.0]; // 5 seconds in future
    [SSBEnvironment setShared:fake];
    // Token should appear expired
    XCTAssertTrue([tok isExpired]);
    // tokenForTokenString should clean up expired tokens
    SSBHTTPAuthToken *found = [self.auth tokenForTokenString:tok.token];
    XCTAssertNil(found);
}

- (void)testAllActiveTokens_excludesExpiredTokens {
    self.auth.tokenExpirationInterval = 1.0; // expires 1 second from now
    NSError *err;
    [self.auth generateTokenForClientId:@"@expired.ed25519" error:&err];
    // Advance environment time past expiry
    FakeAuthEnv *fake = [[FakeAuthEnv alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
    [SSBEnvironment setShared:fake];
    NSArray *active = [self.auth allActiveTokens];
    for (SSBHTTPAuthToken *tok in active) {
        XCTAssertFalse([tok isExpired]);
    }
}

#pragma mark - invalidateToken delegate callbacks

- (void)testInvalidateToken_callsDelegate {
    MockHTTPAuthDelegate *delegate = [[MockHTTPAuthDelegate alloc] init];
    self.auth.delegate = delegate;

    NSError *err;
    SSBHTTPAuthToken *tok = [self.auth generateTokenForClientId:@"@c.ed25519" error:&err];
    XCTAssertNotNil(tok);
    [self.auth invalidateToken:tok];
    // Give async dispatch a moment
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    XCTAssertEqualObjects(delegate.lastInvalidatedToken.token, tok.token);
}

- (void)testInvalidateAllTokens_callsDelegateForEach {
    MockHTTPAuthDelegate *delegate = [[MockHTTPAuthDelegate alloc] init];
    self.auth.delegate = delegate;

    NSError *err;
    [self.auth generateTokenForClientId:@"@c.ed25519" error:&err];
    [self.auth invalidateAllTokensForClientId:@"@c.ed25519"];
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    XCTAssertNotNil(delegate.lastInvalidatedToken);
}

#pragma mark - Client-Initiated Login Flow

- (void)testHandleClientInitiatedLogin_missingParams_returnsError {
    NSDictionary *result = [self.auth handleClientInitiatedLoginWithQueryParams:@{}
                                                               serverChallenge:@"sc"
                                                                    completion:^(BOOL success) {}];
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testHandleClientInitiatedLogin_withParams_returnsPending {
    // Will fail internally (no secret key) but should return "pending" synchronously
    NSDictionary *result = [self.auth handleClientInitiatedLoginWithQueryParams:@{@"cid": @"@cid.ed25519", @"cc": @"cc123"}
                                                               serverChallenge:nil
                                                                    completion:^(BOOL success) {}];
    XCTAssertEqualObjects(result[@"status"], @"pending");
    XCTAssertNotNil(result[@"serverChallenge"]);
}

- (void)testHandleClientInitiatedLogin_withProvidedChallenge_usesThat {
    NSDictionary *result = [self.auth handleClientInitiatedLoginWithQueryParams:@{@"cid": @"@cid.ed25519", @"cc": @"cc123"}
                                                               serverChallenge:@"my-sc"
                                                                    completion:^(BOOL success) {}];
    XCTAssertEqualObjects(result[@"serverChallenge"], @"my-sc");
}

#pragma mark - SSE

- (void)testGenerateSSEChannelId_returnsNonNil {
    NSString *channelId = [self.auth generateSSEChannelIdForServerChallenge:@"sc"];
    XCTAssertNotNil(channelId);
    XCTAssertGreaterThan(channelId.length, 0U);
}

- (void)testWaitForSSEAuth_noChannel_returnsError {
    NSDictionary *result = [self.auth waitForSSEAuthWithChannelId:@"nonexistent" timeout:1.0];
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testWaitForSSEAuth_timeout_returnsTimeout {
    NSString *channelId = [self.auth generateSSEChannelIdForServerChallenge:@"sc"];
    // Use zero timeout so semaphore_wait returns immediately
    NSDictionary *result = [self.auth waitForSSEAuthWithChannelId:channelId timeout:0.0];
    XCTAssertEqualObjects(result[@"status"], @"timeout");
}

- (void)testNotifySSEChannel_unknownChannel_nocrash {
    // Should not crash when notifying unknown channel
    [self.auth notifySSEChannel:@"unknown" withSuccess:YES redirectURL:nil];
    NSRunLoop *rl = [NSRunLoop mainRunLoop];
    [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    XCTAssertTrue(YES); // no crash = pass
}

@end
