#import <Foundation/Foundation.h>
#import "SSBBitset.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBPrefixIndex stores 32-bit FNV-1a hashes of strings to provide fast filtering
 * for high-cardinality values like author IDs or thread links.
 */
@interface SSBPrefixIndex : NSObject

/**
 * Initializes a prefix index with a specific capacity (number of records).
 */
- (instancetype)initWithCapacity:(uint64_t)capacity;

/**
 * Initializes a prefix index from existing data.
 */
- (instancetype)initWithData:(NSData *)data;

/**
 * Adds a value to the index at the specified record sequence.
 */
- (void)addValue:(NSString *)value atSequence:(uint64_t)sequence;

/**
 * Filters the provided bitset, keeping only bits where the stored prefix 
 * matches the prefix of the given value.
 * @param bitset The bitset to filter (modified in place).
 * @param value The search value.
 */
- (void)filterBitset:(SSBBitset *)bitset withValue:(NSString *)value;

/**
 * Returns the raw index data (useful for persistence).
 */
@property (nonatomic, readonly) NSData *data;

@end

NS_ASSUME_NONNULL_END
