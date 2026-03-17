#import "SRGitIssueDetailViewController.h"
#import "../../Sources/SSBGitPRStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays the details and comment thread of a single pull request.
@interface SRGitPRDetailViewController : SRGitIssueDetailViewController

@property (nonatomic, strong) SSBGitPRStore *prStore;

- (instancetype)initWithPRStore:(SSBGitPRStore *)prStore;

- (void)loadPR:(NSString *)prID;

@end

NS_ASSUME_NONNULL_END
