#import "SRMainSplitViewController.h"
#import "SRSidebarViewController.h"
#import "SRFeedViewController.h"
#import "SRComposeViewController.h"
#import "SRPeerListViewController.h"
#import "../Logic/SRRoomManager.h"

@interface SRMainSplitViewController () <SRPeerListDelegate>
@property (nonatomic, strong) SRSidebarViewController *sidebarVC;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) SRComposeViewController *composeVC;
@property (nonatomic, strong) SRPeerListViewController *peerListVC;
@property (nonatomic, strong, nullable) RoomConfig *selectedRoom;
@end

@implementation SRMainSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sidebarVC = [[SRSidebarViewController alloc] init];
    
    // Main Content Area (Feed + Compose)
    NSViewController *contentContainer = [[NSViewController alloc] init];
    contentContainer.view = [[NSView alloc] init];
    
    self.feedVC = [[SRFeedViewController alloc] init];
    [contentContainer addChildViewController:self.feedVC];
    [contentContainer.view addSubview:self.feedVC.view];
    self.feedVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.composeVC = [[SRComposeViewController alloc] init];
    [contentContainer addChildViewController:self.composeVC];
    [contentContainer.view addSubview:self.composeVC.view];
    self.composeVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    __weak typeof(self) weakSelf = self;
    self.composeVC.onPublish = ^(NSString *text, NSString * _Nullable cw) {
        [weakSelf handlePublishWithText:text contentWarning:cw];
    };
    
    [NSLayoutConstraint activateConstraints:@[
        [self.feedVC.view.topAnchor constraintEqualToAnchor:contentContainer.view.topAnchor],
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(endpointsDidUpdate:) 
                                                 name:SRRoomManagerDidUpdateEndpointsNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(roomSelected:) 
                                                 name:@"SRRoomSelectedNotification" 
                                               object:nil];
}

- (void)roomSelected:(NSNotification *)notification {
    self.selectedRoom = notification.object;
    NSLog(@"[MainVC] Room selected: %@", self.selectedRoom.host);
    [self updatePeerList];
    
    // Also trigger a feed refresh for the new room
    [self.feedVC refreshFeed];
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    SSBRoomClient *client = notification.object;
    NSLog(@"[MainVC] DEBUG: Endpoints notification received from %@ (Current selected: %@)", client.host, self.selectedRoom.host);
    if (!self.selectedRoom || [client.host isEqualToString:self.selectedRoom.host]) {
        if (!self.selectedRoom) {
            NSLog(@"[MainVC] DEBUG: No room selected, auto-selecting %@", client.host);
            self.selectedRoom = [[SRRoomManager sharedManager].rooms firstObject];
        }
        [self updatePeerList];
    } else {
        NSLog(@"[MainVC] DEBUG: Notification ignored (host mismatch)");
    }
}

- (void)updatePeerList {
    if (!self.selectedRoom) {
        NSLog(@"[MainVC] DEBUG: updatePeerList called but no room selected");
        [self.peerListVC updatePeers:@[]];
        return;
    }
    NSArray *peers = [SRRoomManager sharedManager].roomEndpoints[self.selectedRoom.host];
    NSLog(@"[MainVC] DEBUG: updatePeerList for %@ - found %lu peers in Manager", self.selectedRoom.host, (unsigned long)peers.count);
    [self.peerListVC updatePeers:peers ?: @[]];
}

- (void)handlePublishWithText:(NSString *)text contentWarning:(NSString *)cw {
    // Publish through the client of the selected room
    SSBRoomClient *client = nil;
    if (self.selectedRoom) {
        client = [[SRRoomManager sharedManager] clientForHost:self.selectedRoom.host];
    }
    
    if (!client) {
        client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    }
    
    if (!client) return;
    
    NSDictionary *content = [SSBMessageCodec rootPostContentWithText:text channel:nil contentWarning:cw mentions:nil recps:nil];
    
    NSError *error = nil;
    SSBMessage *msg = [client publishLocalMessageWithContent:content error:&error];
    if (msg) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SRNewMessageNotification" object:nil];
    }
}

#pragma mark - SRPeerListDelegate

- (void)peerListViewController:(SRPeerListViewController *)vc didSelectPeer:(NSString *)peerID {
    NSLog(@"[MainVC] Handling selection of peer: %@", peerID);
    
    // Switch to author-filtered feed
    SSBRoomClient *client = nil;
    if (self.selectedRoom) {
        client = [[SRRoomManager sharedManager] clientForHost:self.selectedRoom.host];
    }
    
    if (!client) {
        client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    }
    
    if (client) {
        [self.feedVC loadFeedForAuthor:peerID client:client];
    }
}

@end