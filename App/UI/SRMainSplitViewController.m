/*
 SRMainSplitViewController.m

 Modern sidebar-driven rewrite for macOS Scuttlebutt app.
 This version uses a single sidebar for navigation and a content area,
 removing legacy peer list and direct navigation methods.
 It follows modern macOS conventions, with clear separation of navigation
 and content, and toolbar integration.
*/

#import "SRMainSplitViewController.h"
#import "SRContentContainerViewController.h"
#import "SRHomeViewController.h"
#import "SRChannelBrowserViewController.h"
#import "SRSettingsWindowController.h"
#import "SRFeedViewController.h"
#import "SRThreadViewController.h"
#import "SRProfileViewController.h"
#import "SRSidebarViewController.h"
#import "SRPeerListViewController.h"
#import "SRGitActivityViewController.h"
#import "SRGitRepoListViewController.h"
#import "SRGitRepoViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBMessageCodec.h"
#import "../../Sources/SSBLogger.h"
#import "../../Sources/SSBSecretStore.h"
#import "../Logic/SRNotificationNames.h"
#import "SRPlatformLog.h"

static os_log_t split_log;

@interface SRMainSplitViewController () <SRSidebarDelegate, SRFeedViewControllerDelegate, SRThreadViewControllerDelegate, SRProfileViewControllerDelegate, SRChannelBrowserDelegate, SRPeerListDelegate>

/// Sidebar view controller managing the app's navigation.
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;

/// Content container managing the currently displayed content view controller.
@property (nonatomic, strong) SRContentContainerViewController *contentContainer;

/// Home view controller representing the main timeline or feed.
@property (nonatomic, strong) SRHomeViewController *homeVC;

/// Peer list panel (trailing split item, collapsed by default).
@property (nonatomic, strong) SRPeerListViewController *peerListVC;

/// Currently selected room configuration for context.
@property (nonatomic, strong, nullable) RoomConfig *selectedRoom;

@end

@implementation SRMainSplitViewController

+ (void)initialize {
    if (self == [SRMainSplitViewController class]) {
        split_log = os_log_create("com.scuttlebutt.app", "MainSplitVC");
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Initialize and configure sidebar.
    self.sidebarVC = [[SRSidebarViewController alloc] init];
    self.sidebarVC.delegate = self;

    // Initialize the content container that will display child view controllers.
    self.contentContainer = [[SRContentContainerViewController alloc] init];

    // Initialize home view controller (main timeline/feed).
    self.homeVC = [[SRHomeViewController alloc] init];
    self.homeVC.feedVC.delegate = self;

    // Setup compose handler for publishing messages.
    __weak typeof(self) weakSelf = self;
    self.homeVC.composeVC.onPublish = ^(NSString *text, NSString * _Nullable cw, NSString * _Nullable replyTo) {
        [weakSelf handlePublishWithText:text contentWarning:cw replyTo:replyTo];
    };

    // Populate identity header with local identity's public key and name.
    NSData *localSecret = SSBLoadIdentitySecret();
    NSString *pubkey = SSBPublicIDFromSecret(localSecret);
    if (pubkey) {
        [self.homeVC.headerView updateWithIdentity:pubkey name:nil];
        [[SRRoomManager sharedManager] resolveDisplayNameForAuthor:pubkey completion:^(NSString *name) {
            [weakSelf.homeVC.headerView updateWithIdentity:pubkey name:name];
        }];
    }

    // Peer list panel (trailing side, collapsed by default).
    self.peerListVC = [[SRPeerListViewController alloc] init];
    self.peerListVC.delegate = self;

    // Setup three-pane split: Sidebar | Content | PeerList
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebarVC];
    sidebarItem.minimumThickness = 200;
    sidebarItem.maximumThickness = 300;

    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:self.contentContainer];
    contentItem.minimumThickness = 600;

    NSSplitViewItem *peerListItem = [NSSplitViewItem sidebarWithViewController:self.peerListVC];
    peerListItem.minimumThickness = 200;
    peerListItem.maximumThickness = 280;
    peerListItem.collapsed = YES;

    [self addSplitViewItem:sidebarItem];
    [self addSplitViewItem:contentItem];
    [self addSplitViewItem:peerListItem];

    // Set divider style to thin for modern appearance.
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    // Start with home view controller as root content.
    [self.contentContainer setRootViewController:self.homeVC];

    // Listen to room selection changes to update context.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomSelected:) name:SRRoomManagerRoomSelectedNotification object:nil];
    
    // If a room was already selected before view loaded, update state now.
    NSArray<RoomConfig *> *existingRooms = [SRRoomManager sharedManager].rooms;
    if (existingRooms.count > 0) {
        RoomConfig *first = existingRooms.firstObject;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification
                                                            object:nil
                                                          userInfo:@{SRRoomManagerRoomSelectedKey: first}];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notification handlers

