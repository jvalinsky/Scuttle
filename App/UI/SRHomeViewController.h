#import "SRPlatformUI.h"
#import "SRFeedViewController.h"
#import "SRComposeViewController.h"
#import "SRProfileHeaderView.h"
#import "SRErrorBannerView.h"

NS_ASSUME_NONNULL_BEGIN

/// Contains the persistent "home" layout: header → feed → compose, with an
/// error banner overlay. Extracted from SRMainSplitViewController so the
/// content container can push/pop this as a unit.
@interface SRHomeViewController : NSViewController

@property (nonatomic, strong, readonly) SRFeedViewController *feedVC;
@property (nonatomic, strong, readonly) SRComposeViewController *composeVC;
@property (nonatomic, strong, readonly) SRProfileHeaderView *headerView;
@property (nonatomic, strong, readonly) SRErrorBannerView *errorBanner;

@end

NS_ASSUME_NONNULL_END
