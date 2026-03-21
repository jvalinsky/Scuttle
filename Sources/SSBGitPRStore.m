#import "SSBGitPRStore.h"

static const NSInteger kDefaultQueryLimit = 500;

@implementation SSBGitPRStore

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _feedStore = feedStore;
    }
    return self;
}

- (NSArray<SSBMessage *> *)pullRequests {
    NSArray<SSBMessage *> *all = [self.feedStore messagesOfType:@"pull-request" limit:kDefaultQueryLimit];
    NSMutableArray *result = [NSMutableArray array];
    for (SSBMessage *msg in all) {
        if ([msg.content[@"repo"] isEqualToString:self.repoID]) {
            [result addObject:msg];
        }
    }
    return [result copy];
}

- (NSArray<SSBMessage *> *)commentsForPR:(NSString *)prID {
    NSArray<SSBMessage *> *all = [self.feedStore messagesOfType:@"post" limit:kDefaultQueryLimit];
    NSMutableArray *result = [NSMutableArray array];
    for (SSBMessage *msg in all) {
        if ([msg.content[@"root"] isEqualToString:prID]) {
            [result addObject:msg];
        }
    }
    return [result copy];
}

@end
