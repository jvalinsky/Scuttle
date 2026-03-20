#import "SSBRandom.h"
#include <stdlib.h>

#ifdef __APPLE__
#import <Security/Security.h>
#endif

extern void randombytes(unsigned char *ptr, unsigned long long length);

BOOL SSBFillRandomBytes(void *bytes, size_t length) {
#ifdef __APPLE__
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
