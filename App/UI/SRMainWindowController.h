#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Controller for the main content window of ScuttleRoom.
 * It hosts the SRMainSplitViewController and manages window-specific configs.
 */
@interface SRMainWindowController : NSWindowController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
