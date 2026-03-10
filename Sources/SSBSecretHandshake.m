#import "SSBSecretHandshake.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonCrypto.h>
#import <os/log.h>

static os_log_t ssb_shs_log;

@interface SSBSecretHandshake () {
    unsigned char _clientEphPubKey[crypto_box_curve25519xsalsa20poly1305_PUBLICKEYBYTES];
    unsigned char _clientEphSecKey[crypto_box_curve25519xsalsa20poly1305_SECRETKEYBYTES];
    
    unsigned char _serverEphPubKey[crypto_box_curve25519xsalsa20poly1305_PUBLICKEYBYTES];
    unsigned char _serverPubKey[crypto_sign_ed25519_PUBLICKEYBYTES];
    
    // Shared secrets
    unsigned char _a_b[crypto_scalarmult_curve25519_BYTES];
    unsigned char _a_B[crypto_scalarmult_curve25519_BYTES];
    unsigned char _A_b[crypto_scalarmult_curve25519_BYTES];
}

@property (nonatomic, readwrite) BOOL isClient;
@property (nonatomic, readwrite, nullable) NSData *clientToServerKey;
@property (nonatomic, readwrite, nullable) NSData *serverToClientKey;
@property (nonatomic, readwrite, nullable) NSData *clientToServerNonce;
@property (nonatomic, readwrite, nullable) NSData *serverToClientNonce;
@property (nonatomic, strong) NSData *networkIdentifier;

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
        
        // Default SSB network identifier
        unsigned char defaultNetId[32] = {
            0xd4, 0xa1, 0xcb, 0x88, 0xa6, 0x6f, 0x02, 0xf8,
            0xdb, 0x63, 0x5c, 0xe2, 0x64, 0x41, 0xcc, 0x5d,
            0xac, 0x1b, 0x08, 0x42, 0x0c, 0xea, 0xac, 0x23,
            0x08, 0x39, 0xb7, 0x55, 0x84, 0x5a, 0x9f, 0xfb
        };
        _networkIdentifier = [NSData dataWithBytes:defaultNetId length:32];
    }
    return self;
}

- (NSData *)createHello {
    os_log_info(ssb_shs_log, "Generating Client Hello");
    
    // Generate Ephemeral Keypair (a)
    crypto_box_curve25519xsalsa20poly1305_keypair(_clientEphPubKey, _clientEphSecKey);
    
    // Client Hello is HMAC-SHA-512-256(net_id, a_pub) — first 32 bytes of HMAC-SHA-512
    unsigned char hmacOut[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, _networkIdentifier.bytes, _networkIdentifier.length,
           _clientEphPubKey, sizeof(_clientEphPubKey), hmacOut);
    
    self.localAppMac = [NSData dataWithBytes:hmacOut length:32];
    
    NSMutableData *hello = [NSMutableData data];
    [hello appendBytes:hmacOut length:32];
    [hello appendBytes:_clientEphPubKey length:32];
    return hello;
}

- (BOOL)processHello:(NSData *)helloData {
    if (helloData.length != 64) return NO;
    os_log_info(ssb_shs_log, "Processing Server Hello");
    
    const unsigned char *receivedMac = helloData.bytes;
    const unsigned char *pubKey = helloData.bytes + 32;
    
    unsigned char expectedMac[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, _networkIdentifier.bytes, _networkIdentifier.length,
           pubKey, 32, expectedMac);
    
    if (memcmp(receivedMac, expectedMac, 32) != 0) {
        os_log_error(ssb_shs_log, "Server hello HMAC failed");
        return NO;
    }
    
    self.remoteAppMac = [NSData dataWithBytes:receivedMac length:32];
    memcpy(_serverEphPubKey, pubKey, 32);
    
    // Step: Derive shared secret (a_b)
    if (crypto_scalarmult_curve25519(_a_b, _clientEphSecKey, _serverEphPubKey) != 0) {
        os_log_error(ssb_shs_log, "Client ephemeral scalarmult failed");
        return NO;
    }
    
    return YES;
}

