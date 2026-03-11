#import "SSBPrefixIndex.h"
#import <zlib.h>

@interface SSBPrefixIndex () {
    NSMutableData *_buffer;
    uint64_t _capacity;
}
@end

@implementation SSBPrefixIndex

- (instancetype)initWithCapacity:(uint64_t)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _buffer = [NSMutableData dataWithLength:capacity * sizeof(uint32_t)];
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _buffer = [data mutableCopy];
        _capacity = data.length / sizeof(uint32_t);
    }
    return self;
}

- (void)addValue:(NSString *)value atSequence:(uint64_t)sequence {
    if (sequence >= _capacity) return;
    
    uint32_t *prefixes = _buffer.mutableBytes;
    const char *utf8 = value.UTF8String;
    prefixes[sequence] = (uint32_t)crc32(0, (const Bytef *)utf8, (uInt)strlen(utf8));
}

- (void)filterBitset:(SSBBitset *)bitset withValue:(NSString *)value {
    const uint32_t *prefixes = _buffer.bytes;
    const char *utf8 = value.UTF8String;
    uint32_t targetPrefix = (uint32_t)crc32(0, (const Bytef *)utf8, (uInt)strlen(utf8));
    
    uint64_t count = MIN(_capacity, bitset.capacity);
    for (uint64_t i = 0; i < count; i++) {
        // Only check bits that are already set
        if ([bitset isBitSetAtIndex:i]) {
            if (prefixes[i] != targetPrefix) {
                [bitset clearBitAtIndex:i];
            }
        }
    }
}

- (NSData *)data {
    return [_buffer copy];
}

@end
