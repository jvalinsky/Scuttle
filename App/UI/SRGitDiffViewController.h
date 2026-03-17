#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBGitRepo.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a diff for a specific commit.
@interface SRGitDiffViewController : NSViewController

- (void)loadDiffForCommit:(NSString *)sha1 repo:(SSBGitRepo *)repo;

@end

NS_ASSUME_NONNULL_END
