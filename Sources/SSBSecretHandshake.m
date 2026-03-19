#import "SSBSecretHandshake.h"
#import "tweetnacl.h"
#import "SSBCommonCryptoCompat.h"
#import "SSBLogCompat.h"

static os_log_t ssb_shs_log;

@interface SSBSecretHandshake () {
    unsigned char _clientEphPubKey[32];
    unsigned char _clientEphSecKey[32];
    
    unsigned char _serverEphPubKey[32];
    unsigned char _serverEphSecKey[32];
    
    // Shared secrets
    unsigned char _a_b[32];
    unsigned char _a_B[32];
    unsigned char _A_b[32];
}

@property (nonatomic, readwrite) BOOL isClient;
@property (nonatomic, readwrite, nullable) NSData *clientToServerKey;
@property (nonatomic, readwrite, nullable) NSData *serverToClientKey;
@property (nonatomic, readwrite, nullable) NSData *clientToServerNonce;
@property (nonatomic, readwrite, nullable) NSData *serverToClientNonce;
@property (nonatomic, strong) NSData *networkIdentifier;
@property (nonatomic, strong) NSData *appKey;

@property (nonatomic, strong) NSData *localIdentitySecret;
@property (nonatomic, strong) NSData *localIdentityPublic;
@property (nonatomic, strong, nullable) NSData *remoteIdentityPublic;

@property (nonatomic, strong) NSData *localAppMac;
@property (nonatomic, strong) NSData *remoteAppMac;
@property (nonatomic, strong) NSData *helloBuf;

@end

@implementation SSBSecretHandshake

+ (void)initialize {
    if (self == [SSBSecretHandshake class]) {
        ssb_shs_log = os_log_create("com.scuttlebutt.network", "SHS");
    }
}

