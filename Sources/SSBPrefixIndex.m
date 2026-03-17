#import "SSBPrefixIndex.h"

/// FNV-1a 64-bit hash folded to 32 bits.
/// Far lower collision probability than CRC32 for string identity purposes.
static uint32_t fnv1a32(const char *s) {
    uint64_t h = 14695981039346656037ULL;
    while (*s) {
        h ^= (uint8_t)*s++;
        h *= 1099511628211ULL;
    }
    return (uint32_t)(h ^ (h >> 32));
}

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
    prefixes[sequence] = fnv1a32(value.UTF8String);
}

- (void)filterBitset:(SSBBitset *)bitset withValue:(NSString *)value {
    const uint32_t *prefixes = _buffer.bytes;
    uint32_t targetHash = fnv1a32(value.UTF8String);

    uint64_t count = MIN(_capacity, bitset.capacity);
    for (uint64_t i = 0; i < count; i++) {
        if ([bitset isBitSetAtIndex:i]) {
            if (prefixes[i] != targetHash) {
                [bitset clearBitAtIndex:i];
            }
        }
    }
}

- (NSData *)data {
    return [_buffer copy];
}

@end
