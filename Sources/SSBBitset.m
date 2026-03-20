#import "SSBBitset.h"
#ifdef __APPLE__
#import <Accelerate/Accelerate.h>
#import <simd/simd.h>
#endif

@interface SSBBitset () {
    NSMutableData *_buffer;
    uint64_t _capacity;
}
@end

@implementation SSBBitset

- (instancetype)initWithCapacity:(uint64_t)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        // Align to 32 bytes (256 bits) for SIMD efficiency
        uint64_t byteCount = (capacity + 7) / 8;
        uint64_t alignedByteCount = (byteCount + 31) & ~31;
        _buffer = [NSMutableData dataWithLength:alignedByteCount];
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _buffer = [data mutableCopy];
        _capacity = data.length * 8;
    }
    return self;
}

- (void)setBitAtIndex:(uint64_t)index {
    if (index >= _capacity) return;
    uint8_t *bytes = _buffer.mutableBytes;
    bytes[index / 8] |= (1 << (index % 8));
}

- (void)clearBitAtIndex:(uint64_t)index {
    if (index >= _capacity) return;
    uint8_t *bytes = _buffer.mutableBytes;
    bytes[index / 8] &= ~(1 << (index % 8));
}

- (BOOL)isBitSetAtIndex:(uint64_t)index {
    if (index >= _capacity) return NO;
    const uint8_t *bytes = _buffer.bytes;
    return (bytes[index / 8] & (1 << (index % 8))) != 0;
}

- (void)andWithBitset:(SSBBitset *)other {
    NSData *otherData = other.data;
    size_t selfLen  = _buffer.length;
    size_t otherLen = otherData.length;
    size_t commonLen = MIN(selfLen, otherLen);

    uint8_t *dest = (uint8_t *)_buffer.mutableBytes;
    const uint8_t *src = (const uint8_t *)otherData.bytes;
    for (size_t i = 0; i < commonLen; i++) {
        dest[i] &= src[i];
    }

    if (selfLen > otherLen) {
        memset(dest + otherLen, 0, selfLen - otherLen);
    }
}

- (void)orWithBitset:(SSBBitset *)other {
    NSData *otherData = other.data;
    size_t selfLen  = _buffer.length;
    size_t otherLen = otherData.length;
    size_t commonLen = MIN(selfLen, otherLen);

    uint8_t *dest = (uint8_t *)_buffer.mutableBytes;
    const uint8_t *src = (const uint8_t *)otherData.bytes;
    for (size_t i = 0; i < commonLen; i++) {
        dest[i] |= src[i];
    }
}

- (void)not {
    uint8_t *dest = (uint8_t *)_buffer.mutableBytes;
    size_t fullBytes = (size_t)(_capacity / 8);
    uint8_t remainingBits = (uint8_t)(_capacity % 8);

    for (size_t i = 0; i < fullBytes; i++) {
        dest[i] = ~dest[i];
    }

    if (remainingBits > 0) {
        uint8_t mask = (uint8_t)((1u << remainingBits) - 1u);
        dest[fullBytes] = (uint8_t)(~dest[fullBytes]) & mask;
        fullBytes += 1;
    }

    // Keep padded alignment bytes deterministic and out of logical capacity.
    if (fullBytes < _buffer.length) {
        memset(dest + fullBytes, 0, _buffer.length - fullBytes);
    }
}

- (uint64_t)countSetBits {
    uint64_t total = 0;
    const uint8_t *bytes = (const uint8_t *)_buffer.bytes;
    size_t fullBytes = (size_t)(_capacity / 8);
    uint8_t remainingBits = (uint8_t)(_capacity % 8);

    for (size_t i = 0; i < fullBytes; i++) {
        total += (uint64_t)__builtin_popcount((unsigned int)bytes[i]);
    }
    if (remainingBits > 0) {
        uint8_t mask = (uint8_t)((1u << remainingBits) - 1u);
        total += (uint64_t)__builtin_popcount((unsigned int)(bytes[fullBytes] & mask));
    }
    return total;
}

- (NSData *)data {
    return [_buffer copy];
}

- (uint64_t)capacity {
    return _capacity;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[SSBBitset alloc] initWithData:self.data];
}

@end
