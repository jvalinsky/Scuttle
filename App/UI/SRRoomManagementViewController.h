#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A dedicated view controller for managing SSB Rooms.
 * Lists joined rooms with status indicators and allows joining via invite code.
 */
@interface SRRoomManagementViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@end

NS_ASSUME_NONNULL_END
