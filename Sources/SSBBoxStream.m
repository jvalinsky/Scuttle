#import "SSBBoxStream.h"
#import "tweetnacl.h"

@interface SSBBoxStream () {
    unsigned char _clientToServerNonce[crypto_secretbox_xsalsa20poly1305_NONCEBYTES];
    unsigned char _serverToClientNonce[crypto_secretbox_xsalsa20poly1305_NONCEBYTES];
}
@property (nonatomic, copy) NSData *clientToServerKey;
@property (nonatomic, copy) NSData *serverToClientKey;
@property (nonatomic, assign) BOOL isClient;
@end

@implementation SSBBoxStream

- (instancetype)initWithClientToServerKey:(NSData *)clientToServerKey
                        serverToClientKey:(NSData *)serverToClientKey
                      clientToServerNonce:(NSData *)clientToServerNonce
                      serverToClientNonce:(NSData *)serverToClientNonce {
    self = [super init];
    if (self) {
        _clientToServerKey = [clientToServerKey copy];
        _serverToClientKey = [serverToClientKey copy];
        // For simplicity in this demo, ASSUME client role. 
        // Real implementation hooks this flag from SHS.
        _isClient = YES; 
        
        memset(_clientToServerNonce, 0, crypto_secretbox_xsalsa20poly1305_NONCEBYTES);
        memset(_serverToClientNonce, 0, crypto_secretbox_xsalsa20poly1305_NONCEBYTES);
        
        if (clientToServerNonce.length == crypto_secretbox_xsalsa20poly1305_NONCEBYTES) {
            [clientToServerNonce getBytes:_clientToServerNonce length:crypto_secretbox_xsalsa20poly1305_NONCEBYTES];
        }
        if (serverToClientNonce.length == crypto_secretbox_xsalsa20poly1305_NONCEBYTES) {
            [serverToClientNonce getBytes:_serverToClientNonce length:crypto_secretbox_xsalsa20poly1305_NONCEBYTES];
        }
    }
    return self;
}

static void increment_nonce(unsigned char *nonce) {
    for (int i = 23; i >= 0; i--) {
        nonce[i]++;
        if (nonce[i] != 0) break;
    }
}

- (nullable NSData *)encryptPayload:(NSData *)payload {
    if (!payload || payload.length == 0) return nil;
    
    unsigned const char *key = _isClient ? self.clientToServerKey.bytes : self.serverToClientKey.bytes;
    unsigned char *nonce = _isClient ? _clientToServerNonce : _serverToClientNonce;
    
    unsigned char header_nonce[24];
    unsigned char body_nonce[24];
    memcpy(header_nonce, nonce, 24);
    memcpy(body_nonce, nonce, 24);
    increment_nonce(body_nonce);
    
    // 1. Encrypt Body Box
    size_t body_mlen = payload.length + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    unsigned char *body_m = calloc(1, body_mlen);
    unsigned char *body_c = calloc(1, body_mlen);
    memcpy(body_m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES, payload.bytes, payload.length);
    
    if (crypto_secretbox_xsalsa20poly1305(body_c, body_m, body_mlen, body_nonce, key) != 0) {
        free(body_m); free(body_c); return nil;
    }
    
    unsigned char body_mac[16];
    memcpy(body_mac, body_c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES, 16);
    
    // 2. Encrypt Header Box
    size_t header_mlen = 18 + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    unsigned char *header_m = calloc(1, header_mlen);
    unsigned char *header_c = calloc(1, header_mlen);
    
    uint16_t be_len = NSSwapHostShortToBig((uint16_t)payload.length);
    memcpy(header_m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES, &be_len, 2);
    memcpy(header_m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES + 2, body_mac, 16);
    
    if (crypto_secretbox_xsalsa20poly1305(header_c, header_m, header_mlen, header_nonce, key) != 0) {
        free(body_m); free(body_c); free(header_m); free(header_c); return nil;
    }
    
    // 3. Assemble Packet
    NSMutableData *packet = [NSMutableData dataWithCapacity:34 + payload.length];
    [packet appendBytes:(header_c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES) length:34];
    [packet appendBytes:(body_c + crypto_secretbox_xsalsa20poly1305_ZEROBYTES) length:payload.length];
    
    // Update stream nonces for next packet
    memcpy(nonce, body_nonce, 24);
    increment_nonce(nonce);
    
    free(body_m); free(body_c); free(header_m); free(header_c);
    return packet;
}

- (BOOL)decryptHeader:(NSData *)headerData outLength:(size_t *)outLength outBodyMac:(NSData * _Nullable __autoreleasing * _Nullable)outMac {
    if (headerData.length != 34) return NO;
    
    unsigned const char *key = _isClient ? self.serverToClientKey.bytes : self.clientToServerKey.bytes;
    unsigned char *nonce = _isClient ? _serverToClientNonce : _clientToServerNonce;
    
    size_t clen = 18 + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    unsigned char *c = calloc(1, clen);
    unsigned char *m = calloc(1, clen);
    
    memcpy(c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES, headerData.bytes, 34);
    
    if (crypto_secretbox_xsalsa20poly1305_open(m, c, clen, nonce, key) != 0) {
        free(m); free(c);
        return NO;
    }
    
    unsigned char *plain = m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    uint16_t length = 0;
    memcpy(&length, plain, 2);
    length = NSSwapBigShortToHost(length);
    
    if (outLength) *outLength = length;
    if (outMac) *outMac = [NSData dataWithBytes:(plain + 2) length:16];
    
    increment_nonce(nonce);
    free(m); free(c);
    
    return YES;
}

- (nullable NSData *)decryptBody:(NSData *)bodyData expectedMac:(NSData *)bodyMac {
    if (!bodyData || bodyMac.length != 16) return nil;
    
    unsigned const char *key = _isClient ? self.serverToClientKey.bytes : self.clientToServerKey.bytes;
    unsigned char *nonce = _isClient ? _serverToClientNonce : _clientToServerNonce;
    
    size_t clen = bodyData.length + crypto_secretbox_xsalsa20poly1305_ZEROBYTES;
    unsigned char *c = calloc(1, clen);
    unsigned char *m = calloc(1, clen);
    
    memcpy(c + crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES, bodyMac.bytes, 16);
    memcpy(c + crypto_secretbox_xsalsa20poly1305_ZEROBYTES, bodyData.bytes, bodyData.length);
    
    if (crypto_secretbox_xsalsa20poly1305_open(m, c, clen, nonce, key) != 0) {
        free(m); free(c);
        return nil;
    }
    
    NSData *recoveredBody = [NSData dataWithBytes:(m + crypto_secretbox_xsalsa20poly1305_ZEROBYTES) length:bodyData.length];
    
    increment_nonce(nonce);
    free(m); free(c);
    
    return recoveredBody;
}

@end
