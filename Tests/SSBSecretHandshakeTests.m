#import <XCTest/XCTest.h>
#import "../Sources/SSBSecretHandshake.h"
#import "../Sources/tweetnacl.h"

@interface SSBSecretHandshake (TestAccess)
@property (nonatomic, strong) NSData *appKey;
@property (nonatomic, strong) NSData *localIdentitySecret;
@property (nonatomic, strong, nullable) NSData *remoteIdentityPublic;
@property (nonatomic, strong) NSData *helloBuf;
@end

@interface SSBSecretHandshakeTests : XCTestCase
@property (nonatomic, strong) NSData *clientSecret;
@property (nonatomic, strong) NSData *clientPublic;
@property (nonatomic, strong) NSData *serverSecret;
@property (nonatomic, strong) NSData *serverPublic;
@end

// Helper assert for key derivation
#define XCTAssertCurrentKeysMatch(client, server) \
    XCTAssertNotNil(client.clientToServerKey); \
    XCTAssertNotNil(client.serverToClientKey); \
    XCTAssertEqualObjects(client.clientToServerKey, server.clientToServerKey); \
    XCTAssertEqualObjects(client.serverToClientKey, server.serverToClientKey); \
    XCTAssertEqualObjects(client.clientToServerNonce, server.clientToServerNonce); \
    XCTAssertEqualObjects(client.serverToClientNonce, server.serverToClientNonce);

@implementation SSBSecretHandshakeTests

- (void)setUp {
    [super setUp];
    // Generate deterministic or random keypairs for client/server
    unsigned char pk1[32], sk1[64];
    crypto_sign_ed25519_keypair(pk1, sk1);
    self.clientSecret = [NSData dataWithBytes:sk1 length:64];
    self.clientPublic = [NSData dataWithBytes:pk1 length:32];
    
    unsigned char pk2[32], sk2[64];
    crypto_sign_ed25519_keypair(pk2, sk2);
    self.serverSecret = [NSData dataWithBytes:sk2 length:64];
    self.serverPublic = [NSData dataWithBytes:pk2 length:32];
}

- (void)testClientHelloCreation {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    NSData *hello = [clientSHS createHello];
    XCTAssertNotNil(hello);
    XCTAssertEqual(hello.length, 64, @"Client hello must be 64 bytes");
}

- (void)testServerHelloCreation {
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    NSData *hello = [serverSHS createHello];
    XCTAssertNotNil(hello);
    XCTAssertEqual(hello.length, 64, @"Server hello must be 64 bytes");
}

- (void)testFullRoundtrip {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    
    // Step 1: Client -> Server
    NSData *clientHello = [clientSHS createHello];
    XCTAssertTrue([serverSHS processHello:clientHello]);
    
    // Step 2: Server -> Client
    NSData *serverHello = [serverSHS createHello];
    XCTAssertTrue([clientSHS processHello:serverHello]);
    
    // Step 3: Client -> Server
    NSData *clientAuth = [clientSHS createAuth];
    XCTAssertNotNil(clientAuth);
    XCTAssertEqual(clientAuth.length, 112, @"Auth msg must be 112 bytes");
    XCTAssertTrue([serverSHS processAuth:clientAuth]);
    
    // Server should now know the client's public key
    XCTAssertEqualObjects(serverSHS.remoteIdentityPublic, self.clientPublic);
    
    // Step 4: Server -> Client
    NSData *serverAccept = [serverSHS createAccept];
    XCTAssertNotNil(serverAccept);
    XCTAssertEqual(serverAccept.length, 80, @"Accept msg must be 80 bytes");
    XCTAssertTrue([clientSHS processAccept:serverAccept]);
    
    // Key derivation checks
    XCTAssertCurrentKeysMatch(clientSHS, serverSHS);
}

- (void)testProcessHelloRejectsTruncatedData {
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    NSMutableData *badHello = [NSMutableData dataWithLength:63]; // Too short
    
    XCTAssertFalse([serverSHS processHello:badHello]);
}

- (void)testProcessHelloRejectsBadMAC {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    NSData *clientHello = [clientSHS createHello];
    
    NSMutableData *badHello = [clientHello mutableCopy];
    // Corrupt the MAC (first 32 bytes)
    unsigned char *bytes = (unsigned char *)badHello.mutableBytes;
    bytes[0] ^= 0xFF;
    
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    XCTAssertFalse([serverSHS processHello:badHello]);
}

- (void)testProcessAuthRejectsTruncatedData {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    
    NSData *clientHello = [clientSHS createHello];
    [serverSHS processHello:clientHello];
    NSData *serverHello = [serverSHS createHello];
    [clientSHS processHello:serverHello];
    
    NSData *auth = [clientSHS createAuth];
    
    NSMutableData *badAuth = [[auth subdataWithRange:NSMakeRange(0, auth.length - 1)] mutableCopy];
    XCTAssertFalse([serverSHS processAuth:badAuth]);
}

- (void)testProcessAuthRejectsBadMAC {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    
    NSData *clientHello = [clientSHS createHello];
    [serverSHS processHello:clientHello];
    NSData *serverHello = [serverSHS createHello];
    [clientSHS processHello:serverHello];
    
    NSData *auth = [clientSHS createAuth];
    NSMutableData *badAuth = [auth mutableCopy];
    // Corrupt the poly1305 MAC (first 16 bytes)
    unsigned char *bytes = (unsigned char *)badAuth.mutableBytes;
    bytes[0] ^= 0xFF;
    
    XCTAssertFalse([serverSHS processAuth:badAuth]);
}

- (void)testProcessAcceptRejectsTruncatedData {
    SSBSecretHandshake *clientSHS = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    SSBSecretHandshake *serverSHS = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    
    [serverSHS processHello:[clientSHS createHello]];
    [clientSHS processHello:[serverSHS createHello]];
    [serverSHS processAuth:[clientSHS createAuth]];
    
    NSData *accept = [serverSHS createAccept];
    NSMutableData *badAccept = [[accept subdataWithRange:NSMakeRange(0, accept.length - 1)] mutableCopy];
    
    XCTAssertFalse([clientSHS processAccept:badAccept]);
}

- (void)testRoleEnforcement {
    SSBSecretHandshake *client1 = [[SSBSecretHandshake alloc] initWithRole:YES localIdentity:self.clientSecret remotePublicKey:self.serverPublic];
    XCTAssertTrue(client1.isClient);
    
    SSBSecretHandshake *server1 = [[SSBSecretHandshake alloc] initWithRole:NO localIdentity:self.serverSecret remotePublicKey:nil];
    XCTAssertFalse(server1.isClient);
}

@end
