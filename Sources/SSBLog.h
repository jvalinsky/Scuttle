#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBLog manages a high-performance, append-only binary log.
 * It uses dispatch_io_t for asynchronous, non-blocking writes.
 */
@interface SSBLog : NSObject

/**
 * Initializes the log with a file path. Creates the file if it doesn't exist.
 */
- (nullable instancetype)initWithPath:(NSString *)path;

/**
 * Appends a record to the log.
 * @param data The data to append.
 * @param completion Called on the completion queue when the write is durable.
 */
- (void)appendRecord:(NSData *)data completion:(void(^)(uint64_t offset, NSError * _Nullable error))completion;

/**
 * Reads a record at a specific offset.
 * @param offset The file offset.
 * @param length The expected length of the record.
 * @param completion Called with the data or error.
 */
- (void)readRecordAtOffset:(uint64_t)offset length:(size_t)length completion:(void(^)(NSData * _Nullable data, NSError * _Nullable error))completion;

/**
 * Closes the log and flushes any pending writes.
 */
/**
 * Enumerates all records in the log.
 * @param block Called for each record with data and its offset. Return NO to stop.
 */
- (void)enumerateRecordsUsingBlock:(BOOL(^)(NSData *data, uint64_t offset))block;

- (void)close;

/**
 * Returns the current size of the log file.
 */
@property (nonatomic, readonly) uint64_t currentOffset;

@end

NS_ASSUME_NONNULL_END
