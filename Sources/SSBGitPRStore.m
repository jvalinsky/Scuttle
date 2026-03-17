#import "SSBGitPRStore.h"
#import "SSBQueryEngine.h"

@implementation SSBGitPRStore

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _feedStore = feedStore;
    }
    return self;
}

- (NSArray<SSBMessage *> *)pullRequests {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"pull-request" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"repo"], self.repoID ] }
        ]
    };
    return [self.feedStore querySubset:query options:@{@"descending": @YES}];
}

- (NSArray<SSBMessage *> *)commentsForPR:(NSString *)prID {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"post" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"root"], prID ] }
        ]
    };
    // Ascending order for chronological comments
    return [self.feedStore querySubset:query options:@{@"descending": @NO}];
}

@end
