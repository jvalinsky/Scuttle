#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBGitPackDecoder.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBBlobStore;

/// Local cache wrapping SSBBlobStore, keyed by git SHA1.
@interface SSBGitObjectStore : NSObject

- (instancetype)initWithBlobStore:(SSBBlobStore *)blobStore;

/// Registers a pack file and its corresponding index blob.
- (void)registerPackBlob:(NSString *)packBlobID idxBlob:(NSString *)idxBlobID;

/// Fetches a git object by its SHA1 hash (hex string).
/// Returns nil if not found.
- (nullable SSBGitObject *)objectForSHA1:(NSString *)sha1;

/// Returns the SSB blob ID of the pack file containing the given Git SHA1.
- (nullable NSString *)packBlobIDForSHA1:(NSString *)sha1;

@end

NS_ASSUME_NONNULL_END
