#import <Foundation/Foundation.h>
#import "SSBFeedStore.h"
#import "SSBMessage.h"
#import "SSBGitObjectStore.h"

NS_ASSUME_NONNULL_BEGIN

@class SSBRoomClient;

typedef void (^SSBGitRepoCompletion)(NSString * _Nullable msgID, NSError * _Nullable error);

/// Manages the state of a git-SSB repository by tracking `git-update` messages.
@interface SSBGitRepo : NSObject

@property (nonatomic, copy, readonly) NSString *repoID; // The message ID of the `git-repo` message
@property (nonatomic, strong, readonly) SSBFeedStore *feedStore;
@property (nonatomic, strong, readonly) SSBGitObjectStore *objectStore;

/// Initializes with the repository's root message ID.
- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore objectStore:(SSBGitObjectStore *)objectStore;

/// Publishes a new git-repo message.
+ (void)publishRepoWithName:(NSString *)name upstream:(nullable NSString *)upstreamID client:(SSBRoomClient *)client completion:(SSBGitRepoCompletion)completion;

/// Publishes a git-update message.
- (void)publishUpdateWithRefs:(NSDictionary<NSString *, id> *)refs
                        packs:(NSArray<NSString *> *)packBlobIDs
                      indexes:(NSArray<NSString *> *)idxBlobIDs
                       client:(SSBRoomClient *)client
                   completion:(SSBGitRepoCompletion)completion;

/// Uploads a local file to the SSB blob store and returns the blob ID.
+ (void)uploadBlobAtURL:(NSURL *)url completion:(void(^)(NSString * _Nullable blobID, NSError * _Nullable error))completion;

/// Reconstructs the current git references by playing history in reverse chronological order.
/// Keys are ref names (e.g. "refs/heads/main"), values are git SHA1 hex strings.
- (NSDictionary<NSString *, NSString *> *)currentRefs;

/// Returns all git-update messages for this repository, sorted by reverse chronological order.
- (NSArray<SSBMessage *> *)updateMessages;

@end

NS_ASSUME_NONNULL_END
