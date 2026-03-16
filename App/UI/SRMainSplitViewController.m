#import "SRMainSplitViewController.h"
#import "SRChannelBrowserViewController.h"
#import "SRPreferencesWindowController.h"
#import "SRErrorBannerView.h"
#import "SRPeerListViewController.h"
#import "SRFeedViewController.h"
#import "SRThreadViewController.h"
#import "SRProfileViewController.h"
#import "SRComposeViewController.h"
#import "SRSidebarViewController.h"
#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBMessageCodec.h"
#import "../../Sources/SSBLogger.h"
#import "../../Sources/SSBKeychain.h"
#import "../Logic/SRNotificationNames.h"
#import <os/log.h>

static os_log_t split_log;

@interface SRMainSplitViewController () <SRPeerListDelegate, SRFeedViewControllerDelegate, SRThreadViewControllerDelegate, SRProfileViewControllerDelegate, SRChannelBrowserDelegate>
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) SRThreadViewController *threadVC;
@property (nonatomic, strong) SRProfileViewController *profileVC;
@property (nonatomic, strong) SRChannelBrowserViewController *channelBrowserVC;
@property (nonatomic, strong) SRErrorBannerView *errorBanner;
@property (nonatomic, strong) SRComposeViewController *composeVC;
@property (nonatomic, strong) NSView *contentAreaContainer; // We'll use this to swap views
@property (nonatomic, strong) SRPeerListViewController *peerListVC;
@property (nonatomic, strong, nullable) RoomConfig *selectedRoom;
- (void)toolbarSettings:(id)sender;

@end

@implementation SRMainSplitViewController

+ (void)initialize {
    if (self == [SRMainSplitViewController class]) {
        split_log = os_log_create("com.scuttlebutt.app", "MainSplitVC");
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sidebarVC = [[SRSidebarViewController alloc] init];
    
    // Main Content Area (Feed + Compose)
    NSViewController *contentContainer = [[NSViewController alloc] init];
    contentContainer.view = [[NSView alloc] init];
    
    self.feedVC = [[SRFeedViewController alloc] init];
    self.feedVC.delegate = self;
    [contentContainer addChildViewController:self.feedVC];
    [contentContainer.view addSubview:self.feedVC.view];
    self.feedVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.contentAreaContainer = contentContainer.view;
    
    self.errorBanner = [[SRErrorBannerView alloc] init];
    self.errorBanner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentAreaContainer addSubview:self.errorBanner];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.errorBanner.leadingAnchor constraintEqualToAnchor:self.contentAreaContainer.leadingAnchor],
        [self.errorBanner.trailingAnchor constraintEqualToAnchor:self.contentAreaContainer.trailingAnchor],
        [self.errorBanner.topAnchor constraintEqualToAnchor:self.contentAreaContainer.safeAreaLayoutGuide.topAnchor constant:8]
    ]];
    
    self.headerView = [[SRProfileHeaderView alloc] init];
    self.headerView.hidesProfileButton = YES;
    [contentContainer.view addSubview:self.headerView];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    __weak typeof(self) weakSelf = self;
    NSData *localSecret = [SSBKeychain loadIdentitySecret];
    NSString *pubkey = [SSBKeychain publicIDFromSecret:localSecret];
    if (pubkey) {
        [self.headerView updateWithIdentity:pubkey name:nil];
        [[SRRoomManager sharedManager] resolveDisplayNameForAuthor:pubkey completion:^(NSString *name) {
            [weakSelf.headerView updateWithIdentity:pubkey name:name];
        }];
    }
    
    self.composeVC = [[SRComposeViewController alloc] init];
    [contentContainer addChildViewController:self.composeVC];
    [contentContainer.view addSubview:self.composeVC.view];
    self.composeVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    
    self.composeVC.onPublish = ^(NSString *text, NSString * _Nullable cw, NSString * _Nullable replyTo) {
        [weakSelf handlePublishWithText:text contentWarning:cw replyTo:replyTo];
    };
    
    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.errorBanner.bottomAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:contentContainer.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:contentContainer.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:60],

        [self.feedVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.feedVC.view.leadingAnchor constraintEqualToAnchor:contentContainer.view.leadingAnchor],
        [self.feedVC.view.trailingAnchor constraintEqualToAnchor:contentContainer.view.trailingAnchor],
        [self.feedVC.view.bottomAnchor constraintEqualToAnchor:self.composeVC.view.topAnchor constant:-12],
        
        [self.composeVC.view.leadingAnchor constraintEqualToAnchor:contentContainer.view.leadingAnchor constant:20],
        [self.composeVC.view.trailingAnchor constraintEqualToAnchor:contentContainer.view.trailingAnchor constant:-20],
        [self.composeVC.view.bottomAnchor constraintEqualToAnchor:contentContainer.view.bottomAnchor constant:-20],
        [self.composeVC.view.heightAnchor constraintEqualToConstant:120]
    ]];
    
    self.peerListVC = [[SRPeerListViewController alloc] init];
    self.peerListVC.delegate = self;
    
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebarVC];
    sidebarItem.minimumThickness = 200;
    sidebarItem.maximumThickness = 300;
    
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:contentContainer];
    contentItem.minimumThickness = 400;
    
    NSSplitViewItem *peerListItem = [NSSplitViewItem splitViewItemWithViewController:self.peerListVC];
    peerListItem.minimumThickness = 250;
    peerListItem.maximumThickness = 400;
    
    [self addSplitViewItem:sidebarItem];
    [self addSplitViewItem:contentItem];
    [self addSplitViewItem:peerListItem];
    
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomSelected:) name:SRRoomManagerRoomSelectedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusDidUpdate:) name:SRRoomManagerConnectionStatusChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(endpointsDidUpdate:) name:SRRoomManagerDidUpdateEndpointsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityDidGenerate:) name:SRLocalIdentityGeneratedNotification object:nil];

    // Pull initial room state now that observers are registered
    NSArray<RoomConfig *> *existingRooms = [SRRoomManager sharedManager].rooms;
    if (existingRooms.count > 0) {
        RoomConfig *first = existingRooms.firstObject;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification
                                                            object:nil
                                                          userInfo:@{SRRoomManagerRoomSelectedKey: first}];
    }
}

