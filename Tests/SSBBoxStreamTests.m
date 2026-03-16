#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBBoxStream.h>

/// Creates a zero-filled NSData of the given length.
static NSData *ZeroData(NSUInteger length) {
    return [NSData dataWithBytes:(void *)[NSMutableData dataWithLength:length].bytes length:length];
}

/// Creates a repeating byte NSData.
static NSData *RepeatingByte(uint8_t byte, NSUInteger length) {
    NSMutableData *d = [NSMutableData dataWithLength:length];
    memset(d.mutableBytes, byte, length);
    return d;
}

/// Returns a Box Stream pair: clientStream (isClient=YES) and serverStream (isClient=NO),
/// sharing the same key/nonce material so they can communicate.
static void MakeStreamPair(SSBBoxStream **outClient, SSBBoxStream **outServer) {
    // 32-byte keys, 24-byte nonces (XSalsa20 nonce size)
    NSData *c2sKey   = RepeatingByte(0x01, 32);
    NSData *s2cKey   = RepeatingByte(0x02, 32);
    NSData *c2sNonce = ZeroData(24);
    NSData *s2cNonce = ZeroData(24);

    SSBBoxStream *client = [[SSBBoxStream alloc] initWithClientToServerKey:c2sKey
                                                         serverToClientKey:s2cKey
                                                       clientToServerNonce:c2sNonce
                                                       serverToClientNonce:s2cNonce];
    client.isClient = YES;

    SSBBoxStream *server = [[SSBBoxStream alloc] initWithClientToServerKey:c2sKey
                                                         serverToClientKey:s2cKey
                                                       clientToServerNonce:c2sNonce
                                                       serverToClientNonce:s2cNonce];
    server.isClient = NO;

    if (outClient) *outClient = client;
    if (outServer) *outServer = server;
}

@interface SSBBoxStreamTests : XCTestCase
@property (nonatomic, strong) SSBBoxStream *client;
@property (nonatomic, strong) SSBBoxStream *server;
@end

@implementation SSBBoxStreamTests

- (void)setUp {
    [super setUp];
    MakeStreamPair(&_client, &_server);
}

#pragma mark - isClient flag

- (void)testIsClient_flag {
    XCTAssertTrue(self.client.isClient);
    XCTAssertFalse(self.server.isClient);
}

#pragma mark - encryptPayload: / decryptHeader: / decryptBody:

- (void)testClientEncrypt_serverDecrypt_roundTrip {
    NSData *payload = [@"Hello, Box Stream!" dataUsingEncoding:NSUTF8StringEncoding];

    // Client encrypts
    NSData *packet = [self.client encryptPayload:payload];
    XCTAssertNotNil(packet, @"Encryption should succeed");
    // Box Stream packet = 34-byte header + body
    XCTAssertGreaterThan(packet.length, 34);

    // Server splits header and body
    NSData *header = [packet subdataWithRange:NSMakeRange(0, 34)];
    NSData *body   = [packet subdataWithRange:NSMakeRange(34, packet.length - 34)];

    size_t bodyLength = 0;
    NSData *bodyMac = nil;
    BOOL headerOK = [self.server decryptHeader:header outLength:&bodyLength outBodyMac:&bodyMac];
    XCTAssertTrue(headerOK, @"Server must be able to decrypt the header");
    XCTAssertNotNil(bodyMac);
    XCTAssertEqual(bodyLength, payload.length);

    NSData *decrypted = [self.server decryptBody:body expectedMac:bodyMac];
    XCTAssertNotNil(decrypted, @"Body decryption should succeed");
    XCTAssertEqualObjects(decrypted, payload);
}

