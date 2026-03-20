#import "SRPlatformUI.h"
#import "../../Sources/SSBRoomClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRGitNewIssueViewController : NSViewController

@property (nonatomic, copy) NSString *repoID;
@property (nonatomic, strong) SSBRoomClient *currentClient;

- (instancetype)initWithRepoID:(NSString *)repoID client:(SSBRoomClient *)client;

@end

NS_ASSUME_NONNULL_END
