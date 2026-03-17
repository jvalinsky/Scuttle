#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * SRSeedRecoveryViewController presents as a sheet over Preferences.
 * The user pastes a metafeed/seed backup message (JSON) that was encrypted
 * to their current identity's metafeed key. On success the recovered seed
 * is stored in the keychain and the metafeed root ID is updated.
 */
@interface SRSeedRecoveryViewController : NSViewController
@end

NS_ASSUME_NONNULL_END
