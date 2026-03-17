#import <Foundation/Foundation.h>
#import "SSBFeedStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Queries the SSB feed store for issues, issue edits, and posts (comments) related to a specific git repository.
@interface SSBGitIssueStore : NSObject

@property (nonatomic, copy, readonly) NSString *repoID;
@property (nonatomic, strong, readonly) SSBFeedStore *feedStore;

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore;

/// Returns all 'issue' messages for this repository.
- (NSArray<SSBMessage *> *)issues;

/// Returns all 'issue-edit' messages for a specific issue ID.
- (NSArray<SSBMessage *> *)editsForIssue:(NSString *)issueID;

/// Returns all 'post' messages (comments) for a specific issue ID.
- (NSArray<SSBMessage *> *)commentsForIssue:(NSString *)issueID;

@end

NS_ASSUME_NONNULL_END
