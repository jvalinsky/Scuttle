# Cryptographic APIs

## Scuttle Crypto Stack

| Layer | Algorithm | Implementation |
|-------|-----------|----------------|
| Signing | Ed25519 | TweetNaCl |
| Hashing | SHA-256 | CommonCrypto/OpenSSL |
| Hashing | BLAKE2b | Custom |
| Hashing | BLAKE3 | Custom |
| MAC | HMAC-SHA512 | CommonCrypto/OpenSSL |
| Encryption | xsalsa20poly1305 | TweetNaCl |

## TweetNaCl

**Files:** `Sources/tweetnacl.h`, `Sources/tweetnacl.c`

### Ed25519 Key Generation

```c
// Generate keypair
int crypto_sign_keypair(unsigned char *pk, unsigned char *sk);
```

### Ed25519 Signing

```c
// Sign message (includes message + signature)
int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen,
                        const unsigned char *m, unsigned long long mlen,
                        const unsigned char *sk);

// Verify
int crypto_sign_ed25519_open(unsigned char *m, unsigned long long *mlen,
                             const unsigned char *sm, unsigned long long smlen,
                             const unsigned char *pk);
```

### Usage in Objective-C

```objc
// Sources/SSBMessageCodec.m
- (NSData *)signContent:(NSData *)content withKey:(NSData *)secretKey {
    unsigned char sm[128];  // message + 64-byte signature
    unsigned long long smlen;
    
    int ret = crypto_sign_ed25519(sm, &smlen, 
                                  content.bytes, content.length, 
                                  secretKey.bytes);
    if (ret != 0) return nil;
    
    return [NSData dataWithBytes:sm length:smlen];
}

- (BOOL)verifySignature:(NSData *)signature 
               forContent:(NSData *)content 
                  withKey:(NSData *)publicKey {
    unsigned char m[4096];
    unsigned long long mlen;
    
    int ret = crypto_sign_ed25519_open(m, &mlen,
                                        signature.bytes, signature.length,
                                        publicKey.bytes);
    return ret == 0;
}
```

### XSalsa20-Poly1305 (Secret Box)

```c
// Encrypt
int crypto_secretbox(unsigned char *c, const unsigned char *m,
                     unsigned long long mlen,
                     const unsigned char *n, const unsigned char *k);

// Decrypt
int crypto_secretbox_open(unsigned char *m, const unsigned char *c,
                          unsigned long long clen,
                          const unsigned char *n, const unsigned char *k);
```

## BLAKE2b

**Files:** `Sources/blake2b.h`, `Sources/blake2b.c`

### Usage

```c
// Hash to 32 bytes
int blake2b256(uint8_t out[32], const void *in, size_t inlen);

// Example
uint8_t hash[32];
blake2b256(hash, data.bytes, data.length);
```

### Objective-C Wrapper

```objc
// Sources/SSBGabbyGrove.m
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[32];
    if (blake2b256(digest, data.bytes, data.length) != 0) {
        return nil;
    }
    return [NSData dataWithBytes:digest length:32];
}
```

## BLAKE3

**Files:** `Sources/blake3.h`, `Sources/blake3.c`

### Usage

```c
// One-shot
uint8_t hash[32];
blake3(hash, 32, data, len);

// Incremental
blake3_hasher hasher;
blake3_hasher_init(&hasher);
blake3_hasher_update(&hasher, data1, len1);
blake3_hasher_update(&hasher, data2, len2);
uint8_t hash[32];
blake3_hasher_final(&hasher, hash);
```

## HMAC-SHA512

Via CommonCrypto or compatibility shim:

```objc
// Sources/SSBCommonCryptoCompat.h
void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength,
            const void *data, size_t dataLength, void *macOut);

// Usage
uint8_t hmac[64];
CCHmac(kCCHmacAlgSHA512, key.bytes, key.length, data.bytes, data.length, hmac);
```

## Random Bytes

```c
// Use TweetNaCl's randombytes ( Seeds PRNG)
#include "tweetnacl.h"
randombytes(buf, len);

// Or SecRandomCopyBytes
uint8_t buf[32];
SecRandomCopyBytes(kSecRandomDefault, 32, buf);
```
