#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parses a git PACK v2 .idx file and provides O(log n) lookups for object offsets.
@interface SSBGitPackIDXParser : NSObject

/// Initialize with raw .idx file data.
/// Returns nil if the magic/version header is invalid or data is too short.
- (nullable instancetype)initWithData:(NSData *)data;

/// Returns the offset in the pack file for the given 20-byte git SHA1.
/// Returns 0 if the object is not found in this index.
- (uint64_t)offsetForSHA1:(NSData *)sha1;

/// Returns the offset for a hex string git SHA1.
- (uint64_t)offsetForHexString:(NSString *)hexString;

@end

NS_ASSUME_NONNULL_END