- (instancetype)initWithRole:(BOOL)isClient
               localIdentity:(NSData *)localIdentitySecret
             remotePublicKey:(nullable NSData *)remotePublicKey {
    self = [super init];
    if (self) {
        _isClient = isClient;
        _localIdentitySecret = localIdentitySecret;
        if (localIdentitySecret.length == 64) {
            _localIdentityPublic = [localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
        }
        _remoteIdentityPublic = remotePublicKey;
        
        // Default SSB network/application key used by public SSB rooms.
        unsigned char defaultNetId[32] = {
            0xd4, 0xa1, 0xcb, 0x88, 0xa6, 0x6f, 0x02, 0xf8,
            0xdb, 0x63, 0x5c, 0xe2, 0x64, 0x41, 0xcc, 0x5d,
            0xac, 0x1b, 0x08, 0x42, 0x0c, 0xea, 0xac, 0x23,
            0x08, 0x39, 0xb7, 0x55, 0x84, 0x5a, 0x9f, 0xfb
        };
        _networkIdentifier = [NSData dataWithBytes:defaultNetId length:32];
        _appKey = _networkIdentifier;
    }
    return self;
}

- (NSData *)createHello {
    if (self.isClient) {
        os_log_info(ssb_shs_log, "Generating Client Hello");
        crypto_box_curve25519xsalsa20poly1305_keypair(_clientEphPubKey, _clientEphSecKey);
        unsigned char hmacOut[64];
        CCHmac(kCCHmacAlgSHA512, self.appKey.bytes, self.appKey.length, _clientEphPubKey, 32, hmacOut);
        self.localAppMac = [NSData dataWithBytes:hmacOut length:32];
        NSMutableData *hello = [NSMutableData dataWithBytes:hmacOut length:32];
        [hello appendBytes:_clientEphPubKey length:32];
        return hello;
    } else {
        os_log_info(ssb_shs_log, "Generating Server Hello");
        // Server ephemeral key (b) is generated in processHello when client's hello arrives.
        unsigned char hmacOut[64];
        CCHmac(kCCHmacAlgSHA512, self.appKey.bytes, self.appKey.length, _serverEphPubKey, 32, hmacOut);
        self.localAppMac = [NSData dataWithBytes:hmacOut length:32];
        NSMutableData *hello = [NSMutableData dataWithBytes:hmacOut length:32];
        [hello appendBytes:_serverEphPubKey length:32];
        return hello;
    }
}

- (BOOL)processHello:(NSData *)helloData {
    if (helloData.length != 64) return NO;
    const unsigned char *receivedMac = helloData.bytes;
    const unsigned char *receivedPubKey = helloData.bytes + 32;
    
    unsigned char expectedMac[64];
    CCHmac(kCCHmacAlgSHA512, self.appKey.bytes, self.appKey.length, receivedPubKey, 32, expectedMac);
    if (memcmp(receivedMac, expectedMac, 32) != 0) {
        os_log_error(ssb_shs_log, "Hello HMAC failure");
        return NO;
    }
    
    self.remoteAppMac = [NSData dataWithBytes:receivedMac length:32];
    
    if (self.isClient) {
        os_log_info(ssb_shs_log, "Processing Server Hello (Role=Client)");
        memcpy(_serverEphPubKey, receivedPubKey, 32);
        if (crypto_scalarmult_curve25519(_a_b, _clientEphSecKey, _serverEphPubKey) != 0) return NO;
    } else {
        os_log_info(ssb_shs_log, "Processing Client Hello (Role=Server)");
        memcpy(_clientEphPubKey, receivedPubKey, 32);
        // Server generates b here
        crypto_box_curve25519xsalsa20poly1305_keypair(_serverEphPubKey, _serverEphSecKey);
        if (crypto_scalarmult_curve25519(_a_b, _serverEphSecKey, _clientEphPubKey) != 0) return NO;
    }
    return YES;
}

- (NSData *)createAuth {
    os_log_info(ssb_shs_log, "Generating Client Auth message");
    
    // 1. Convert Remote Ed25519 PubKey to Curve25519 PubKey
    if (self.remoteIdentityPublic.length != 32) return nil;
    unsigned char curveRemotePubKey[32];
    crypto_sign_ed25519_pk_to_curve25519(curveRemotePubKey, self.remoteIdentityPublic.bytes);
    
    // 2. a_B = scalarmult(ClientEphSecKey, curveRemotePubKey)
    if (crypto_scalarmult_curve25519(_a_B, _clientEphSecKey, curveRemotePubKey) != 0) return nil;
    
    // 3. secret2 = SHA256(netId + a_b + a_B)
    unsigned char secret2[32];
    NSMutableData *sec2Msg = [NSMutableData data];
    [sec2Msg appendData:self.networkIdentifier];
    [sec2Msg appendBytes:_a_b length:32];
    [sec2Msg appendBytes:_a_B length:32];
    CC_SHA256(sec2Msg.bytes, (CC_LONG)sec2Msg.length, secret2);
    
    // 4. Build sigMsg: netId + ServerPublicKey + SHA256(a_b)
    unsigned char secHash[32]; CC_SHA256(_a_b, 32, secHash);
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier];
    [sigMsg appendData:self.remoteIdentityPublic];
    [sigMsg appendBytes:secHash length:32];
    
    // 5. Sign
    unsigned char sm[64 + sigMsg.length]; unsigned long long smlen = 0;
    crypto_sign_ed25519(sm, &smlen, sigMsg.bytes, sigMsg.length, self.localIdentitySecret.bytes);
    
    // 6. Box(sig + localPublic)
    NSMutableData *helloBuf = [NSMutableData dataWithBytes:sm length:64];
    [helloBuf appendData:self.localIdentityPublic];
    self.helloBuf = helloBuf;
    
    unsigned char nonce[24] = {0};
    size_t mlen = helloBuf.length + 32;
    unsigned char *m = calloc(1, mlen); unsigned char *c = calloc(1, mlen);
    memcpy(m + 32, helloBuf.bytes, helloBuf.length);
    crypto_secretbox_xsalsa20poly1305(c, m, mlen, nonce, secret2);
    NSData *authData = [NSData dataWithBytes:c + 16 length:mlen - 16];
    free(m); free(c);
    return authData;
}

