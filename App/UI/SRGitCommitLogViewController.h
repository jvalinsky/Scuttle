#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBGitRepo.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a chronological list of commits for a repository.
@interface SRGitCommitLogViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, strong) SSBGitRepo *repo;

- (instancetype)initWithRepo:(SSBGitRepo *)repo;

@end

NS_ASSUME_NONNULL_END
