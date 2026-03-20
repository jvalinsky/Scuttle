#import "SRPlatformUI.h"
#import "../../Sources/SSBGitPackDecoder.h"

NS_ASSUME_NONNULL_BEGIN

/// Displays the content of a single git blob (file).
@interface SRGitFileViewController : NSViewController

- (void)loadFileWithSHA1:(NSString *)sha1 name:(NSString *)name objectStore:(id)objectStore;

@end

NS_ASSUME_NONNULL_END
