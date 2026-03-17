#import <Foundation/Foundation.h>
#import "SSBMessage.h"
#import "SSBFeedStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Queries the SSB feed store for pull requests and posts (comments) related to a specific git repository.
@interface SSBGitPRStore : NSObject

@property (nonatomic, copy, readonly) NSString *repoID;
@property (nonatomic, strong, readonly) SSBFeedStore *feedStore;

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore;

/// Returns all 'pull-request' messages for this repository.
- (NSArray<SSBMessage *> *)pullRequests;

/// Returns all 'post' messages (comments) for a specific pull request ID.
- (NSArray<SSBMessage *> *)commentsForPR:(NSString *)prID;

@end

NS_ASSUME_NONNULL_END
