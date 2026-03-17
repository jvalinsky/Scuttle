#import "SRGitPRDetailViewController.h"

@implementation SRGitPRDetailViewController

- (instancetype)initWithPRStore:(SSBGitPRStore *)prStore {
    if (self = [super initWithIssueStore:nil]) {
        _prStore = prStore;
    }
    return self;
}

- (void)loadPR:(NSString *)prID {
    self.currentRootID = prID;
    NSMutableArray *thread = [NSMutableArray array];
    NSArray *prs = [self.prStore pullRequests];
    for (SSBMessage *msg in prs) {
        if ([msg.key isEqualToString:prID]) {
            [thread addObject:msg];
            break;
        }
    }
    [thread addObjectsFromArray:[self.prStore commentsForPR:prID]];
    self.thread = thread;
    [self.tableView reloadData];
}

@end
