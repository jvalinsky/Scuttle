#import <Cocoa/Cocoa.h>
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays a global feed of git activity (pushes, issues, PRs).
@interface SRGitActivityViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, strong, nullable) SSBRoomClient *currentClient;

- (void)refreshActivity;

@end

NS_ASSUME_NONNULL_END
