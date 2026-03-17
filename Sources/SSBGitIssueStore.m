#import "SSBGitIssueStore.h"
#import "SSBQueryEngine.h"

@implementation SSBGitIssueStore

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _feedStore = feedStore;
    }
    return self;
}

- (NSArray<SSBMessage *> *)issues {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"issue" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"repo"], self.repoID ] }
        ]
    };
    return [self.feedStore querySubset:query options:@{@"descending": @YES}];
}

- (NSArray<SSBMessage *> *)editsForIssue:(NSString *)issueID {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"issue-edit" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"root"], issueID ] }
        ]
    };
    // Ascending order for edits to replay state
    return [self.feedStore querySubset:query options:@{@"descending": @NO}];
}

- (NSArray<SSBMessage *> *)commentsForIssue:(NSString *)issueID {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"post" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"root"], issueID ] }
        ]
    };
    // Ascending order for chronological comments
    return [self.feedStore querySubset:query options:@{@"descending": @NO}];
}

@end
