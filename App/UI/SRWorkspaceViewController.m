#import "SRWorkspaceViewController.h"
#import "SRStripViewController.h"
#import "SRSidebarViewController.h"
#import "SRFeedViewController.h"
#import "SRChannelBrowserViewController.h"
#import "SRGitRepoListViewController.h"
#import "SRPeerListViewController.h"
#import "SRComposeViewController.h"
#import "SRErrorBannerView.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "../../Sources/RoomInviteHandler.h"
#import "TEA/SRStore.h"
#import "TEA/SRAppModel.h"

@interface SRWorkspaceViewController () <SRStripDelegate, SRSidebarDelegate>
@property (nonatomic, strong) SRStore *store;
@property (nonatomic, assign) SRDestination currentDestination;

@property (nonatomic, strong) SRStripViewController *stripVC;
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;
@property (nonatomic, strong) NSViewController *currentCanvasVC;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) SRPeerListViewController *peerListVC;
@property (nonatomic, strong) SRComposeViewController *composeVC;
@property (nonatomic, strong) SRErrorBannerView *errorBanner;
@property (nonatomic, strong) RoomConfig *selectedRoom;

@property (nonatomic, strong) NSView *nexusStripView;
@property (nonatomic, strong) NSView *inspectorView;
@property (nonatomic, strong) NSView *canvasView;

@property (nonatomic, strong) NSLayoutConstraint *inspectorWidthConstraint;
@end

@implementation SRWorkspaceViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 600)];
    self.view.wantsLayer = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Initialize TEA Store
    self.store = [[SRStore alloc] init];
    self.currentDestination = -1; // Force first render swap
    
    [self setupLayout];
    [self setupErrorBanner];
    
    // Subscribe to State Updates
    __weak typeof(self) weakSelf = self;
    [self.store subscribe:^(SRAppModel *model) {
        [weakSelf render:model];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomSelected:) name:SRRoomManagerRoomSelectedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomsDidUpdate:) name:SRRoomManagerDidUpdateRoomsNotification object:nil];

    // Start the store (subscribes to notifications, loads initial data)
    [self.store start];
}