/// Update current selected room and update UI accordingly.
- (void)roomSelected:(NSNotification *)notification {
    RoomConfig *room = notification.userInfo[SRRoomManagerRoomSelectedKey];
    self.selectedRoom = room;
    os_log_info(split_log, "Selected room: %{public}@ (name: %{public}@)", room.host, room.name);

    [self.homeVC.headerView updateWithIdentity:room.host name:room.name];
    self.homeVC.composeVC.roomHost = room.host;
    self.homeVC.feedVC.currentClient = [self currentClient];
    [self.homeVC.feedVC refreshFeed];
}

#pragma mark - Navigation

/// Handles sidebar destination selection to update the main content area.
/// @param destination Identifier of the selected sidebar destination.
- (void)selectDestination:(NSString *)destination {
    if ([destination isEqualToString:@"home"]) {
        [self showContentViewController:self.homeVC animated:YES];
    } else if ([destination isEqualToString:@"channels"]) {
        SRChannelBrowserViewController *channelsVC = [[SRChannelBrowserViewController alloc] init];
        channelsVC.delegate = self;
        [self showContentViewController:channelsVC animated:YES];
    } else if ([destination isEqualToString:@"repos"]) {
        SRGitRepoListViewController *reposVC = [[SRGitRepoListViewController alloc] initWithListType:SRGitRepoListTypeMyRepos];
        reposVC.currentClient = [self currentClient];
        [self showContentViewController:reposVC animated:YES];
    } else if ([destination isEqualToString:@"peers"]) {
        self.peerListVC.roomHost = self.selectedRoom.host;
        // Expand the peer list panel if it's collapsed
        NSSplitViewItem *peerItem = self.splitViewItems.lastObject;
        if (peerItem.isCollapsed) {
            peerItem.animator.collapsed = NO;
        }
    } else if ([destination isEqualToString:@"settings"]) {
        [self showPreferences];
    } else {
        // Default fallback to home.
        [self showContentViewController:self.homeVC animated:YES];
    }
}

/// Replaces the content area with the specified view controller.
/// @param vc View controller to display.
/// @param animated Whether to animate the transition.
- (void)showContentViewController:(NSViewController *)vc animated:(BOOL)animated {
    if ([self.contentContainer.topViewController isEqual:vc]) {
        return;
    }
    if (animated) {
        [self.contentContainer transitionToViewController:vc];
    } else {
        [self.contentContainer setRootViewController:vc];
    }
}

#pragma mark - Public methods

/// Shows the Preferences window.
- (void)showPreferences {
    [[SRSettingsWindowController sharedSettingsWindowController] showSettings];
}

#pragma mark - Helpers

/// Returns the current active room client, falling back to first available.
/// @return The current SSBRoomClient or nil if none available.
- (nullable SSBRoomClient *)currentClient {
    SSBRoomClient *client = nil;
    if (self.selectedRoom) {
        client = [[SRRoomManager sharedManager] clientForHost:self.selectedRoom.host];
    }
    if (!client) {
        client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    }
    return client;
}

