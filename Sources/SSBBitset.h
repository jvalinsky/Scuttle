#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBBitset provides a SIMD-accelerated bitvector implementation.
 * Optimized for Accelerate.framework (SIMD) on Apple Silicon and Intel.
 */
@interface SSBBitset : NSObject <NSCopying>

/**
 * Initializes a bitset with a specific capacity (number of bits).
 */
- (instancetype)initWithCapacity:(uint64_t)capacity;

/**
 * Initializes a bitset from existing data.
 */
- (instancetype)initWithData:(NSData *)data;

/**
 * Sets the bit at the specified index to 1.
 */
- (void)setBitAtIndex:(uint64_t)index;

/**
 * Clears the bit at the specified index to 0.
 */
- (void)clearBitAtIndex:(uint64_t)index;

/**
 * Returns YES if the bit at the specified index is set.
 */
- (BOOL)isBitSetAtIndex:(uint64_t)index;

/**
 * Performs a bitwise AND operation with another bitset and stores the result in this bitset.
 * Uses SIMD acceleration.
 */
- (void)andWithBitset:(SSBBitset *)other;

/**
 * Performs a bitwise OR operation with another bitset and stores the result in this bitset.
 * Uses SIMD acceleration.
 */
- (void)orWithBitset:(SSBBitset *)other;

/**
 * Performs a bitwise NOT operation on this bitset.
 * Uses SIMD acceleration.
 */
- (void)not;

/**
 * Returns the number of set bits (popcount).
 */
- (uint64_t)countSetBits;

/**
 * The underlying raw data.
 */
@property (nonatomic, readonly) NSData *data;

/**
 * The capacity of the bitset in bits.
 */
@property (nonatomic, readonly) uint64_t capacity;

@end

NS_ASSUME_NONNULL_END
