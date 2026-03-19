#import "SRMainSplitViewController.h"
#import "SRContentContainerViewController.h"
#import "SRHomeViewController.h"
#import "SRChannelBrowserViewController.h"
#import "SRPreferencesWindowController.h"
#import "SRPeerListViewController.h"
#import "SRFeedViewController.h"
#import "SRThreadViewController.h"
#import "SRProfileViewController.h"
#import "SRSidebarViewController.h"
#import "SRGitActivityViewController.h"
#import "SRGitRepoListViewController.h"
#import "SRGitRepoViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBMessageCodec.h"
#import "../../Sources/SSBLogger.h"
#import "../../Sources/SSBKeychain.h"
#import "../Logic/SRNotificationNames.h"
#import <os/log.h>

static os_log_t split_log;
static NSString * const kSRPeerDiscoveryLogPath = @"/tmp/scuttle_peer_discovery.log";

static void SRPeerDiscoveryAppend(NSString *line) {
    if (line.length == 0) return;
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.scuttlebutt.room.peerdiag.mainsplit", DISPATCH_QUEUE_SERIAL);
    });
    NSString *full = [NSString stringWithFormat:@"[%@] mainsplit %@\n", [NSDate date], line];
    NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(q, ^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:kSRPeerDiscoveryLogPath]) {
                [fm createFileAtPath:kSRPeerDiscoveryLogPath contents:nil attributes:nil];
            }
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kSRPeerDiscoveryLogPath];
            if (!h) return;
            @try {
                [h seekToEndOfFile];
                [h writeData:data];
            } @catch (__unused NSException *exception) {
            } @finally {
                [h closeFile];
            }
        }
    });
}

@interface SRMainSplitViewController () <SRPeerListDelegate, SRFeedViewControllerDelegate, SRThreadViewControllerDelegate, SRProfileViewControllerDelegate, SRChannelBrowserDelegate>
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;
@property (nonatomic, strong) SRHomeViewController *homeVC;
@property (nonatomic, strong) SRContentContainerViewController *contentContainer;
@property (nonatomic, strong) SRPeerListViewController *peerListVC;
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

    self.sidebarVC = [[SRSidebarViewController alloc] init];

    // Content area: a container that manages push/pop navigation between the
    // home view and any detail view (profile, thread, channel browser).
    self.contentContainer = [[SRContentContainerViewController alloc] init];

    self.homeVC = [[SRHomeViewController alloc] init];
    // Accessing .view triggers viewDidLoad on homeVC, instantiating its children.
    [self.contentContainer setRootViewController:self.homeVC];

    // Wire delegates now that homeVC's children exist.
    self.homeVC.feedVC.delegate = self;

    __weak typeof(self) weakSelf = self;
    self.homeVC.composeVC.onPublish = ^(NSString *text, NSString * _Nullable cw, NSString * _Nullable replyTo) {
        [weakSelf handlePublishWithText:text contentWarning:cw replyTo:replyTo];
    };

    // Populate identity header.
    NSData *localSecret = [SSBKeychain loadIdentitySecret];
    NSString *pubkey = [SSBKeychain publicIDFromSecret:localSecret];
    if (pubkey) {
        [self.homeVC.headerView updateWithIdentity:pubkey name:nil];
        [[SRRoomManager sharedManager] resolveDisplayNameForAuthor:pubkey completion:^(NSString *name) {
            [weakSelf.homeVC.headerView updateWithIdentity:pubkey name:name];
        }];
    }

    self.peerListVC = [[SRPeerListViewController alloc] init];
    self.peerListVC.delegate = self;

    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebarVC];
    sidebarItem.minimumThickness = 200;
    sidebarItem.maximumThickness = 300;

    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:self.contentContainer];
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repoSelected:) name:SRGitRepoSelectedNotification object:nil];

    // Replay any room that was selected before we registered observers.
    NSArray<RoomConfig *> *existingRooms = [SRRoomManager sharedManager].rooms;
    if (existingRooms.count > 0) {
        RoomConfig *first = existingRooms.firstObject;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification
                                                            object:nil
                                                          userInfo:@{SRRoomManagerRoomSelectedKey: first}];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notification handlers

- (void)identityDidGenerate:(NSNotification *)notification {
    NSData *localSecret = [SSBKeychain loadIdentitySecret];
    NSString *pubkey = [SSBKeychain publicIDFromSecret:localSecret];
    if (pubkey) {
        [self.homeVC.headerView updateWithIdentity:pubkey name:nil];
    }
}