/// Handles publishing text content, either as a new post or a reply.
/// @param text Text to publish.
/// @param cw Optional content warning.
/// @param replyTo Optional message key to reply to.
- (void)handlePublishWithText:(NSString *)text contentWarning:(NSString *)cw replyTo:(nullable NSString *)replyTo {
    SSBRoomClient *client = [self currentClient];
    if (!client) return;

    NSDictionary *content;
    if (replyTo) {
        content = [SSBMessageCodec replyContentWithText:text root:replyTo branch:replyTo channel:nil contentWarning:cw mentions:nil recps:nil];
    } else {
        content = [SSBMessageCodec rootPostContentWithText:text channel:nil contentWarning:cw mentions:nil recps:nil];
    }

    NSError *error = nil;
    SSBMessage *msg = [client publishLocalMessageWithContent:content error:&error];
    if (msg) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SRNewMessageNotification object:nil];
    }
}

#pragma mark - SRSidebarDelegate

- (void)sidebarViewController:(SRSidebarViewController *)sidebar didSelectDestination:(NSString *)identifier {
    [self selectDestination:identifier];
}

#pragma mark - SRFeedViewControllerDelegate

- (void)feedViewController:(SRFeedViewController *)vc didLikeMessage:(SSBMessage *)message {
    SSBRoomClient *client = [self currentClient];
    if (client) {
        NSDictionary *content = [SSBMessageCodec likeVoteForMessage:message.key];
        [client publishLocalMessageWithContent:content error:nil];
    }
}

- (void)feedViewController:(SRFeedViewController *)vc didReplyToMessage:(SSBMessage *)message {
    [self feedViewController:vc didSelectMessageThread:message];
}

- (void)feedViewController:(SRFeedViewController *)vc didSelectMessageThread:(SSBMessage *)message {
    SSBRoomClient *client = [self currentClient];
    SRThreadViewController *threadVC = [[SRThreadViewController alloc] initWithRootMessage:message client:client];
    threadVC.delegate = self;
    [self showContentViewController:threadVC animated:YES];
}

#pragma mark - SRThreadViewControllerDelegate

- (void)threadViewControllerDidRequestBack:(SRThreadViewController *)vc {
    [self showContentViewController:self.homeVC animated:YES];
}

- (void)threadViewController:(SRThreadViewController *)vc didLikeMessage:(SSBMessage *)message {
    [self feedViewController:self.homeVC.feedVC didLikeMessage:message];
}

- (void)threadViewController:(SRThreadViewController *)vc didReplyToMessage:(SSBMessage *)message {
    [self showContentViewController:self.homeVC animated:YES];
    self.homeVC.composeVC.replyToKey = message.key;
    [self.homeVC.composeVC.view.window makeFirstResponder:self.homeVC.composeVC.view];
}

#pragma mark - SRProfileViewControllerDelegate

- (void)profileViewControllerDidRequestBack:(SRProfileViewController *)vc {
    [self showContentViewController:self.homeVC animated:YES];
}

#pragma mark - SRChannelBrowserDelegate

- (void)channelBrowser:(SRChannelBrowserViewController *)vc didSelectChannel:(NSString *)channel {
    [self showContentViewController:self.homeVC animated:YES];
    [self.homeVC.feedVC loadFeedForChannel:channel];
}

- (void)channelBrowserDidRequestBack:(SRChannelBrowserViewController *)vc {
    [self showContentViewController:self.homeVC animated:YES];
}

#pragma mark - SRPeerListDelegate

- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID {
    SRProfileViewController *profileVC = [[SRProfileViewController alloc] initWithPeerID:peerID client:[self currentClient]];
    profileVC.delegate = self;
    [self showContentViewController:profileVC animated:YES];
}

