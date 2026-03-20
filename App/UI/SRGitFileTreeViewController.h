#import "SRPlatformUI.h"
#import "../../Sources/SSBGitRepo.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a git file tree for a repository and handles branch/tag switching.
@interface SRGitFileTreeViewController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource>

@property (nonatomic, strong, readonly) SSBGitRepo *repo;
@property (nonatomic, copy, nullable) NSString *currentBranch;

- (instancetype)initWithRepo:(SSBGitRepo *)repo;

@end

NS_ASSUME_NONNULL_END
