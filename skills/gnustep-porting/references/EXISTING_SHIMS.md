# Existing Compatibility Shims

## Overview

Scuttle already has compatibility shims for:

| Shim | File | Purpose |
|------|------|---------|
| Logging | `SSBLogCompat.h` | os/log → NSLog |
| Crypto | `SSBCommonCryptoCompat.h` | CommonCrypto → OpenSSL |
| BLAKE | `blake2b.h/c` | Standalone implementation |
| TweetNaCl | `tweetnacl.h/c` | Standalone crypto |

## SSBLogCompat.h

**File:** `Sources/SSBLogCompat.h`

Maps Apple's unified logging to NSLog:

```c
#ifdef __APPLE__
    #import <os/log.h>
#else
    #import <Foundation/Foundation.h>

    typedef NSString * os_log_t;

    #define os_log_create(subsystem, category) \
        [NSString stringWithFormat:@"%s.%s", subsystem, category]

    #define os_log_info(log, format, ...) \
        NSLog((@"[%@] INFO: " format), log, ##__VA_ARGS__)

    #define os_log_error(log, format, ...) \
        NSLog((@"[%@] ERROR: " format), log, ##__VA_ARGS__)

    #define os_log_debug(log, format, ...) \
        NSLog((@"[%@] DEBUG: " format), log, ##__VA_ARGS__)

    #define os_log("%{public}@", message) \
        NSLog(@"%@", message)
#endif
```

## SSBCommonCryptoCompat.h

**File:** `Sources/SSBCommonCryptoCompat.h`

Maps CommonCrypto to OpenSSL:

```c
#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #import <Foundation/Foundation.h>
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    #include <openssl/evp.h>

    // Type aliases
    typedef unsigned int CC_LONG;
    #define CC_SHA256_DIGEST_LENGTH 32

    // SHA-256
    static inline unsigned char * CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
        return SHA256((const unsigned char *)data, len, md);
    }

    // HMAC
    static inline void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength,
                              const void *data, size_t dataLength, void *macOut) {
        unsigned int maclen;
        switch (alg) {
            case kCCHmacAlgSHA512:
                HMAC(EVP_sha512(), key, keyLength, data, dataLength, macOut, &maclen);
                break;
            // ... other algorithms
        }
    }
#endif
```

## Standalone Crypto

### blake2b.h/c

**Files:** `Sources/blake2b.h`, `Sources/blake2b.c`

No external dependencies - self-contained BLAKE2b implementation.

### blake3.h/c

**Files:** `Sources/blake3.h`, `Sources/blake3.c`

Self-contained BLAKE3 implementation.

### tweetnacl.h/c

**Files:** `Sources/tweetnacl.h`, `Sources/tweetnacl.c`

Self-contained NaCl library with:
- Ed25519 signing
- XSalsa20-Poly1305 encryption
- Random bytes

## What Still Needs Shim

| Component | Status | Notes |
|-----------|--------|-------|
| os/log | Done | SSBLogCompat.h |
| CommonCrypto | Done | SSBCommonCryptoCompat.h |
| Security.framework | Pending | Need Keychain shim |
| Network.framework | Pending | Need socket wrapper |
| os_unfair_lock | Pending | Need pthread mutex |
| dispatch_data_t | Pending | May work with GNUstep |
