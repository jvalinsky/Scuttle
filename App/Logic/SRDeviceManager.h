#import <Foundation/Foundation.h>
#import "../../Sources/SSBMetafeed.h"

NS_ASSUME_NONNULL_BEGIN

/// Manages per-device sub-feeds under the local root metafeed.
/// Each device derives a unique Buttwoo sub-feed keyed by device name + UUID.
/// The resulting sub-feed IDs are recorded as add/derived metafeed messages so
/// peers can discover all devices under a single metafeed identity.
@interface SRDeviceManager : NSObject

+ (instancetype)sharedManager;

/// Derives and publishes an add/derived metafeed message for this device if one
/// does not already exist. Called once at startup after metafeed bootstrap.
- (void)registerThisDeviceIfNeeded;

/// Returns the sub-feed IDs of all known registered devices by scanning stored
/// add/derived metafeed messages for the local root metafeed.
- (NSArray<NSString *> *)registeredDeviceFeedIDs;

/// Tombstones the given device feed so peers stop replicating it.
- (void)deregisterDeviceWithFeedID:(NSString *)feedID;

@end

NS_ASSUME_NONNULL_END