- (void)testServerEncrypt_clientDecrypt_roundTrip {
    NSData *payload = [@"Server response!" dataUsingEncoding:NSUTF8StringEncoding];

    NSData *packet = [self.server encryptPayload:payload];
    XCTAssertNotNil(packet);

    NSData *header = [packet subdataWithRange:NSMakeRange(0, 34)];
    NSData *body   = [packet subdataWithRange:NSMakeRange(34, packet.length - 34)];

    size_t bodyLength = 0;
    NSData *bodyMac = nil;
    BOOL headerOK = [self.client decryptHeader:header outLength:&bodyLength outBodyMac:&bodyMac];
    XCTAssertTrue(headerOK);

    NSData *decrypted = [self.client decryptBody:body expectedMac:bodyMac];
    XCTAssertNotNil(decrypted);
    XCTAssertEqualObjects(decrypted, payload);
}

- (void)testMultiplePackets_noncesIncrementCorrectly {
    NSData *p1 = [@"first" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *p2 = [@"second" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *p3 = [@"third" dataUsingEncoding:NSUTF8StringEncoding];

    for (NSData *payload in @[p1, p2, p3]) {
        NSData *packet = [self.client encryptPayload:payload];
        XCTAssertNotNil(packet);

        NSData *header = [packet subdataWithRange:NSMakeRange(0, 34)];
        NSData *body   = [packet subdataWithRange:NSMakeRange(34, packet.length - 34)];

        size_t bodyLength = 0;
        NSData *bodyMac = nil;
        BOOL ok = [self.server decryptHeader:header outLength:&bodyLength outBodyMac:&bodyMac];
        XCTAssertTrue(ok, @"Header decrypt must succeed for packet");

        NSData *decrypted = [self.server decryptBody:body expectedMac:bodyMac];
        XCTAssertEqualObjects(decrypted, payload, @"Each packet must decrypt to its original payload");
    }
}

#pragma mark - Error cases

- (void)testDecryptHeader_wrongKeyFails {
    NSData *payload = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *packet = [self.client encryptPayload:payload];
    NSData *header = [packet subdataWithRange:NSMakeRange(0, 34)];

    // Build a stream with wrong keys
    NSData *wrongKey = RepeatingByte(0xFF, 32);
    NSData *nonce    = ZeroData(24);
    SSBBoxStream *stranger = [[SSBBoxStream alloc] initWithClientToServerKey:wrongKey
                                                           serverToClientKey:wrongKey
                                                         clientToServerNonce:nonce
                                                         serverToClientNonce:nonce];
    stranger.isClient = NO;

    size_t len = 0;
    NSData *mac = nil;
    BOOL ok = [stranger decryptHeader:header outLength:&len outBodyMac:&mac];
    XCTAssertFalse(ok, @"Wrong key must fail header decryption");
}

- (void)testDecryptHeader_shortDataFails {
    // Header must be exactly 34 bytes
    NSData *shortHeader = ZeroData(10);
    size_t len = 0;
    NSData *mac = nil;
    BOOL ok = [self.server decryptHeader:shortHeader outLength:&len outBodyMac:&mac];
    XCTAssertFalse(ok, @"Header shorter than 34 bytes must fail");
}

- (void)testEncryptPayload_nilReturnsNil {
    // Passing nil should be handled gracefully
    NSData *result = [self.client encryptPayload:(NSData * _Nonnull)nil];
    XCTAssertNil(result);
}

- (void)testEncryptPayload_emptyData {
    NSData *empty = [NSData data];
    NSData *packet = [self.client encryptPayload:empty];
    XCTAssertNotNil(packet);
    XCTAssertGreaterThanOrEqual(packet.length, 34);
}

- (void)testDecryptBody_wrongMacFails {
    NSData *payload = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *packet = [self.client encryptPayload:payload];
    NSData *header = [packet subdataWithRange:NSMakeRange(0, 34)];
    NSData *body   = [packet subdataWithRange:NSMakeRange(34, packet.length - 34)];

    size_t bodyLength = 0;
    NSData *correctMac = nil;
    [self.server decryptHeader:header outLength:&bodyLength outBodyMac:&correctMac];

    // Supply a zeroed (wrong) MAC instead
    NSData *wrongMac = ZeroData(16);
    NSData *decrypted = [self.server decryptBody:body expectedMac:wrongMac];
    XCTAssertNil(decrypted, @"Wrong MAC must fail body decryption");
}

@end