- (NSData *)createAuth {
    os_log_info(ssb_shs_log, "Generating Client Auth message");
    
    // 1. Convert Remote Ed25519 PubKey to Curve25519 PubKey
    if (self.remoteIdentityPublic.length != 32) {
        os_log_error(ssb_shs_log, "createAuth: remoteIdentityPublic is missing or wrong length: %lu", (unsigned long)self.remoteIdentityPublic.length);
        return nil;
    }
    unsigned char curveRemotePubKey[32];
    crypto_sign_ed25519_pk_to_curve25519(curveRemotePubKey, self.remoteIdentityPublic.bytes);
    
    // 2. a_B = scalarmult(ClientEphSecKey, curveRemotePubKey)
    if (crypto_scalarmult_curve25519(_a_B, _clientEphSecKey, curveRemotePubKey) != 0) {
        os_log_error(ssb_shs_log, "a_B derivation failed");
        return nil;
    }
    
    // 3. secret2 = SHA256(netId + a_b + a_B)
    unsigned char secret2[CC_SHA256_DIGEST_LENGTH];
    NSMutableData *sec2Msg = [NSMutableData data];
    [sec2Msg appendData:self.networkIdentifier ?: [NSData data]];
    [sec2Msg appendBytes:_a_b length:32];
    [sec2Msg appendBytes:_a_B length:32];
    CC_SHA256(sec2Msg.bytes, (CC_LONG)sec2Msg.length, secret2);
    
    // 4. secHash = SHA256(a_b)
    unsigned char secHash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(_a_b, 32, secHash);
    
    // 5. Build sigMsg: netId + ServerPublicKey + secHash
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier ?: [NSData data]];
    [sigMsg appendData:self.remoteIdentityPublic ?: [NSData data]];
    [sigMsg appendBytes:secHash length:32];
    
    // 6. sign
    if (self.localIdentitySecret.length != 64) {
        os_log_error(ssb_shs_log, "createAuth: localIdentitySecret is missing or wrong length: %lu", (unsigned long)self.localIdentitySecret.length);
        return nil;
    }
    unsigned char sm[crypto_sign_ed25519_BYTES + sigMsg.length];
    unsigned long long smlen = 0;
    crypto_sign_ed25519(sm, &smlen, sigMsg.bytes, sigMsg.length, self.localIdentitySecret.bytes);
    
    // 7. helloBuf = sig + localPublic (96 bytes)
    NSMutableData *helloBuf = [NSMutableData data];
    [helloBuf appendBytes:sm length:64]; // Ed25519 sig is first 64 bytes
    [helloBuf appendData:self.localIdentityPublic ?: [NSData data]];
    self.helloBuf = helloBuf;
    
    // 8. Box it
    unsigned char nonce[24] = {0};
    size_t mlen = helloBuf.length + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    unsigned char *m = calloc(1, mlen);
    unsigned char *c = calloc(1, mlen);
    
    if (!m || !c) return nil;
    
    memcpy(m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES, helloBuf.bytes, helloBuf.length);
    crypto_secretbox_xsalsa20poly1305(c, m, mlen, nonce, secret2); 
    
    NSData *authData = [NSData dataWithBytes:c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES 
                                       length:mlen - crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES];
    free(m); free(c);
    
    return authData;
}

- (BOOL)processAuth:(NSData *)authData {
    if (authData.length != 112) return NO;
    os_log_info(ssb_shs_log, "Processing Auth message");
    return YES;
}

- (NSData *)createAccept {
    os_log_info(ssb_shs_log, "Generating Accept message");
    unsigned char mockAccept[80];
    arc4random_buf(mockAccept, 80);
    return [NSData dataWithBytes:mockAccept length:80];
}