- (void)dealloc {
    [self.store stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)render:(SRAppModel *)model {
    self.selectedRoom = model.selectedRoom;
    self.inspectorView.hidden = (model.workspace == SRWorkspaceContextSettings);
    self.stripVC.selectedContext = model.workspace;
    
    // Pass state to sidebar
    self.sidebarVC.gitRepos = model.gitRepos;
    self.sidebarVC.rooms = model.rooms;
    self.sidebarVC.activeContext = model.workspace;
    [self.sidebarVC reloadContents];
    
    // Pass room sync status to sidebar
    if (model.selectedRoom) {
        NSString *syncStatus = model.roomSyncStatuses[model.selectedRoom.host];
        NSNumber *syncProgress = model.roomSyncProgress[model.selectedRoom.host];
        [self.sidebarVC updateSyncStatus:syncStatus progress:syncProgress ? syncProgress.floatValue : 1.0f];
    }

    // Handle errors
    if (model.error) {
        [self.errorBanner showMessage:model.error.localizedDescription type:SRNotificationTypeError];
        self.errorBanner.hidden = NO;
    } else if (model.loadingState != SRLoadingStateLoading) {
        [self.errorBanner hide];
    }

    // Pass feed data to FeedViewController if showing
    if (model.destination == SRDestinationHome && self.feedVC) {
        [self.feedVC setMessages:model.feed];
    }

    // Pass peer data to PeerListViewController if showing
    if (model.destination == SRDestinationPeers && self.peerListVC) {
        NSMutableArray *peerIDs = [NSMutableArray array];
        NSMutableDictionary *syncStatus = [NSMutableDictionary dictionary];
        NSMutableDictionary *syncProgress = [NSMutableDictionary dictionary];
        
        for (SRPeerModel *peer in model.peers) {
            [peerIDs addObject:peer.peerID];
            if (peer.syncState != SRPeerSyncStateDisconnected) {
                syncStatus[peer.peerID] = peer.syncState == SRPeerSyncStateReady ? @"Synced" : @"Syncing";
                syncProgress[peer.peerID] = @(peer.syncProgress);
            }
        }
        
        [self.peerListVC updatePeers:peerIDs];
        [self.peerListVC updateSyncStatus:syncStatus progress:syncProgress];
    }

    // Reactive Content Swap
    if (self.currentDestination != model.destination) {
        self.currentDestination = model.destination;

        [self.currentCanvasVC.view removeFromSuperview];
        [self.currentCanvasVC removeFromParentViewController];
        [self.composeVC.view removeFromSuperview];
        [self.composeVC removeFromParentViewController];
        self.feedVC = nil;
        self.peerListVC = nil;
        self.composeVC = nil;

        switch (model.destination) {
            case SRDestinationHome: {
                SRFeedViewController *feedVC = [[SRFeedViewController alloc] init];
                feedVC.currentClient = [self currentClient];
                feedVC.feedType = SRFeedTypeTimeline;
                self.feedVC = feedVC;
                self.currentCanvasVC = feedVC;
                // Set initial feed data if available
                if (model.feed.count > 0) {
                    [feedVC setMessages:model.feed];
                }
                // Create compose view
                [self setupComposeView];
                break;
            }
            case SRDestinationChannels: {
                SRChannelBrowserViewController *channelsVC = [[SRChannelBrowserViewController alloc] init];
                self.currentCanvasVC = channelsVC;
                // Set initial channels data if available
                if (model.channels.count > 0) {
                    [channelsVC setChannels:model.channels];
                }
                break;
            }
            case SRDestinationRepos: {
                SRGitRepoListViewController *reposVC = [[SRGitRepoListViewController alloc] initWithListType:SRGitRepoListTypeMyRepos];
                reposVC.currentClient = [self currentClient];
                self.currentCanvasVC = reposVC;
                // Set initial repos data if available
                if (model.gitRepos.count > 0) {
                    [reposVC setRepos:model.gitRepos];
                }
                break;
            }
            case SRDestinationPeers: {
                SRPeerListViewController *peersVC = [[SRPeerListViewController alloc] init];
                peersVC.roomHost = self.selectedRoom.host;
                self.peerListVC = peersVC;
                self.currentCanvasVC = peersVC;
                // Set initial peer data if available
                if (model.peers.count > 0) {
                    NSMutableArray *peerIDs = [NSMutableArray array];
                    for (SRPeerModel *peer in model.peers) {
                        [peerIDs addObject:peer.peerID];
                    }
                    [peersVC updatePeers:peerIDs];
                }
                break;
            }
        }
    }

    // Reactive Content Swap
    if (self.currentDestination != model.destination) {
        self.currentDestination = model.destination;

        [self.currentCanvasVC.view removeFromSuperview];
        [self.currentCanvasVC removeFromParentViewController];
        self.feedVC = nil;

        switch (model.destination) {
            case SRDestinationHome: {
                SRFeedViewController *feedVC = [[SRFeedViewController alloc] init];
                feedVC.currentClient = [self currentClient];
                feedVC.feedType = SRFeedTypeTimeline;
                self.feedVC = feedVC;
                self.currentCanvasVC = feedVC;
                // Set initial feed data if available
                if (model.feed.count > 0) {
                    [feedVC setMessages:model.feed];
                }
                break;
            }
            case SRDestinationChannels: {
                self.currentCanvasVC = [[SRChannelBrowserViewController alloc] init];
                break;
            }
            case SRDestinationRepos: {
                SRGitRepoListViewController *reposVC = [[SRGitRepoListViewController alloc] initWithListType:SRGitRepoListTypeMyRepos];
                reposVC.currentClient = [self currentClient];
                self.currentCanvasVC = reposVC;
                break;
            }
            case SRDestinationPeers: {
                SRPeerListViewController *peersVC = [[SRPeerListViewController alloc] init];
                peersVC.roomHost = self.selectedRoom.host;
                self.currentCanvasVC = peersVC;
                break;
            }
        }

        [self addChildViewController:self.currentCanvasVC];
        self.currentCanvasVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.canvasView addSubview:self.currentCanvasVC.view];

        [NSLayoutConstraint activateConstraints:@[
            [self.currentCanvasVC.view.topAnchor constraintEqualToAnchor:self.canvasView.topAnchor],
            [self.currentCanvasVC.view.bottomAnchor constraintEqualToAnchor:self.canvasView.bottomAnchor],
            [self.currentCanvasVC.view.leadingAnchor constraintEqualToAnchor:self.canvasView.leadingAnchor],
            [self.currentCanvasVC.view.trailingAnchor constraintEqualToAnchor:self.canvasView.trailingAnchor]
        ]];
    }
}

