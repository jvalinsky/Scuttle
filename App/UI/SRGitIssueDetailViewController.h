#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBGitIssueStore.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays the details and comment thread of a single issue.
@interface SRGitIssueDetailViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, strong) SSBGitIssueStore *issueStore;
@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;
@property (nonatomic, copy, nullable) NSString *currentRootID;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *thread;

- (instancetype)initWithIssueStore:(nullable SSBGitIssueStore *)issueStore;

- (void)loadIssue:(NSString *)issueID;

@end

NS_ASSUME_NONNULL_END
