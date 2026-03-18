#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SSBMuxRPCSession;

/// Callback for blob fetch operations. Returns file path on success, error on failure.
typedef void (^SSBBlobFetchCompletion)(NSString * _Nullable localPath, NSError * _Nullable error);

/// Local disk-backed store for SSB blobs (images, files).
/// Blobs are stored as files named by their hash in ~/Library/Application Support/ScuttleKit/blobs/
@interface SSBBlobStore : NSObject

/// Shared blob store instance.
+ (instancetype)sharedStore;

/// Returns the local file path for a blob if it exists on disk, otherwise nil.
- (nullable NSString *)localPathForBlobID:(NSString *)blobID;

/// Returns YES if the blob exists locally.
- (BOOL)hasBlob:(NSString *)blobID;

/// Stores blob data locally. Verifies the SHA-256 hash matches the blob ID.
/// Returns the local path on success, nil on hash mismatch.
- (nullable NSString *)storeBlob:(NSData *)data forBlobID:(NSString *)blobID;

/// Adds a blob by calculating its hash and storing it.
/// Returns the blob ID (&...sha256) on success, nil on failure.
- (nullable NSString *)addBlobWithData:(NSData *)data;

/// Fetches a blob from a peer via MuxRPC `blobs.get` and stores it locally.
/// Calls completion on the main queue with the local file path or error.
- (void)fetchBlob:(NSString *)blobID session:(SSBMuxRPCSession *)session completion:(SSBBlobFetchCompletion)completion;

/// Returns the base directory for blob storage.
- (NSString *)blobsDirectory;

/// Total size of all stored blobs in bytes.
- (NSUInteger)totalStorageSize;

/// Removes all stored blobs.
- (void)wipeBlobs;

@end

NS_ASSUME_NONNULL_END
