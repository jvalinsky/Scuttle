#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBHTTPAuth.h>
#import "tweetnacl.h"

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
