#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBGitIssueStore.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a list of issues for a repository.
@interface SRGitIssueListViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, strong) SSBGitIssueStore *issueStore;
@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;

- (instancetype)initWithIssueStore:(SSBGitIssueStore *)issueStore;

@end

NS_ASSUME_NONNULL_END