- (void)identityDidGenerate:(NSNotification *)notification {
    NSData *localSecret = [SSBKeychain loadIdentitySecret];
    NSString *pubkey = [SSBKeychain publicIDFromSecret:localSecret];
    if (pubkey) {
        [self.headerView updateWithIdentity:pubkey name:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)statusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[@"host"];
    BOOL connected = [userInfo[@"connected"] boolValue];
    
    if (!self.selectedRoom) {
        // If no room is selected, we don't care about connection status for a specific host yet.
        return;
    }

    if (!connected && [host isEqualToString:self.selectedRoom.host]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.errorBanner showMessage:[NSString stringWithFormat:@"Disconnected from %@", host]];
        });
    } else if (connected && [host isEqualToString:self.selectedRoom.host]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.errorBanner hide];
        });
    }
}

- (void)roomSelected:(NSNotification *)notification {
    RoomConfig *room = notification.userInfo[SRRoomManagerRoomSelectedKey];
    self.selectedRoom = room;
    os_log_info(split_log, "Selected room: %{public}@ (name: %{public}@)", room.host, room.name);
    
    [self.headerView updateWithIdentity:room.host name:room.name];
    
    // Start loading indicators
    [self.feedVC.progressIndicator startAnimation:nil];
    [self.peerListVC.progressIndicator startAnimation:nil];
    
    self.feedVC.currentClient = [self currentClient];
    
    [self updatePeerList];
    [self.feedVC refreshFeed];
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    SSBRoomClient *client = notification.object;
    os_log_debug(split_log, "Endpoints notification received from %{public}@ (current selected: %{public}@)", client.host, self.selectedRoom.host);
    if (!self.selectedRoom || [client.host isEqualToString:self.selectedRoom.host]) {
        if (!self.selectedRoom) {
            os_log_debug(split_log, "No room selected, auto-selecting %{public}@", client.host);
            self.selectedRoom = [[SRRoomManager sharedManager].rooms firstObject];
        }
        [self updatePeerList];
    } else {
        os_log_debug(split_log, "Endpoint notification ignored (host mismatch)");
    }
}

- (void)showPreferences {
    [[SRPreferencesWindowController sharedPreferencesWindowController] showWindow:nil];
}

- (void)updatePeerList {
    if (!self.selectedRoom) {
        os_log_debug(split_log, "updatePeerList called but no room selected");
        [self.peerListVC updatePeers:@[]];
        return;
    }
    NSArray *peers = [SRRoomManager sharedManager].roomEndpoints[self.selectedRoom.host];
    os_log_debug(split_log, "updatePeerList for %{public}@ - found %lu peers", self.selectedRoom.host, (unsigned long)peers.count);
    [self.peerListVC updatePeers:peers ?: @[]];
}

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

#pragma mark - SRPeerListDelegate

- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID {
    SSBLogInfo(SSBLogCategoryUI, @"👤 Peer selected: %@", [peerID substringToIndex:MIN(8, peerID.length)]);
    
    if (self.profileVC) {
        SSBLogInfo(SSBLogCategoryUI, @"   Removing existing profile view");
        [self.profileVC.view removeFromSuperview];
        [self.profileVC removeFromParentViewController];
    }
    
    SSBRoomClient *client = [self currentClient];
    SSBLogInfo(SSBLogCategoryUI, @"   Client: %@ connected=%d", client ? @"available" : @"nil", client.isConnected);
    
    self.profileVC = [[SRProfileViewController alloc] initWithPeerID:peerID client:client];
    self.profileVC.delegate = self;
    [self addChildViewController:self.profileVC];
    [self.contentAreaContainer addSubview:self.profileVC.view];
    self.profileVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.profileVC.view.topAnchor constraintEqualToAnchor:self.contentAreaContainer.safeAreaLayoutGuide.topAnchor],
        [self.profileVC.view.leadingAnchor constraintEqualToAnchor:self.contentAreaContainer.leadingAnchor],
        [self.profileVC.view.trailingAnchor constraintEqualToAnchor:self.contentAreaContainer.trailingAnchor],
        [self.profileVC.view.bottomAnchor constraintEqualToAnchor:self.contentAreaContainer.bottomAnchor]
    ]];
    
    self.headerView.hidden = YES;
    self.feedVC.view.hidden = YES;
    self.composeVC.view.hidden = YES;
    if (self.threadVC) self.threadVC.view.hidden = YES;
}

#pragma mark - SRProfileViewControllerDelegate

- (void)profileViewControllerDidRequestBack:(SRProfileViewController *)vc {
    self.headerView.hidden = NO;
    self.feedVC.view.hidden = NO;
    self.composeVC.view.hidden = NO;
    [vc.view removeFromSuperview];
    [vc removeFromParentViewController];
    self.profileVC = nil;
}

#pragma mark - SRChannelBrowserDelegate

- (void)channelBrowser:(SRChannelBrowserViewController *)vc didSelectChannel:(NSString *)channel {
    [self channelBrowserDidRequestBack:vc];
    [self.feedVC loadFeedForChannel:channel];
}

- (void)channelBrowserDidRequestBack:(SRChannelBrowserViewController *)vc {
    self.headerView.hidden = NO;
    self.feedVC.view.hidden = NO;
    self.composeVC.view.hidden = NO;
    [vc.view removeFromSuperview];
    [vc removeFromParentViewController];
    self.channelBrowserVC = nil;
}

- (void)showChannelBrowser {
    if (self.channelBrowserVC) return;
    
    self.channelBrowserVC = [[SRChannelBrowserViewController alloc] init];
    self.channelBrowserVC.delegate = self;
    [self addChildViewController:self.channelBrowserVC];
    [self.contentAreaContainer addSubview:self.channelBrowserVC.view];
    self.channelBrowserVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.channelBrowserVC.view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.channelBrowserVC.view.leadingAnchor constraintEqualToAnchor:self.contentAreaContainer.leadingAnchor],
        [self.channelBrowserVC.view.trailingAnchor constraintEqualToAnchor:self.contentAreaContainer.trailingAnchor],
        [self.channelBrowserVC.view.bottomAnchor constraintEqualToAnchor:self.contentAreaContainer.bottomAnchor]
    ]];
    
    self.headerView.hidden = YES;
    self.feedVC.view.hidden = YES;
    self.composeVC.view.hidden = YES;
}

- (void)peerListViewController:(SRPeerListViewController *)vc didRequestFollow:(NSString *)peerID {
    SSBRoomClient *client = [self currentClient];
    if (client) {
        [client publishContact:peerID following:YES completion:^(NSError *error, id result) {
            if (!error) {
                [self.peerListVC updatePeers:self.peerListVC.peers];
            }
        }];
    }
}

- (void)peerListViewController:(SRPeerListViewController *)vc didRequestUnfollow:(NSString *)peerID {
    SSBRoomClient *client = [self currentClient];
    if (client) {
        [client publishContact:peerID following:NO completion:^(NSError *error, id result) {
            if (!error) {
                [self.peerListVC updatePeers:self.peerListVC.peers];
            }
        }];
    }
}

- (void)peerListViewController:(SRPeerListViewController *)vc didRequestBlock:(NSString *)peerID blocking:(BOOL)blocking {
    SSBRoomClient *client = [self currentClient];
    if (client) {
        [client publishBlock:peerID blocking:blocking completion:^(NSError *error, id result) {
            if (!error) {
                [self.peerListVC updatePeers:self.peerListVC.peers];
            }
        }];
    }
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
    // For now, selecting a thread also acts as 'reply' intent if we don't have a better UI
    [self feedViewController:vc didSelectMessageThread:message];
}

