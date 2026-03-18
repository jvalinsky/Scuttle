# Complete Example: SSBDiffEngine

## Overview

`SSBDiffEngine.m` bridges Objective-C to C diff implementation in `SSBDiffCore.c`.

## Files

| File | Language | Purpose |
|------|----------|---------|
| `Sources/SSBDiffCore.h` | C | Header with function declarations |
| `Sources/SSBDiffCore.c` | C | Diff algorithm implementation |
| `Sources/SSBDiffEngine.h` | ObjC | Objective-C interface |
| `Sources/SSBDiffEngine.m` | ObjC | Wrapper bridging ObjC ↔ C |

## C Interface (SSBDiffCore.h)

```c
// Sources/SSBDiffCore.h
#ifndef SSBDiffCore_h
#define SSBDiffCore_h

#include <stdint.h>
#include <stddef.h>

typedef enum {
    SSB_DIFF_ALGORITHM_MYERS = 0,
    SSB_DIFF_ALGORITHM_HISTOGRAM = 1,
    SSB_DIFF_ALGORITHM_MYERS_V
} SSBDiffAlgorithm;

typedef struct {
    int type;      // 0=match, 1=add, 2=delete
    int line_a;
    int line_b;
} SSBEdit;

typedef struct {
    SSBEdit *edits;
    int count;
} SSBDiffResult;

uint32_t ssb_diff_hash_line(const char *line, size_t length);

SSBDiffResult ssb_diff(const uint32_t *hashes_a, int count_a,
                       const uint32_t *hashes_b, int count_b,
                       SSBDiffAlgorithm algo);

void ssb_diff_free_result(SSBDiffResult result);

#endif
```

## Objective-C Header (SSBDiffEngine.h)

```objc
// Sources/SSBDiffEngine.h
#import <Foundation/Foundation.h>
#import "SSBDiffCore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBDiffAlgorithmType) {
    SSBDiffAlgorithmTypeMyers = SSB_DIFF_ALGORITHM_MYERS,
    SSBDiffAlgorithmTypeHistogram = SSB_DIFF_ALGORITHM_HISTOGRAM
};

typedef NS_ENUM(NSInteger, SSBDiffEditType) {
    SSBDiffEditTypeMatch = 0,
    SSBDiffEditTypeAdd = 1,
    SSBDiffEditTypeDelete = 2
};

@interface SSBDiffHunk : NSObject
@property (nonatomic) SSBDiffEditType editType;
@property (nonatomic) NSInteger lineA;
@property (nonatomic) NSInteger lineB;
@end

@interface SSBDiffEngine : NSObject

- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)stringA
                            withString:(NSString *)stringB
                             algorithm:(SSBDiffAlgorithmType)algorithm;

@end

NS_ASSUME_NONNULL_END
```

## Objective-C Implementation (SSBDiffEngine.m)

```objc
// Sources/SSBDiffEngine.m
#import "SSBDiffEngine.h"
#import "SSBDiffCore.h"

@implementation SSBDiffHunk
@end

@implementation SSBDiffEngine

- (NSArray<SSBDiffHunk *> *)diffString:(NSString *)stringA
                            withString:(NSString *)stringB
                             algorithm:(SSBDiffAlgorithmType)algorithm {
    // Step 1: Convert NSString → uint32_t hashes
    NSArray<NSString *> *linesA = [stringA componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *linesB = [stringB componentsSeparatedByString:@"\n"];
    
    uint32_t *hashesA = malloc(sizeof(uint32_t) * linesA.count);
    for (NSUInteger i = 0; i < linesA.count; i++) {
        const char *cLine = [linesA[i] UTF8String];
        hashesA[i] = ssb_diff_hash_line(cLine, strlen(cLine));
    }
    
    uint32_t *hashesB = malloc(sizeof(uint32_t) * linesB.count);
    for (NSUInteger i = 0; i < linesB.count; i++) {
        const char *cLine = [linesB[i] UTF8String];
        hashesB[i] = ssb_diff_hash_line(cLine, strlen(cLine));
    }
    
    // Step 2: Call C function
    SSBDiffResult result = ssb_diff(hashesA, (int)linesA.count,
                                     hashesB, (int)linesB.count,
                                     (SSBDiffAlgorithm)algorithm);
    
    // Step 3: Convert result → NSArray
    NSMutableArray<SSBDiffHunk *> *hunks = [NSMutableArray array];
    for (int i = 0; i < result.count; i++) {
        SSBDiffHunk *hunk = [[SSBDiffHunk alloc] init];
        hunk.editType = (SSBDiffEditType)result.edits[i].type;
        hunk.lineA = result.edits[i].line_a;
        hunk.lineB = result.edits[i].line_b;
        [hunks addObject:hunk];
    }
    
    // Step 4: Clean up C memory
    ssb_diff_free_result(result);  // Frees result.edits
    free(hashesA);                  // Free our buffers
    free(hashesB);
    
    return hunks;
}

@end
```

## Key Patterns Demonstrated

1. **Header Import**: Direct `#import "SSBDiffCore.h"`
2. **Type Bridging**: `NS_ENUM` maps to C `enum`
3. **Data Conversion**: NSString → uint32_t array
4. **Function Call**: Pass C types to C function
5. **Result Conversion**: C struct → NSArray
6. **Memory Cleanup**: Match allocations with frees

## Usage

```objc
SSBDiffEngine *engine = [[SSBDiffEngine alloc] init];
NSArray *diff = [engine diffString:@"line1\nline2\nline3"
                        withString:@"line1\nmodified\nline3"
                         algorithm:SSBDiffAlgorithmTypeMyers];

for (SSBDiffHunk *hunk in diff) {
    NSLog(@"Edit: %ld at A:%ld B:%ld", (long)hunk.editType, 
          (long)hunk.lineA, (long)hunk.lineB);
}
```