- (void)repoSelected:(NSNotification *)notification {
    NSString *repoID = notification.userInfo[SRGitRepoSelectedKey];
    if (!repoID) return;
    
    SSBGitObjectStore *objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:[SSBBlobStore sharedStore]];
    SSBGitRepo *repo = [[SSBGitRepo alloc] initWithRepoID:repoID feedStore:[SSBFeedStore sharedStore] objectStore:objectStore];
    
    SRGitRepoViewController *repoVC = [[SRGitRepoViewController alloc] initWithRepo:repo];
    repoVC.currentClient = [self currentClient];
    [self.contentContainer pushViewController:repoVC];
}

- (void)statusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[@"host"];
    BOOL connected = [userInfo[@"connected"] boolValue];

    if (!self.selectedRoom) return;

    if (!connected && [host isEqualToString:self.selectedRoom.host]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.homeVC.errorBanner showMessage:[NSString stringWithFormat:@"Disconnected from %@", host]];
        });
    } else if (connected && [host isEqualToString:self.selectedRoom.host]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.homeVC.errorBanner hide];
        });
    }
}

- (void)roomSelected:(NSNotification *)notification {
    RoomConfig *room = notification.userInfo[SRRoomManagerRoomSelectedKey];
    self.selectedRoom = room;
    os_log_info(split_log, "Selected room: %{public}@ (name: %{public}@)", room.host, room.name);
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"room selected host=%@ name=%@",
                           room.host ?: @"<unknown>",
                           room.name ?: @"<none>"]);

    [self.homeVC.headerView updateWithIdentity:room.host name:room.name];

    [self.homeVC.feedVC.progressIndicator startAnimation:nil];
    [self.peerListVC.progressIndicator startAnimation:nil];

    self.homeVC.feedVC.currentClient = [self currentClient];

    [self updatePeerList];
    [self.homeVC.feedVC refreshFeed];
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    SSBRoomClient *client = notification.object;
    NSString *host = notification.userInfo[SRRoomManagerEndpointsHostKey];
    if (host.length == 0) {
        host = client.host;
    }

    NSArray<NSString *> *peers = notification.userInfo[SRRoomManagerEndpointsListKey];
    if (![peers isKindOfClass:[NSArray class]]) {
        peers = [SRRoomManager sharedManager].roomEndpoints[host];
    }
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"endpointsDidUpdate host=%@ selected=%@ peers=%lu",
                           host ?: @"<unknown>",
                           self.selectedRoom.host ?: @"<none>",
                           (unsigned long)peers.count]);

    os_log_debug(split_log,
                 "Endpoints notification host=%{public}@ selected=%{public}@ peers=%lu",
                 host, self.selectedRoom.host, (unsigned long)peers.count);

    if (!self.selectedRoom || [host isEqualToString:self.selectedRoom.host]) {
        if (!self.selectedRoom) {
            for (RoomConfig *candidate in [SRRoomManager sharedManager].rooms) {
                if ([candidate.host isEqualToString:host]) {
                    self.selectedRoom = candidate;
                    break;
                }
            }
            if (!self.selectedRoom) {
                self.selectedRoom = [[SRRoomManager sharedManager].rooms firstObject];
            }
            os_log_debug(split_log, "No room selected, auto-selected %{public}@", self.selectedRoom.host);
        }
        if (peers) {
            SRPeerDiscoveryAppend([NSString stringWithFormat:@"peerListVC updatePeers host=%@ peers=%lu",
                                   host ?: @"<unknown>",
                                   (unsigned long)peers.count]);
            [self.peerListVC updatePeers:peers];
        } else {
            os_log_debug(split_log, "No endpoints payload for %{public}@; falling back to cached lookup", host);
            SRPeerDiscoveryAppend([NSString stringWithFormat:@"no payload for host=%@, fallback to cached lookup", host ?: @"<unknown>"]);
            [self updatePeerList];
        }
    } else {
        os_log_debug(split_log, "Endpoint notification ignored (host mismatch for %{public}@)", host);
        SRPeerDiscoveryAppend([NSString stringWithFormat:@"endpoint notification ignored host=%@ selected=%@",
                               host ?: @"<unknown>",
                               self.selectedRoom.host ?: @"<none>"]);
    }
}

#pragma mark - Public

- (void)showPreferences {
    [[SRPreferencesWindowController sharedPreferencesWindowController] showWindow:nil];
}

- (void)showChannelBrowser {
    if ([self.contentContainer.topViewController isKindOfClass:[SRChannelBrowserViewController class]]) return;
    SRChannelBrowserViewController *channelVC = [[SRChannelBrowserViewController alloc] init];
    channelVC.delegate = self;
    [self.contentContainer pushViewController:channelVC];
}