- (void)setupLayout {
    // 1. Left Nexus Strip Toolbar
    NSVisualEffectView *stripEffect = [[NSVisualEffectView alloc] init];
    stripEffect.material = NSVisualEffectMaterialDark;
    stripEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    stripEffect.state = NSVisualEffectStateActive;
    stripEffect.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stripEffect];
    self.nexusStripView = stripEffect;

    self.stripVC = [[SRStripViewController alloc] init];
    self.stripVC.delegate = self;
    [self addChildViewController:self.stripVC];
    self.stripVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nexusStripView addSubview:self.stripVC.view];

    [NSLayoutConstraint activateConstraints:@[
        [self.stripVC.view.topAnchor constraintEqualToAnchor:self.nexusStripView.topAnchor],
        [self.stripVC.view.bottomAnchor constraintEqualToAnchor:self.nexusStripView.bottomAnchor],
        [self.stripVC.view.leadingAnchor constraintEqualToAnchor:self.nexusStripView.leadingAnchor],
        [self.stripVC.view.trailingAnchor constraintEqualToAnchor:self.nexusStripView.trailingAnchor]
    ]];

    // 2. Collapsible Inspector / Sub-sidebar
    NSVisualEffectView *inspectorEffect = [[NSVisualEffectView alloc] init];
    inspectorEffect.material = NSVisualEffectMaterialDark;
    inspectorEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    inspectorEffect.state = NSVisualEffectStateActive;
    inspectorEffect.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:inspectorEffect];
    self.inspectorView = inspectorEffect;

    // Embed Sidebar underneath Inspector
    self.sidebarVC = [[SRSidebarViewController alloc] init];
    self.sidebarVC.delegate = self;
    self.sidebarVC.hideProfileHeader = YES;
    [self addChildViewController:self.sidebarVC];
    self.sidebarVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.inspectorView addSubview:self.sidebarVC.view];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarVC.view.topAnchor constraintEqualToAnchor:self.inspectorView.topAnchor],
        [self.sidebarVC.view.bottomAnchor constraintEqualToAnchor:self.inspectorView.bottomAnchor],
        [self.sidebarVC.view.leadingAnchor constraintEqualToAnchor:self.inspectorView.leadingAnchor],
        [self.sidebarVC.view.trailingAnchor constraintEqualToAnchor:self.inspectorView.trailingAnchor]
    ]];

    // 3. Main Center Canvas for Timeline
    self.canvasView = [[NSView alloc] init];
    self.canvasView.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvasView.wantsLayer = YES;
    self.canvasView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.18 alpha:1.0].CGColor;
    [self.view addSubview:self.canvasView];

    self.inspectorWidthConstraint = [self.inspectorView.widthAnchor constraintEqualToConstant:220];

    [NSLayoutConstraint activateConstraints:@[
        // Strip: pinned Left, Top, Bottom
        [self.nexusStripView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nexusStripView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.nexusStripView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.nexusStripView.widthAnchor constraintEqualToConstant:64],

        // Inspector: pinned Next to Strip, Top, Bottom
        [self.inspectorView.leadingAnchor constraintEqualToAnchor:self.nexusStripView.trailingAnchor],
        [self.inspectorView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.inspectorView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.inspectorWidthConstraint,

        // Canvas: Pinned Next to Inspector, fills balance
        [self.canvasView.leadingAnchor constraintEqualToAnchor:self.inspectorView.trailingAnchor],
        [self.canvasView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.canvasView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.canvasView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

#pragma mark - SRStripDelegate

- (void)stripDidSelectContext:(SRWorkspaceContext)context {
    [self.store dispatch:[SRMsg setWorkspaceContext:context]];
}

#pragma mark - SRSidebarDelegate

- (void)sidebarViewController:(SRSidebarViewController *)sidebar didSelectDestination:(NSString *)identifier {
    SRDestination dest = SRDestinationHome;
    if ([identifier isEqualToString:@"home"]) {
        dest = SRDestinationHome;
    } else if ([identifier isEqualToString:@"channels"]) {
        dest = SRDestinationChannels;
    } else if ([identifier isEqualToString:@"repos"]) {
        dest = SRDestinationRepos;
    } else if ([identifier isEqualToString:@"peers"]) {
        dest = SRDestinationPeers;
    }
    
    [self.store dispatch:[SRMsg selectDestination:dest]];
}

#pragma mark - Client Helpers

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

- (void)roomSelected:(NSNotification *)notification {
    RoomConfig *room = notification.userInfo[SRRoomManagerRoomSelectedKey];
    [self.store dispatch:[SRMsg selectRoom:room]];
}

- (void)roomsDidUpdate:(NSNotification *)notification {
    [self.store dispatch:[SRMsg loadRooms]];
}

- (void)setupComposeView {
    self.composeVC = [[SRComposeViewController alloc] init];
    self.composeVC.roomHost = self.selectedRoom.host;
    __weak typeof(self) weakSelf = self;
    self.composeVC.onPublish = ^(NSString *text, NSString * _Nullable contentWarning, NSString * _Nullable replyToKey, void (^completion)(BOOL success, NSError * _Nullable error)) {
        NSDictionary *content = @{@"type": @"post", @"text": text};
        [weakSelf.store dispatch:[SRMsg publishMessage:content replyTo:replyToKey cw:contentWarning]];
        completion(YES, nil);
    };
    [self addChildViewController:self.composeVC];
    self.composeVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.composeVC.view];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.composeVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.composeVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.composeVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20],
        [self.composeVC.view.heightAnchor constraintEqualToConstant:120]
    ]];
}

- (void)setupErrorBanner {
    self.errorBanner = [[SRErrorBannerView alloc] init];
    self.errorBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorBanner.hidden = YES;
    [self.view addSubview:self.errorBanner];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.errorBanner.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [self.errorBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.errorBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.errorBanner.heightAnchor constraintEqualToConstant:44]
    ]];
}

@end
