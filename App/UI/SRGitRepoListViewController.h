#import "SRPlatformUI.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRGitRepoListType) {
    SRGitRepoListTypeMyRepos,
    SRGitRepoListTypeFollowing
};

/// Displays a list of repositories (either owned by the user or followed).
@interface SRGitRepoListViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, assign) SRGitRepoListType listType;
@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;

- (instancetype)initWithListType:(SRGitRepoListType)listType;

- (void)refreshRepos;

@end

NS_ASSUME_NONNULL_END