- (void)showGitActivity {
    if ([self.contentContainer.topViewController isKindOfClass:[SRGitActivityViewController class]]) return;
    SRGitActivityViewController *gitVC = [[SRGitActivityViewController alloc] init];
    gitVC.currentClient = [self currentClient];
    [self.contentContainer pushViewController:gitVC];
}

- (void)showGitMyRepos {
    if ([self.contentContainer.topViewController isKindOfClass:[SRGitRepoListViewController class]]) {
        SRGitRepoListViewController *vc = (SRGitRepoListViewController *)self.contentContainer.topViewController;
        if (vc.listType == SRGitRepoListTypeMyRepos) return;
    }
    SRGitRepoListViewController *gitVC = [[SRGitRepoListViewController alloc] initWithListType:SRGitRepoListTypeMyRepos];
    gitVC.currentClient = [self currentClient];
    [self.contentContainer pushViewController:gitVC];
}

- (void)showGitFollowing {
    if ([self.contentContainer.topViewController isKindOfClass:[SRGitRepoListViewController class]]) {
        SRGitRepoListViewController *vc = (SRGitRepoListViewController *)self.contentContainer.topViewController;
        if (vc.listType == SRGitRepoListTypeFollowing) return;
    }
    SRGitRepoListViewController *gitVC = [[SRGitRepoListViewController alloc] initWithListType:SRGitRepoListTypeFollowing];
    gitVC.currentClient = [self currentClient];
    [self.contentContainer pushViewController:gitVC];
}

#pragma mark - Helpers

- (void)updatePeerList {
    if (!self.selectedRoom) {
        os_log_debug(split_log, "updatePeerList called but no room selected");
        SRPeerDiscoveryAppend(@"updatePeerList no selected room");
        [self.peerListVC updatePeers:@[]];
        return;
    }
    NSArray *peers = [SRRoomManager sharedManager].roomEndpoints[self.selectedRoom.host];
    os_log_debug(split_log, "updatePeerList for %{public}@ - found %lu peers", self.selectedRoom.host, (unsigned long)peers.count);
    SRPeerDiscoveryAppend([NSString stringWithFormat:@"updatePeerList host=%@ peers=%lu",
                           self.selectedRoom.host ?: @"<unknown>",
                           (unsigned long)peers.count]);
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

#pragma mark - SRPeerListDelegate

- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID {
    SSBLogInfo(SSBLogCategoryUI, @"👤 Peer selected: %@", [peerID substringToIndex:MIN(8, peerID.length)]);
    SSBRoomClient *client = [self currentClient];
    SSBLogInfo(SSBLogCategoryUI, @"   Client: %@ connected=%d", client ? @"available" : @"nil", client.isConnected);

    SRProfileViewController *profileVC = [[SRProfileViewController alloc] initWithPeerID:peerID client:client];
    profileVC.delegate = self;
    [self.contentContainer pushViewController:profileVC];
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

#pragma mark - SRProfileViewControllerDelegate

- (void)profileViewControllerDidRequestBack:(SRProfileViewController *)vc {
    [self.contentContainer popViewController];
}

#pragma mark - SRChannelBrowserDelegate

- (void)channelBrowser:(SRChannelBrowserViewController *)vc didSelectChannel:(NSString *)channel {
    [self.contentContainer popViewController];
    [self.homeVC.feedVC loadFeedForChannel:channel];
}

- (void)channelBrowserDidRequestBack:(SRChannelBrowserViewController *)vc {
    [self.contentContainer popViewController];
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
    [self.contentContainer pushViewController:threadVC];
}

#pragma mark - SRThreadViewControllerDelegate

- (void)threadViewControllerDidRequestBack:(SRThreadViewController *)vc {
    [self.contentContainer popViewController];
}

- (void)threadViewController:(SRThreadViewController *)vc didLikeMessage:(SSBMessage *)message {
    [self feedViewController:self.homeVC.feedVC didLikeMessage:message];
}

- (void)threadViewController:(SRThreadViewController *)vc didReplyToMessage:(SSBMessage *)message {
    [self.contentContainer popViewController];
    self.homeVC.composeVC.replyToKey = message.key;
    [self.homeVC.composeVC.view.window makeFirstResponder:self.homeVC.composeVC.view];
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
        NSSegmentedControl *control = [NSSegmentedControl segmentedControlWithLabels:@[@"Timeline", @"Global"]
                                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                              target:self
                                                                              action:@selector(toolbarToggleFeed:)];
        control.selectedSegment = (self.homeVC.feedVC.feedType == SRFeedTypeTimeline) ? 0 : 1;
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

- (void)toolbarCompose:(id)sender {
    if (self.contentContainer.topViewController != self.homeVC) {
        [self.contentContainer popViewController];
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
        [self.contentContainer popViewController];
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

@end
