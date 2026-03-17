#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBLog manages a high-performance, append-only binary log.
 * Uses dispatch_io_t for asynchronous, non-blocking writes.
 * All records are length-prefixed (4-byte uint32_t LE) followed by the BIPF payload.
 *
 * Sequence numbers are 0-based record indices, NOT byte offsets.
 * A companion ".offsets" file maps each record index to its byte offset in the log.
 */
@interface SSBLog : NSObject

/**
 * Initializes the log with a file path. Creates the file if it doesn't exist.
 * Also loads (or rebuilds) the companion offset map from <path>.offsets.
 */
- (nullable instancetype)initWithPath:(NSString *)path;

/**
 * Appends a length-prefixed record to the log.
 * @param data The full record bytes (4-byte length prefix + BIPF payload).
 * @param completion Called on the IO queue when the write is durable.
 *                   First parameter is the 0-based record index, NOT a byte offset.
 */
- (void)appendRecord:(NSData *)data completion:(void(^)(uint64_t recordIndex, NSError * _Nullable error))completion;

/**
 * Reads the BIPF payload of the record at the given 0-based record index.
 * The 4-byte length prefix is consumed internally; the callback receives only the payload.
 */
- (void)readRecordAtIndex:(uint64_t)index completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion;

/**
 * Reads raw bytes at a specific byte offset.
 * Prefer readRecordAtIndex: for record-level access.
 */
- (void)readRecordAtOffset:(uint64_t)offset length:(size_t)length completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion;

/**
 * Enumerates all records synchronously (blocking the caller's thread).
 * @param block Called for each record with the BIPF payload and its 0-based record index.
 *              Return NO to stop enumeration.
 */
- (void)enumerateRecordsUsingBlock:(BOOL(^)(NSData *data, uint64_t recordIndex))block;

/**
 * Flushes pending writes, saves the offset map, and closes the log.
 */
- (void)close;

/** Number of records in the log. Thread-safe. */
@property (nonatomic, readonly) uint64_t recordCount;

/** Current size of the log file in bytes. Thread-safe. */
@property (nonatomic, readonly) uint64_t currentOffset;

@end

NS_ASSUME_NONNULL_END
