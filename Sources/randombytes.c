#include <stdlib.h>
#include <unistd.h>

void SSBEnvironmentRandomBytes(void *buffer, size_t length);
#include "tweetnacl.h"

#ifdef __APPLE__
#include <Security/Security.h>
#endif

void randombytes(unsigned char *ptr, unsigned long long length) {
#ifdef __APPLE__
    arc4random_buf(ptr, (size_t)length);
#else
    // For Linux, use getentropy (available in glibc 2.25+)
    if (getentropy(ptr, (size_t)length) != 0) {
        // Handle error if necessary, though getentropy is standard in 2026
    }
#endif
}