- (BOOL)processAuth:(NSData *)authData {
    if (authData.length != 112) return NO;
    os_log_info(ssb_shs_log, "Processing Client Auth (Role=Server)");
    
    unsigned char curveLocalSec[32];
    crypto_sign_ed25519_sk_to_curve25519(curveLocalSec, self.localIdentitySecret.bytes);
    if (crypto_scalarmult_curve25519(_a_B, curveLocalSec, _clientEphPubKey) != 0) return NO;
    
    unsigned char secret2[32];
    NSMutableData *sec2Msg = [NSMutableData data];
    [sec2Msg appendData:self.networkIdentifier];
    [sec2Msg appendBytes:_a_b length:32];
    [sec2Msg appendBytes:_a_B length:32];
    CC_SHA256(sec2Msg.bytes, (CC_LONG)sec2Msg.length, secret2);
    
    size_t clen = authData.length + 16;
    unsigned char *c = calloc(1, clen); unsigned char *m = calloc(1, clen);
    unsigned char nonce[24] = {0};
    memcpy(c + 16, authData.bytes, authData.length);
    if (crypto_secretbox_xsalsa20poly1305_open(m, c, clen, nonce, secret2) != 0) {
        free(m); free(c); return NO;
    }
    
    unsigned char *sigA = m + 32;
    unsigned char *clientId = sigA + 64;
    self.remoteIdentityPublic = [NSData dataWithBytes:clientId length:32];
    
    unsigned char secHash[32]; CC_SHA256(_a_b, 32, secHash);
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier];
    [sigMsg appendData:self.localIdentityPublic];
    [sigMsg appendBytes:secHash length:32];
    
    unsigned char sm[64 + sigMsg.length]; memcpy(sm, sigA, 64); memcpy(sm + 64, sigMsg.bytes, sigMsg.length);
    unsigned char v_m[64 + sigMsg.length]; unsigned long long v_mlen = 0;
    if (crypto_sign_ed25519_open(v_m, &v_mlen, sm, sizeof(sm), clientId) != 0) {
        free(m); free(c); return NO;
    }
    
    self.helloBuf = [NSData dataWithBytes:sigA length:96];
    free(m); free(c);
    return YES;
}

- (NSData *)createAccept {
    os_log_info(ssb_shs_log, "Generating Server Accept");
    
    // b_A: Bob's ephemeral secret (b) and Alice's persistent public (A)
    unsigned char alicePersistentCurvepk[32];
    crypto_sign_ed25519_pk_to_curve25519(alicePersistentCurvepk, self.remoteIdentityPublic.bytes);
    if (crypto_scalarmult_curve25519(_A_b, _serverEphSecKey, alicePersistentCurvepk) != 0) return nil;
    
    unsigned char secret3[32];
    NSMutableData *sec3Msg = [NSMutableData data];
    [sec3Msg appendData:self.networkIdentifier];
    [sec3Msg appendBytes:_a_b length:32];
    [sec3Msg appendBytes:_a_B length:32];
    [sec3Msg appendBytes:_A_b length:32];
    CC_SHA256(sec3Msg.bytes, (CC_LONG)sec3Msg.length, secret3);
    
    unsigned char secHash[32]; CC_SHA256(_a_b, 32, secHash);
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier];
    [sigMsg appendData:self.helloBuf];
    [sigMsg appendBytes:secHash length:32];
    
    unsigned char sm[64 + sigMsg.length]; unsigned long long smlen = 0;
    crypto_sign_ed25519(sm, &smlen, sigMsg.bytes, sigMsg.length, self.localIdentitySecret.bytes);
    
    unsigned char nonce[24] = {0};
    size_t mlen = 64 + 32; // sig only
    unsigned char *m = calloc(1, mlen); unsigned char *c = calloc(1, mlen);
    memcpy(m + 32, sm, 64);
    crypto_secretbox_xsalsa20poly1305(c, m, mlen, nonce, secret3);
    NSData *acceptData = [NSData dataWithBytes:c + 16 length:mlen - 16];
    
    [self deriveFinalKeys:secret3];
    free(m); free(c);
    return acceptData;
}

