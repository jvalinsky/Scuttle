#import <Foundation/Foundation.h>
#import "SSBLog.h"
#import "SSBBitset.h"
#import "SSBPrefixIndex.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * SSBJITDB is the central coordinator for the JIT indexing engine.
 * It manages the log and lazily creates bitset and prefix indexes as needed.
 */
@interface SSBJITDB : NSObject

/**
 * Initializes JITDB with a directory for storage.
 * @param directory The directory where the log and index files will be stored.
 */
- (nullable instancetype)initWithDirectory:(NSString *)directory;

/**
 * Appends a message to the log and updates any active indexes.
 * @param message The message dictionary (author, content, etc.).
 * @param completion Called with the sequence number (offset) of the message.
 */
- (void)appendMessage:(NSDictionary<NSString *, id> *)message completion:(void(^)(uint64_t sequence, NSError * _Nullable error))completion;

/**
 * Appends a batch of messages in a single pass and saves indexes once at the end.
 * Significantly more efficient than calling appendMessage: in a loop for large bursts.
 * @param messages Array of message dictionaries.
 * @param completion Called with the first error encountered, or nil on full success.
 */
- (void)appendMessages:(NSArray<NSDictionary<NSString *, id> *> *)messages completion:(void(^)(NSError * _Nullable error))completion;

/**
 * Executes a query and returns a bitset of matching sequence numbers.
 * @param query The query dictionary (author, type, etc.).
 * @return A bitset representing the matching records.
 */
- (SSBBitset *)query:(NSDictionary<NSString *, id> *)query;

/**
 * Fetches the message data for a given sequence number.
 */
- (void)fetchMessageAtSequence:(uint64_t)sequence completion:(void(^)(NSDictionary * _Nullable message, NSError * _Nullable error))completion;

/**
 * Closes the database.
 */
- (void)close;

@end

NS_ASSUME_NONNULL_END