- (void)feedViewController:(SRFeedViewController *)vc didSelectMessageThread:(SSBMessage *)message {
    if (self.threadVC) {
        [self.threadVC.view removeFromSuperview];
        [self.threadVC removeFromParentViewController];
    }
    
    SSBRoomClient *client = [self currentClient];
    self.threadVC = [[SRThreadViewController alloc] initWithRootMessage:message client:client];
    self.threadVC.delegate = self;
    [self addChildViewController:self.threadVC];
    [self.contentAreaContainer addSubview:self.threadVC.view];
    self.threadVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.threadVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.threadVC.view.leadingAnchor constraintEqualToAnchor:self.contentAreaContainer.leadingAnchor],
        [self.threadVC.view.trailingAnchor constraintEqualToAnchor:self.contentAreaContainer.trailingAnchor],
        [self.threadVC.view.bottomAnchor constraintEqualToAnchor:self.contentAreaContainer.bottomAnchor]
    ]];
    
    self.feedVC.view.hidden = YES;
    self.composeVC.view.hidden = YES;
}

#pragma mark - SRThreadViewControllerDelegate

- (void)threadViewControllerDidRequestBack:(SRThreadViewController *)vc {
    self.feedVC.view.hidden = NO;
    self.composeVC.view.hidden = NO;
    [vc.view removeFromSuperview];
    [vc removeFromParentViewController];
    self.threadVC = nil;
}

- (void)threadViewController:(SRThreadViewController *)vc didLikeMessage:(SSBMessage *)message {
    [self feedViewController:self.feedVC didLikeMessage:message];
}

- (void)threadViewController:(SRThreadViewController *)vc didReplyToMessage:(SSBMessage *)message {
    self.composeVC.replyToKey = message.key;
    [self.view.window makeFirstResponder:self.composeVC.view];
    // Maybe also scroll compose view into view if it was hidden?
    // In our case it's always at the bottom of the feed container.
}

#pragma mark - Helpers

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

#pragma mark - NSToolbarDelegate

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:@"Compose"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Compose";
        item.paletteLabel = @"Compose";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.pencil" accessibilityDescription:@"Compose"];
        item.target = self;
        item.action = @selector(toolbarCompose:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"Refresh"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Refresh";
        item.paletteLabel = @"Refresh";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Refresh"];
        item.target = self;
        item.action = @selector(toolbarRefresh:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"ToggleFeed"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        NSSegmentedControl *control = [NSSegmentedControl segmentedControlWithLabels:@[@"Timeline", @"Global"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(toolbarToggleFeed:)];
        control.selectedSegment = (self.feedVC.feedType == SRFeedTypeTimeline) ? 0 : 1;
        item.view = control;
        item.label = @"Feed Type";
        item.paletteLabel = @"Toggle Feed Type";
        return item;
    } else if ([itemIdentifier isEqualToString:@"Search"]) {
    NSSearchToolbarItem *searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        searchItem.label = @"Search";
        searchItem.paletteLabel = @"Search Messages";
        searchItem.searchField.delegate = (id<NSSearchFieldDelegate>)self;
        searchItem.action = @selector(toolbarSearch:);
        searchItem.target = self;
        return searchItem;
    } else if ([itemIdentifier isEqualToString:@"Settings"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Settings";
        item.paletteLabel = @"Settings";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Settings"];
        item.target = self;
        item.action = @selector(toolbarSettings:);
        return item;
    }
    return nil;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"Compose", @"Refresh", @"ToggleFeed", @"Search", @"Settings", NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"Compose", @"Refresh", NSToolbarFlexibleSpaceItemIdentifier, @"Search", @"Settings", @"ToggleFeed"];
}

- (void)toolbarSearch:(id)sender {
    NSString *query = @"";
    if ([sender isKindOfClass:[NSSearchToolbarItem class]]) {
        query = ((NSSearchToolbarItem *)sender).searchField.stringValue;
    }
    
    if (self.threadVC.view.superview) {
        [self threadViewControllerDidRequestBack:self.threadVC];
    }
    if (self.profileVC.view.superview) {
        [self profileViewControllerDidRequestBack:self.profileVC];
    }
    if (self.channelBrowserVC.view.superview) {
        [self channelBrowserDidRequestBack:self.channelBrowserVC];
    }
    
    [self.feedVC loadFeedWithSearch:query];
}

- (void)toolbarCompose:(id)sender {
    if (self.threadVC.view.superview) {
        [self threadViewControllerDidRequestBack:self.threadVC];
    }
    if (self.profileVC.view.superview) {
        [self profileViewControllerDidRequestBack:self.profileVC];
    }
    [self.composeVC.view.window makeFirstResponder:self.composeVC.view];
}

- (void)toolbarRefresh:(id)sender {
    [self.feedVC refreshFeed];
}

- (void)toolbarToggleFeed:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    if (control.selectedSegment == 0) {
        self.feedVC.feedType = SRFeedTypeTimeline;
    } else {
        self.feedVC.feedType = SRFeedTypeGlobal;
    }
    [self.feedVC refreshFeed];
}

@end