- (BOOL)processAccept:(NSData *)acceptData {
    if (acceptData.length != 80) return NO;
    os_log_info(ssb_shs_log, "Processing Accept message");
    
    // 1. Convert Local Ed25519 SecKey to Curve25519 SecKey
    unsigned char curveLocalSec[32];
    crypto_sign_ed25519_sk_to_curve25519(curveLocalSec, self.localIdentitySecret.bytes);
    
    // 2. A_b = scalarmult(curveLocalSec, _serverEphPubKey)
    crypto_scalarmult_curve25519(_A_b, curveLocalSec, _serverEphPubKey);
    
    // 3. secret3 = SHA256(netId + a_b + a_B + A_b)
    unsigned char secret3[CC_SHA256_DIGEST_LENGTH];
    NSMutableData *sec3Msg = [NSMutableData data];
    [sec3Msg appendData:self.networkIdentifier];
    [sec3Msg appendBytes:_a_b length:32];
    [sec3Msg appendBytes:_a_B length:32];
    [sec3Msg appendBytes:_A_b length:32];
    CC_SHA256(sec3Msg.bytes, (CC_LONG)sec3Msg.length, secret3);
    
    // 4. Open Secretbox
    size_t clen = acceptData.length + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES; // 80 + 16 = 96
    unsigned char *c = calloc(1, clen);
    unsigned char *m = calloc(1, clen);
    
    unsigned char nonce[24] = {0};
    memset(c, 0, crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES);
    memcpy(c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES, acceptData.bytes, acceptData.length);
    
    if (crypto_secretbox_xsalsa20poly1305_open(m, c, clen, nonce, secret3) != 0) {
        os_log_error(ssb_shs_log, "Server accept Box failed to open");
        free(m); free(c);
        return NO;
    }
    
    unsigned char *sig = m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES; // 64 byte signature
    
    // 5. Verify the Signature
    // sigMsg = netId + helloBuf + secHash (where secHash is hash(_a_b))
    unsigned char secHash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(_a_b, 32, secHash);
    
    NSMutableData *sigMsg = [NSMutableData data];
    [sigMsg appendData:self.networkIdentifier];
    [sigMsg appendData:self.helloBuf];
    [sigMsg appendBytes:secHash length:32];
    
    // Create verification buffer format for tweetnacl: sig (64 bytes) + message
    unsigned char sm[64 + sigMsg.length];
    memcpy(sm, sig, 64);
    memcpy(sm + 64, sigMsg.bytes, sigMsg.length);
    
    unsigned char v_m[64 + sigMsg.length];
    unsigned long long v_mlen = 0;
    
    if (crypto_sign_ed25519_open(v_m, &v_mlen, sm, sizeof(sm), self.remoteIdentityPublic.bytes) != 0) {
        os_log_error(ssb_shs_log, "Server accept signature verification failed");
        free(m); free(c);
        return NO;
    }
    
    free(m); free(c);
    os_log_info(ssb_shs_log, "Server accept signature verified successfully!");
    
    // 6. Derive Final Box Stream Keys
    // networkSecret = SHA256(secret3)
    unsigned char networkSecret[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(secret3, 32, networkSecret);
    
    // enKey = SHA256(networkSecret + remotePublic)
    unsigned char clientToServer[CC_SHA256_DIGEST_LENGTH];
    NSMutableData *ctosMsg = [NSMutableData dataWithBytes:networkSecret length:32];
    [ctosMsg appendData:self.remoteIdentityPublic];
    CC_SHA256(ctosMsg.bytes, (CC_LONG)ctosMsg.length, clientToServer);
    self.clientToServerKey = [NSData dataWithBytes:clientToServer length:32];
    
    // deKey = SHA256(networkSecret + localPublic)
    unsigned char serverToClient[CC_SHA256_DIGEST_LENGTH];
    NSMutableData *stocMsg = [NSMutableData dataWithBytes:networkSecret length:32];
    [stocMsg appendData:self.localIdentityPublic];
    CC_SHA256(stocMsg.bytes, (CC_LONG)stocMsg.length, serverToClient);
    self.serverToClientKey = [NSData dataWithBytes:serverToClient length:32];
    
    // enNonce = remoteAppMac (truncated to 24)
    self.clientToServerNonce = [self.remoteAppMac subdataWithRange:NSMakeRange(0, 24)];
    // deNonce = localAppMac (truncated to 24)
    self.serverToClientNonce = [self.localAppMac subdataWithRange:NSMakeRange(0, 24)];
    
    return YES;
}

@end
