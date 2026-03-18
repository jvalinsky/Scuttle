# SSB Cryptography

## Overview

| Operation | Algorithm | Implementation |
|-----------|-----------|----------------|
| Signing | Ed25519 | TweetNaCl |
| Verification | Ed25519 | TweetNaCl |
| Hashing | SHA-256 | CommonCrypto/OpenSSL |
| Hashing | BLAKE2b-256 | Custom |
| Hashing | BLAKE3-256 | Custom |
| MAC | HMAC-SHA512 | CommonCrypto/OpenSSL |
| Encryption | xsalsa20poly1305 | TweetNaCl |

## Ed25519 (Signing)

**Files:** `Sources/tweetnacl.h`, `Sources/tweetnacl.c`

### Key Generation

```c
// Generate keypair
int crypto_sign_keypair(unsigned char *pk, unsigned char *sk);

// Usage from Objective-C
unsigned char pk[32], sk[64];
crypto_sign_keypair(pk, sk);
```

### Signing

```c
// Detached signature
int crypto_sign_detached(unsigned char *sig, unsigned long long *siglen,
                         const unsigned char *m, unsigned long long mlen,
                         const unsigned char *sk);

// With sodium wrapper (Scuttle uses this)
int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen,
                        const unsigned char *m, unsigned long long mlen,
                        const unsigned char *sk);
```

### Verification

```c
// Verify detached signature  
int crypto_sign_ed25519_open(unsigned char *m, unsigned long long *mlen,
                             const unsigned char *sm, unsigned long long smlen,
                             const unsigned char *pk);
```

### Usage in Scuttle

```objc
// Sources/SSBMessageCodec.m lines 244-264
- (NSData *)signContent:(NSData *)content withKey:(NSData *)secretKey {
    unsigned char sm[128];
    unsigned long long smlen;
    
    int ret = crypto_sign_ed25519(sm, &smlen, content.bytes, content.length, secretKey.bytes);
    if (ret != 0) return nil;
    
    return [NSData dataWithBytes:smlen length:smlen];
}
```

## BLAKE2b-256

**Files:** `Sources/blake2b.h`, `Sources/blake2b.c`

### Usage

```c
// Hash to 32 bytes
int blake2b256(uint8_t out[32], const void *in, size_t inlen);

// Usage
uint8_t hash[32];
blake2b256(hash, data.bytes, data.length);
```

### Objective-C Wrapper

```objc
// Sources/SSBGabbyGrove.m lines 105-114
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[32];
    if (blake2b256(digest, data.bytes, data.length) != 0) {
        return nil;
    }
    return [NSData dataWithBytes:digest length:32];
}
```

## BLAKE3-256

**Files:** `Sources/blake3.h`, `Sources/blake3.c`

### Usage

```c
// Initialize
blake3_hasher hasher;
blake3_hasher_init(&hasher);

// Update with data
blake3_hasher_update(&hasher, data, len);

// Finalize
uint8_t hash[32];
blake3_hasher_final(&hasher, hash);

// One-shot
uint8_t hash[32];
blake3(hash, 32, data, len);
```

## HMAC-SHA512

Used in BendyButt for content signing:

```objc
// Sources/SSBCommonCryptoCompat.h
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    // Shim to OpenSSL
#endif

// HMAC-SHA512
void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength,
            const void *data, size_t dataLength, void *macOut);

// Usage
uint8_t hmac[64];
CCHmac(kCCHmacAlgSHA512, key.bytes, key.length, data.bytes, data.length, hmac);
```

## BoxStream (xsalsa20poly1305)

**File:** `Sources/SSBBoxStream.m`

Encryption stream after Secret Handshake:

```objc
// Encryption
+ (NSData *)encrypt:(NSData *)plaintext 
            withKey:(NSData *)key 
            nonce:(NSData *)nonce {
    // Uses crypto_secretbox from TweetNaCl
    // XSalsa20-Poly1305
}

// Decryption
+ (nullable NSData *)decrypt:(NSData *)ciphertext 
                    withKey:(NSData *)key 
                    nonce:(NSData *)nonce {
    // Uses crypto_secretbox_open
}
```

## Secret Handshake Keys

After SHS, derive final keys:

```objc
// Sources/SSBSecretHandshake.m
// Final key derivation uses HMAC-SHA512
// AppMACS for message authentication
```

## Hash Comparison

| Hash | Output | Use | Speed |
|------|--------|-----|-------|
| SHA-256 | 32 bytes | BendyButt keys | Fast |
| BLAKE2b-256 | 32 bytes | Bamboo, GabbyGrove | Faster |
| BLAKE3-256 | 32 bytes | Buttwoo | Fastest |

## Compatibility Shim

**File:** `Sources/SSBCommonCryptoCompat.h`

```c
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    // Maps to OpenSSL
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    #include <openssl/evp.h>
    
    #define CC_SHA256_SHA256_DIGEST_LENGTH
    // ...
#endif
```
