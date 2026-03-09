#include <stdlib.h>
#include <unistd.h>
#include "tweetnacl.h"
#include <Security/Security.h>

void randombytes(unsigned char *ptr, unsigned long long length) {
    // arc4random_buf is the recommended native macOS PRNG
    arc4random_buf(ptr, (size_t)length);
}