#pragma mark - NSToolbarDelegate

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:@"Compose"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Compose";
        item.paletteLabel = @"Compose";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.pencil" accessibilityDescription:@"Compose"];
        item.target = self;
        item.action = @selector(toolbarCompose:);
        item.bordered = YES;
        return item;
    } else if ([itemIdentifier isEqualToString:@"Refresh"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Refresh";
        item.paletteLabel = @"Refresh";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Refresh"];
        item.target = self;
        item.action = @selector(toolbarRefresh:);
        item.bordered = YES;
        return item;
    } else if ([itemIdentifier isEqualToString:@"ToggleFeed"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        NSSegmentedControl *control = [NSSegmentedControl segmentedControlWithLabels:@[@"Timeline", @"Global"]
                                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                              target:self
                                                                              action:@selector(toolbarToggleFeed:)];
        control.selectedSegment = (self.homeVC.feedVC.feedType == SRFeedTypeTimeline) ? 0 : 1;
        item.view = control;
        item.label = @"Feed Type";
        item.paletteLabel = @"Toggle Feed Type";
        item.bordered = YES;
        return item;
    } else if ([itemIdentifier isEqualToString:@"Search"]) {
        NSSearchToolbarItem *searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        searchItem.label = @"Search";
        searchItem.paletteLabel = @"Search Messages";
        searchItem.searchField.delegate = (id<NSSearchFieldDelegate>)self;
        searchItem.action = @selector(toolbarSearch:);
        searchItem.target = self;
        searchItem.bordered = YES;
        return searchItem;
    } else if ([itemIdentifier isEqualToString:@"Settings"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Settings";
        item.paletteLabel = @"Settings";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Settings"];
        item.target = self;
        item.action = @selector(toolbarSettings:);
        item.bordered = YES;
        return item;
    }
    return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarToggleSidebarItemIdentifier,
             NSToolbarSidebarTrackingSeparatorItemIdentifier,
             @"Compose", @"Refresh", @"ToggleFeed", @"Search", @"Settings",
             NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarToggleSidebarItemIdentifier,
             NSToolbarSidebarTrackingSeparatorItemIdentifier,
             @"Compose", @"Refresh", NSToolbarFlexibleSpaceItemIdentifier, @"Search", @"ToggleFeed", @"Settings"];
}

- (void)toolbarCompose:(id)sender {
    if (self.contentContainer.topViewController != self.homeVC) {
        [self showContentViewController:self.homeVC animated:YES];
    }
    [self.homeVC.composeVC.view.window makeFirstResponder:self.homeVC.composeVC.view];
}

- (void)toolbarRefresh:(id)sender {
    [self.homeVC.feedVC refreshFeed];
}

- (void)toolbarSearch:(id)sender {
    NSString *query = @"";
    if ([sender isKindOfClass:[NSSearchToolbarItem class]]) {
        query = ((NSSearchToolbarItem *)sender).searchField.stringValue;
    }
    if (self.contentContainer.topViewController != self.homeVC) {
        [self showContentViewController:self.homeVC animated:YES];
    }
    [self.homeVC.feedVC loadFeedWithSearch:query];
}

- (void)toolbarToggleFeed:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    self.homeVC.feedVC.feedType = (control.selectedSegment == 0) ? SRFeedTypeTimeline : SRFeedTypeGlobal;
    [self.homeVC.feedVC refreshFeed];
}

- (void)toolbarSettings:(id)sender {
    [self showPreferences];
}

#pragma mark - Menu Actions

- (void)navigateHome:(id)sender {
    [self.sidebarVC selectDestination:@"home"];
}

- (void)navigateChannels:(id)sender {
    [self.sidebarVC selectDestination:@"channels"];
}

- (void)navigateRepos:(id)sender {
    [self.sidebarVC selectDestination:@"repos"];
}

- (void)togglePeerList:(id)sender {
    // Legacy action, no-op in modern UI or toggle sidebar
    [self toggleSidebar:sender];
}

- (void)showKeyboardShortcuts:(id)sender {
    // Placeholder for modern shortcuts view
}

@end
