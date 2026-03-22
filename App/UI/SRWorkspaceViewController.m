#import "SRWorkspaceViewController.h"
#import "SRStripViewController.h"
#import "SRSidebarViewController.h"
#import "SRFeedViewController.h"
#import "SRChannelBrowserViewController.h"
#import "SRGitRepoListViewController.h"
#import "SRPeerListViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "../../Sources/RoomInviteHandler.h"
#import "TEA/SRStore.h"

@interface SRWorkspaceViewController () <SRStripDelegate, SRSidebarDelegate>
@property (nonatomic, strong) SRStore *store;
@property (nonatomic, assign) SRDestination currentDestination;

@property (nonatomic, strong) SRStripViewController *stripVC;
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;
@property (nonatomic, strong) NSViewController *currentCanvasVC;
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
    self.store = [[SRStore alloc] initWithInitialModel:[SRModel initialModel]];
    self.currentDestination = -1; // Force first render swap
    
    [self setupLayout];
    
    // Subscribe to State Updates
    __weak typeof(self) weakSelf = self;
    [self.store subscribe:^(SRModel *model) {
        [weakSelf render:model];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomSelected:) name:SRRoomManagerRoomSelectedNotification object:nil];

    // Initial Data Load
    [self.store dispatch:[SRMsg loadGitRepos]];
}

- (void)render:(SRModel *)model {
    self.selectedRoom = model.selectedRoom;
    self.inspectorView.hidden = (model.workspaceContext == SRWorkspaceContextSettings);
    self.stripVC.selectedContext = model.workspaceContext; // Render strip bar setup
    
    // Pass state to sidebar
    self.sidebarVC.gitRepos = model.gitRepos;
    self.sidebarVC.activeContext = model.workspaceContext;
    [self.sidebarVC reloadContents];

    // Reactive Content Swap
    if (self.currentDestination != model.activeDestination) {
        self.currentDestination = model.activeDestination;

        [self.currentCanvasVC.view removeFromSuperview];
        [self.currentCanvasVC removeFromParentViewController];

        switch (model.activeDestination) {
            case SRDestinationHome: {
                SRFeedViewController *feedVC = [[SRFeedViewController alloc] init];
                feedVC.currentClient = [self currentClient];
                self.currentCanvasVC = feedVC;
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

@end
