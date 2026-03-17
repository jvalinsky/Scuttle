# C Testing & Verification Tool Guide

## 1. Static Analysis

### cppcheck
A versatile tool for finding bugs and potential vulnerabilities.
```bash
cppcheck --enable=all --suppress=missingIncludeSystem Sources/
```

### Clang Static Analyzer (scan-build)
Best used with a build system like `make` or `xcodebuild`.
```bash
scan-build xcodebuild -project SSBNetwork.xcodeproj -scheme SSBNetwork
```

## 2. Dynamic Analysis (Sanitizers)

AddressSanitizer (ASan) and UndefinedBehaviorSanitizer (UBSan) are built into modern compilers (Clang/GCC).

### Enabling in Build
Add the following flags to your compiler and linker commands:
```bash
-fsanitize=address,undefined -fno-omit-frame-pointer
```

### What it catches:
- Out-of-bounds access (stack, heap, global)
- Use-after-free
- Double-free
- Integer overflow
- Null pointer dereference

## 3. Memory Leak Detection (Valgrind)

Note: Valgrind is primarily available on Linux.
```bash
valgrind --leak-check=full --show-leak-kinds=all ./your_test_executable
```

## 4. Fuzzing (libFuzzer)

For critical parsers (like Git PACK or MuxRPC), write a simple fuzzer target:

```c
// fuzzer_target.c
#include <stdint.h>
#include <stddef.h>
#include "SSBGitPackDecoder.h"

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    NSData *input = [NSData dataWithBytes:Data length:Size];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:input];
    if (decoder) {
        [decoder objectAtOffset:0]; // Exercise the parser
    }
    return 0;
}
```
Compile with `-fsanitize=fuzzer,address`.
