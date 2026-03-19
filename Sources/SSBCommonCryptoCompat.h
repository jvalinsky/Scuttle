#ifndef SSBCommonCryptoCompat_h
#define SSBCommonCryptoCompat_h

#ifdef __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #import <Foundation/Foundation.h>
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    #include <openssl/evp.h>

    // 2026 Linux/GNUstep Compatibility Shim for Apple's CommonCrypto
    
    typedef unsigned int CC_LONG;
    #define CC_SHA256_DIGEST_LENGTH 32

    // Map CC_SHA256 directly to OpenSSL's SHA256
    static inline unsigned char * CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
        return SHA256((const unsigned char *)data, len, md);
    }

    // Map CCHmac Algorithm constants
    enum {
        kCCHmacAlgSHA256 = 1
    };
    typedef uint32_t CCHmacAlgorithm;

    // Map CCHmac directly to OpenSSL's HMAC
    static inline void CCHmac(CCHmacAlgorithm alg, const void *key, size_t keyLength, 
                              const void *data, size_t dataLength, void *macOut) {
        if (alg == kCCHmacAlgSHA256) {
            unsigned int len = CC_SHA256_DIGEST_LENGTH;
            HMAC(EVP_sha256(), key, (int)keyLength, (const unsigned char *)data, dataLength, (unsigned char *)macOut, &len);
        }
    }

#endif /* __APPLE__ */

#endif /* SSBCommonCryptoCompat_h */
