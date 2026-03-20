#import "SRPlatformUI.h"
#import "../../Sources/SSBGitRepo.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Container view for a single repository, featuring a toolbar for switching
/// between Code, Activity, Commits, Issues, and PRs.
@interface SRGitRepoViewController : NSViewController

@property (nonatomic, strong) SSBGitRepo *repo;
@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;

- (instancetype)initWithRepo:(SSBGitRepo *)repo;

@end

NS_ASSUME_NONNULL_END