- (BOOL)processAccept:(NSData *)acceptData {
    if (acceptData.length != 80) return NO;
    os_log_info(ssb_shs_log, "Processing Server Accept (Role=Client)");
    
    unsigned char curveLocalSec[32];
    crypto_sign_ed25519_sk_to_curve25519(curveLocalSec, self.localIdentitySecret.bytes);
    if (crypto_scalarmult_curve25519(_A_b, curveLocalSec, _serverEphPubKey) != 0) return NO;
    
    unsigned char secret3[32];
    NSMutableData *sec3Msg = [NSMutableData data];
    [sec3Msg appendData:self.networkIdentifier];
    [sec3Msg appendBytes:_a_b length:32];
    [sec3Msg appendBytes:_a_B length:32];
    [sec3Msg appendBytes:_A_b length:32];
    CC_SHA256(sec3Msg.bytes, (CC_LONG)sec3Msg.length, secret3);
    
    size_t clen = acceptData.length + 16;
    unsigned char *c = calloc(1, clen); unsigned char *m = calloc(1, clen);
    unsigned char nonce[24] = {0};
    memcpy(c + 16, acceptData.bytes, acceptData.length);
    if (crypto_secretbox_xsalsa20poly1305_open(m, c, clen, nonce, secret3) != 0) {
        free(m); free(c); return NO; 
    }
    
    unsigned char *sigB = m + 32;
    unsigned char secHash[32]; CC_SHA256(_a_b, 32, secHash);
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier];
    [sigMsg appendData:self.helloBuf];
    [sigMsg appendBytes:secHash length:32];
    
    unsigned char sm[64 + sigMsg.length]; memcpy(sm, sigB, 64); memcpy(sm + 64, sigMsg.bytes, sigMsg.length);
    unsigned char v_m[64 + sigMsg.length]; unsigned long long v_mlen = 0;
    if (crypto_sign_ed25519_open(v_m, &v_mlen, sm, sizeof(sm), self.remoteIdentityPublic.bytes) != 0) {
        free(m); free(c); return NO;
    }
    
    [self deriveFinalKeys:secret3];
    free(m); free(c);
    return YES;
}

- (void)deriveFinalKeys:(unsigned char *)secret3 {
    unsigned char networkSecret[32]; CC_SHA256(secret3, 32, networkSecret);
    
    // Key(Alice To Bob) = H(H(sec3), BobPub)
    // Key(Bob To Alice) = H(H(sec3), AlicePub)
    
    unsigned char aliceToBob[32];
    NSMutableData *atobMsg = [NSMutableData dataWithBytes:networkSecret length:32];
    [atobMsg appendData:self.isClient ? self.remoteIdentityPublic : self.localIdentityPublic];
    CC_SHA256(atobMsg.bytes, (CC_LONG)atobMsg.length, aliceToBob);
    
    unsigned char bobToAlice[32];
    NSMutableData *btoaMsg = [NSMutableData dataWithBytes:networkSecret length:32];
    [btoaMsg appendData:self.isClient ? self.localIdentityPublic : self.remoteIdentityPublic];
    CC_SHA256(btoaMsg.bytes, (CC_LONG)btoaMsg.length, bobToAlice);
    
    self.clientToServerKey = [NSData dataWithBytes:aliceToBob length:32];
    self.serverToClientKey = [NSData dataWithBytes:bobToAlice length:32];
    
    self.clientToServerNonce = [self.remoteAppMac subdataWithRange:NSMakeRange(0, 24)];
    self.serverToClientNonce = [self.localAppMac subdataWithRange:NSMakeRange(0, 24)];
}

@end
