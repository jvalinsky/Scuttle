#import <Cocoa/Cocoa.h>
#import "SRWorkspaceTypes.h"

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

@property (nonatomic, assign) SRWorkspaceContext activeContext;
@property (nonatomic, assign) BOOL hideProfileHeader;

@property (nonatomic, strong) NSArray *gitRepos;
@property (nonatomic, strong) NSArray *rooms;

/// Programmatically select a sidebar destination.
- (void)selectDestination:(NSString *)identifier;

/// Rebuild sections based on activeContext
- (void)reloadContents;

/// Update sync status display for a room
- (void)updateSyncStatus:(nullable NSString *)status progress:(float)progress;

@end

NS_ASSUME_NONNULL_END
