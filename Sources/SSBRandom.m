#import "SSBRandom.h"
#include <stdlib.h>

#if defined(__APPLE__) && __has_include(<Security/Security.h>)
#import <Security/Security.h>
#endif

extern void randombytes(unsigned char *ptr, unsigned long long length);

BOOL SSBFillRandomBytes(void *bytes, size_t length) {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    return SecRandomCopyBytes(kSecRandomDefault, length, bytes) == errSecSuccess;
#else
    randombytes(bytes, (unsigned long long)length);
    return YES;
#endif
}

uint32_t SSBRandomUInt32(void) {
    uint32_t value = 0;
    if (!SSBFillRandomBytes(&value, sizeof(value))) {
        value = (uint32_t)arc4random();
    }
    return value;
}
