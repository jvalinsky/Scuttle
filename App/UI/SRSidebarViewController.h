#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SRSidebarViewController;

/// Delegate protocol for sidebar navigation events (destination selection).
@protocol SRSidebarDelegate <NSObject>
/// Called when the user selects a new destination in the sidebar.
- (void)sidebarViewController:(SRSidebarViewController *)sidebar didSelectDestination:(NSString *)identifier;
@end

/// Sidebar view controller: displays app destinations and triggers navigation.
@interface SRSidebarViewController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource>
@property (nonatomic, weak, nullable) id<SRSidebarDelegate> delegate;

/// Programmatically select a sidebar destination.
- (void)selectDestination:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
