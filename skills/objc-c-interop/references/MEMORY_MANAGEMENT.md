# Memory Management Across ObjC/C Boundary

## Golden Rule

**Whichever side allocates must free.**

## Allocation Scenarios

### 1. C Allocates, C Frees

```c
// C function allocates
SSBDiffResult ssb_diff(...) {
    SSBDiffResult res;
    res.edits = malloc(sizeof(SSBEdit) * count);
    // ...
    return res;
}

// Caller must free
void caller(void) {
    SSBDiffResult result = ssb_diff(...);
    // Use result
    free(result.edits);  // MUST free
}
```

### 2. ObjC Allocates, C Uses (No Free)

```objc
// ObjC allocates
uint32_t *hashes = malloc(sizeof(uint32_t) * count);
// Fill hashes
[obj processHashes:hashes count:count];
// ObjC frees - C should not free
free(hashes);
```

### 3. C Function Provides Free Helper

```c
// C provides cleanup function
void ssb_diff_free_result(SSBDiffResult result) {
    free(result.edits);
}

// ObjC uses helper
SSBDiffResult result = ssb_diff(...);
// Use result
ssb_diff_free_result(result);  // Calls free()
```

## ObjC with malloc/free

### Stack vs Heap

```objc
// Stack - automatic, don't free
uint32_t buffer[1024];  // Don't free!

// Heap - manual
uint32_t *buffer = malloc(sizeof(uint32_t) * 1024);
free(buffer);  // MUST free
```

### Matching Allocations

```objc
// malloc ↔ free
uint32_t *a = malloc(100);
free(a);  // OK

// calloc ↔ free  
uint32_t *b = calloc(100, sizeof(uint32_t));
free(b);  // OK

// realloc ↔ free
uint32_t *c = malloc(100);
c = realloc(c, 200);
free(c);  // OK - just once

// WRONG - mixing
uint32_t *d = malloc(100);
delete d;  // WRONG! Use free()
```

## Bridging and Memory

### __bridge (No Transfer)

```objc
// C owns the memory, ObjC just borrows
NSData *data = (__bridge_transfer NSData *)cBuffer;

// After __bridge_transfer:
// - ARC takes ownership
// - Will call [data dealloc] when refcount drops to 0
```

### When to Use __bridge_transfer

```objc
// C returns newly allocated buffer that ObjC now owns
- (NSData *)getDataFromC {
    uint8_t *buffer = allocateBuffer();  // C allocates
    
    // Transfer ownership to ObjC
    NSData *data = (__bridge_transfer NSData *)buffer;
    // Now ARC will free when data is deallocated
    
    return data;
}
```

### When NOT to Use __bridge_transfer

```objc
// C provides pointer to existing data (not allocated for ObjC)
- (void)processCData {
    uint8_t *existingData = getExistingData();  // C owns, don't free
    
    // Just borrow - no transfer
    NSData *data = (__bridge NSData *)existingData;
    // data will NOT call free() on dealloc
}
```

## Common Mistakes

### Mistake 1: Double Free

```objc
// WRONG
uint8_t *buf = malloc(100);
NSData *data = (__bridge_transfer NSData *)buf;
free(buf);  // Double free!

// CORRECT - choose one
uint8_t *buf = malloc(100);
NSData *data = (__bridge_transfer NSData *)buf;
// Don't call free(buf) - data owns it now
```

### Mistake 2: Forgetting to Free

```objc
// WRONG - leak
uint32_t *buf = malloc(100);
// ... use buf ...

// CORRECT
uint32_t *buf = malloc(100);
// ... use buf ...
free(buf);
```

### Mistake 3: Using ObjC on C memory

```objc
// WRONG
uint8_t *buf = malloc(100);
NSData *data = buf;  // Wrong! Implicit cast

// CORRECT
uint8_t *buf = malloc(100);
NSData *data = (__bridge NSData *)buf;
```

## Example: Complete Pattern

```objc
- (NSArray *)diffWithC:(NSArray *)a other:(NSArray *)b {
    // 1. Convert ObjC → C
    uint32_t *hashesA = malloc(sizeof(uint32_t) * a.count);
    for (NSUInteger i = 0; i < a.count; i++) {
        hashesA[i] = [self hashForString:a[i]];
    }
    
    uint32_t *hashesB = malloc(sizeof(uint32_t) * b.count);
    for (NSUInteger i = 0; i < b.count; i++) {
        hashesB[i] = [self hashForString:b[i]];
    }
    
    // 2. Call C function
    SSBDiffResult result = ssb_diff(hashesA, (int)a.count,
                                     hashesB, (int)b.count,
                                     SSB_DIFF_ALGORITHM_MYERS);
    
    // 3. Convert result to ObjC
    NSMutableArray *diff = [NSMutableArray array];
    for (int i = 0; i < result.count; i++) {
        [diff addObject:@(result.edits[i].type)];
    }
    
    // 4. Clean up C memory
    ssb_diff_free_result(result);  // Frees result.edits
    free(hashesA);  // Free our input buffers
    free(hashesB);
    
    return diff;
}
```
