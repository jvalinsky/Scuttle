#import "SRPlatformUI.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * SRSeedBackupViewController presents as a sheet over Preferences.
 * It encrypts the local metafeed seed to a trusted contact's public key
 * and publishes the result as a metafeed/seed message on the classic feed.
 */
@interface SRSeedBackupViewController : NSViewController
@end

NS_ASSUME_NONNULL_END
