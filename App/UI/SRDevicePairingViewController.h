#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Sheet that shows a list of registered devices and allows the user to deregister them.
/// Also provides a "Pair New Device" flow that encrypts the metafeed seed using
/// SIP-004 so a second device can derive the full metafeed tree.
@interface SRDevicePairingViewController : NSViewController
@end

NS_ASSUME_NONNULL_END
