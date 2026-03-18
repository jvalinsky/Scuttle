---
name: objc-c-interop
description: Safe bridging between Objective-C and C code including direct header imports, type bridging, memory management, and callback patterns.
---

# Objective-C to C Interoperability

This skill provides expertise in safely bridging Objective-C and C code, including header imports, type bridging, and memory management at the boundary.

## When to Use This Skill

Use this skill when you are:
- Calling C functions from Objective-C
- Bridging C enums to Objective-C enums
- Managing memory across the ObjC/C boundary
- Working with C libraries (TweetNaCl, BLAKE, diff)
- Creating C callbacks from Objective-C

## Patterns Used in Scuttle

### Direct Header Import

**Pattern:** Import C headers directly in .m files (no bridging header needed)

```objc
// Sources/SSBRoomClient.m line 13
#import "tweetnacl.h"
#import "blake2b.h"
```

No bridging header needed because:
1. TweetNaCl and BLAKE define C functions only
2. .m files can directly import .h files

### TweetNaCl Usage

```objc
// Sources/SSBMessageCodec.m
#import "tweetnacl.h"

- (NSData *)signData:(NSData *)data withKey:(NSData *)secretKey {
    unsigned char signature[64];
    unsigned long long siglen;
    
    int ret = crypto_sign_ed25519(signature, &siglen,
                                   data.bytes, data.length,
                                   secretKey.bytes);
    if (ret != 0) return nil;
    
    return [NSData dataWithBytes:signature length:siglen];
}
```

## Type Bridging

### C Enum to NSEnum

```objc
// C header: SSBDiffCore.h
typedef enum {
    SSB_DIFF_ALGORITHM_MYERS = 0,
    SSB_DIFF_ALGORITHM_HISTOGRAM = 1
} SSBDiffAlgorithm;

// Objective-C: SSBDiffEngine.h
#import "SSBDiffCore.h"

typedef NS_ENUM(NSInteger, SSBDiffAlgorithmType) {
    SSBDiffAlgorithmTypeMyers = SSB_DIFF_ALGORITHM_MYERS,
    SSBDiffAlgorithmTypeHistogram = SSB_DIFF_ALGORITHM_HISTOGRAM
};
```

### Matching C Structures

```objc
// C: SSBDiffCore.h
typedef struct {
    SSBEdit *edits;
    int count;
} SSBDiffResult;

// Objective-C wrapper: SSBDiffEngine.m
- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)a 
                            withString:(NSString *)b 
                             algorithm:(SSBDiffAlgorithmType)type {
    // Convert NSString → uint32_t hashes
    // Call C function
    SSBDiffResult result = ssb_diff(hashesA, countA, hashesB, countB,
                                     (SSBDiffAlgorithm)type);
    // Convert results back to NSArray
    // ...
}
```

## Memory Management

### Critical: Match malloc with free

```objc
// Correct: match allocations
uint32_t *buffer = malloc(sizeof(uint32_t) * count);
// ... use buffer ...
free(buffer);  // MUST match malloc

// WRONG: mixing allocators
uint32_t *buffer = malloc(sizeof(uint32_t) * count);
// ... use buffer ...
[buffer release];  // WRONG! Will crash
```

### C Function That Allocates

```objc
// SSBDiffCore.c returns allocated memory
SSBDiffResult result = ssb_diff(hashesA, countA, hashesB, countB, algo);

// Objective-C MUST free it
ssb_diff_free_result(result);  // Frees result.edits
```

### Allocating in ObjC, Freeing in C

```objc
// Allocate in ObjC
uint32_t *hashes = malloc(sizeof(uint32_t) * count);
// Fill data
// Pass to C
processHashes(hashes, count);
// C should NOT free - ObjC owns it
free(hashes);  // ObjC frees
```

### Bridging with __bridge

```objc
// C to ObjC (no ownership transfer)
NSData *data = (__bridge_transfer NSData *)cBuffer;
// ObjC now owns data, will release on dealloc

// ObjC to C (no ownership transfer)  
const void *bytes = (__bridge const void *)data;
// C can read, ObjC still owns
```

## Reference Files

- [C_CALLS_FROM_OBJC.md](references/C_CALLS_FROM_OBJC.md) - Direct imports
- [TYPE_BRIDGING.md](references/TYPE_BRIDGING.md) - Enum/struct mapping
- [MEMORY_MANAGEMENT.md](references/MEMORY_MANAGEMENT.md) - malloc/free
- [DIFF_ENGINE_EXAMPLE.md](references/DIFF_ENGINE_EXAMPLE.md) - Complete example
