#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBGitPRStore.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a list of pull requests for a repository.
@interface SRGitPRListViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, strong) SSBGitPRStore *prStore;
@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;

- (instancetype)initWithPRStore:(SSBGitPRStore *)prStore;

@end

NS_ASSUME_NONNULL_END
