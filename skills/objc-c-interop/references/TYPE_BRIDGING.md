# Type Bridging

## Bridging C Enums to NSEnum

### C Enum Definition

```c
// SSBDiffCore.h
typedef enum {
    SSB_DIFF_ALGORITHM_MYERS = 0,
    SSB_DIFF_ALGORITHM_HISTOGRAM = 1,
    SSB_DIFF_ALGORITHM_MYERS_V
} SSBDiffAlgorithm;
```

### Objective-C Bridging

```objc
// SSBDiffEngine.h
#import "SSBDiffCore.h"

typedef NS_ENUM(NSInteger, SSBDiffAlgorithmType) {
    SSBDiffAlgorithmTypeMyers = SSB_DIFF_ALGORITHM_MYERS,
    SSBDiffAlgorithmTypeHistogram = SSB_DIFF_ALGORITHM_HISTOGRAM,
    SSBDiffAlgorithmTypeMyersV = SSB_DIFF_ALGORITHM_MYERS_V
};
```

### Usage

```objc
// Call C function with bridged type
SSBDiffAlgorithm cAlgo = (SSBDiffAlgorithm)objcAlgo;
SSBDiffResult result = ssb_diff(hashesA, countA, hashesB, countB, cAlgo);
```

## Bridging C Structures

### C Structure

```c
// SSBDiffCore.h
typedef struct {
    SSBEdit *edits;
    int count;
} SSBDiffResult;

typedef struct {
    int type;       // SSB_EDIT_MATCH, SSB_EDIT_ADD, SSB_EDIT_DELETE
    int line_a;     // Line in A (-1 for add)
    int line_b;     // Line in B (-1 for delete)
} SSBEdit;
```

### Objective-C Equivalent

```objc
// SSBDiffEngine.m
typedef NS_ENUM(NSInteger, SSBDiffEditType) {
    SSBDiffEditTypeMatch = SSB_EDIT_MATCH,
    SSBDiffEditTypeAdd = SSB_EDIT_ADD,
    SSBDiffEditTypeDelete = SSB_EDIT_DELETE
};

@interface SSBDiffHunk : NSObject
@property (nonatomic) SSBDiffEditType editType;
@property (nonatomic) NSInteger lineA;
@property (nonatomic) NSInteger lineB;
@end
```

### Converting Between

```objc
// C → ObjC
- (NSArray<SSBDiffHunk *> *)convertResult:(SSBDiffResult)result {
    NSMutableArray *hunks = [NSMutableArray array];
    for (int i = 0; i < result.count; i++) {
        SSBDiffHunk *hunk = [[SSBDiffHunk alloc] init];
        hunk.editType = (SSBDiffEditType)result.edits[i].type;
        hunk.lineA = result.edits[i].line_a;
        hunk.lineB = result.edits[i].line_b;
        [hunks addObject:hunk];
    }
    return hunks;
}
```

## Bridging Data Types

### NSData ↔ uint8_t*

```objc
// NSData → uint8_t* (read-only)
- (void)processData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    size_t len = data.length;
    processBytes(bytes, len);
}

// NSData → uint8_t* (writable - careful!)
- (NSMutableData *)modifyData:(NSData *)data {
    NSMutableData *mutable = [data mutableCopy];
    uint8_t *bytes = mutable.mutableBytes;
    // modify bytes...
    return mutable;
}

// uint8_t* → NSData (no copy)
- (NSData *)createDataFromBuffer:(uint8_t *)buffer length:(size_t)len {
    return [NSData dataWithBytesNoCopy:buffer 
                                 length:len
                           freeWhenDone:NO];  // Don't free - caller owns
}
```

### NSString ↔ const char*

```objc
// NSString → const char*
const char *str = [nsString UTF8String];
processCString(str);

// const char* → NSString
NSString *nsString = [NSString stringWithUTF8String:cString];
```

## Constant Bridging

### C Constants

```c
// SSBDiffCore.h
#define SSB_DIFF_ALGORITHM_MYERS 0
#define SSB_DIFF_ALGORITHM_HISTOGRAM 1
```

### ObjC Constants

```objc
// SSDiffEngine.m
static const NSInteger SSBDiffAlgorithmMyers = SSB_DIFF_ALGORITHM_MYERS;
static const NSInteger SSBDiffAlgorithmHistogram = SSB_DIFF_ALGORITHM_HISTOGRAM;
```
