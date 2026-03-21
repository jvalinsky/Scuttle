#import "SSBGitIssueStore.h"

static const NSInteger kDefaultQueryLimit = 500;

@implementation SSBGitIssueStore

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _feedStore = feedStore;
    }
    return self;
}

- (NSArray<SSBMessage *> *)issues {
    NSArray<SSBMessage *> *all = [self.feedStore messagesOfType:@"issue" limit:kDefaultQueryLimit];
    NSMutableArray *result = [NSMutableArray array];
    for (SSBMessage *msg in all) {
        if ([msg.content[@"repo"] isEqualToString:self.repoID]) {
            [result addObject:msg];
        }
    }
    return [result copy];
}

- (NSArray<SSBMessage *> *)editsForIssue:(NSString *)issueID {
    NSArray<SSBMessage *> *all = [self.feedStore messagesOfType:@"issue-edit" limit:kDefaultQueryLimit];
    NSMutableArray *result = [NSMutableArray array];
    for (SSBMessage *msg in all) {
        if ([msg.content[@"root"] isEqualToString:issueID]) {
            [result addObject:msg];
        }
    }
    return [result copy];
}

- (NSArray<SSBMessage *> *)commentsForIssue:(NSString *)issueID {
    NSArray<SSBMessage *> *all = [self.feedStore messagesOfType:@"post" limit:kDefaultQueryLimit];
    NSMutableArray *result = [NSMutableArray array];
    for (SSBMessage *msg in all) {
        if ([msg.content[@"root"] isEqualToString:issueID]) {
            [result addObject:msg];
        }
    }
    return [result copy];
}

@end
