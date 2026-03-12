#import "SRProfileViewController.h"
#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import "../../Sources/SSBLogger.h"
#import <SSBNetwork/SSBNetwork.h>
#import <SSBNetwork/SSBRoomClient.h>
#import "SRProfileHeaderView.h"

@interface SRProfileViewController () <SRFeedViewControllerDelegate>
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *followButton;
@property (nonatomic, strong) NSButton *blockButton;
@end

@implementation SRProfileViewController

- (instancetype)initWithPeerID:(NSString *)peerID client:(nullable SSBRoomClient *)client {
    self = [super init];
    if (self) {
        _peerID = peerID;
        _client = client;
    }
    return self;
}

- (void)loadView {
    NSView *container = [[NSView alloc] init];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    SSBLogInfo(SSBLogCategoryUI, @"📱 SRProfileViewController viewDidLoad: peerID=%@", [self.peerID substringToIndex:MIN(8, self.peerID.length)]);
    SSBLogInfo(SSBLogCategoryUI, @"   client=%@ connected=%d", self.client ? @"yes" : @"no", self.client.isConnected);
    
    self.headerView = [[SRProfileHeaderView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];
    
    self.backButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Back"] target:self action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backButton];
    
    self.followButton = [NSButton buttonWithTitle:@"Follow" target:self action:@selector(followAction:)];
    self.followButton.bezelStyle = NSBezelStyleRounded;
    self.followButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.followButton];
    
    self.blockButton = [NSButton buttonWithTitle:@"Block" target:self action:@selector(blockAction:)];
    self.blockButton.bezelStyle = NSBezelStyleRounded;
    self.blockButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blockButton];
    
    self.feedVC = [[SRFeedViewController alloc] init];
    self.feedVC.hidesBackButton = YES;
    self.feedVC.delegate = self;
    [self addChildViewController:self.feedVC];
    [self.view addSubview:self.feedVC.view];
    self.feedVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.headerView.hidesProfileButton = YES;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.backButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:12],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.followButton.leadingAnchor constant:-12],
        [self.headerView.heightAnchor constraintEqualToConstant:80],
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],

        [self.followButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.followButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.followButton.widthAnchor constraintEqualToConstant:80],
        
        [self.blockButton.topAnchor constraintEqualToAnchor:self.followButton.bottomAnchor constant:4],
        [self.blockButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.blockButton.widthAnchor constraintEqualToConstant:80],
        
        [self.feedVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.feedVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.feedVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.feedVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncStatusChanged:) name:@"SRRoomSyncStatusChangedNotification" object:nil];
    
    [self.headerView updateWithIdentity:self.peerID name:nil];
    
    SSBLogInfo(SSBLogCategoryUI, @"   Loading feed for author...");
    [self.feedVC loadFeedForAuthor:self.peerID client:self.client];
    
    // Trigger replication for preview
    if (self.client && self.client.host) {
        NSLog(@"[UI] Triggering replication from peer %@ via room %@", self.peerID, self.client.host);
        SSBLogInfo(SSBLogCategoryUI, @"   Triggering replication from peer...");
        [self.client replicateFromPeer:self.peerID viaRoom:self.client.host];
    } else {
        NSLog(@"[UI] Cannot replicate: client=%p host=%@", self.client, self.client.host);
        SSBLogWarning(SSBLogCategoryUI, @"   Cannot replicate: client=%@ host=%@", self.client ? @"yes" : @"no", self.client.host);
    }
    
    [self updateFollowButton];
}

- (void)updateFollowButton {
    if ([[SSBFeedStore sharedStore] isFollowing:self.peerID]) {
        self.followButton.title = @"Unfollow";
        self.followButton.contentTintColor = [NSColor systemRedColor];
    } else {
        self.followButton.title = @"Follow";
        self.followButton.contentTintColor = [NSColor systemBlueColor];
    }
    
    if ([[SSBFeedStore sharedStore] isBlocked:self.peerID]) {
        self.blockButton.title = @"Unblock";
        self.blockButton.contentTintColor = [NSColor systemRedColor];
    } else {
        self.blockButton.title = @"Block";
        self.blockButton.contentTintColor = [NSColor systemGrayColor];
    }
}

- (void)followAction:(id)sender {
    SSBLogInfo(SSBLogCategoryUI, @"👆 Follow button clicked for: %@", [self.peerID substringToIndex:MIN(8, self.peerID.length)]);
    
    BOOL currentlyFollowing = [[SSBFeedStore sharedStore] isFollowing:self.peerID];
    SSBLogInfo(SSBLogCategoryUI, @"   Current follow state: %@", currentlyFollowing ? @"Following" : @"Not following");
    
    if (!self.client) {
        SSBLogError(SSBLogCategoryUI, @"   ❌ No client available!");
        return;
    }
    
    if (!self.client.isConnected) {
        SSBLogError(SSBLogCategoryUI, @"   ❌ Client not connected!");
        return;
    }
    
    SSBLogInfo(SSBLogCategoryUI, @"   Publishing contact: %@", !currentlyFollowing ? @"Follow" : @"Unfollow");
    [self.client publishContact:self.peerID following:!currentlyFollowing completion:^(id _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                SSBLogError(SSBLogCategoryUI, @"   ❌ publishContact error: %@", error.localizedDescription);
            } else if (response) {
                SSBLogInfo(SSBLogCategoryUI, @"   ✅ publishContact succeeded: %@", response);
            } else {
                SSBLogWarning(SSBLogCategoryUI, @"   ⏳ publishContact queued (feed not synced)");
            }
            [self updateFollowButton];
        });
    }];
}

- (void)blockAction:(id)sender {
    SSBLogInfo(SSBLogCategoryUI, @"🚫 Block button clicked for: %@", [self.peerID substringToIndex:MIN(8, self.peerID.length)]);
    
    BOOL currentlyBlocked = [[SSBFeedStore sharedStore] isBlocked:self.peerID];
    if (self.client) {
        [self.client publishBlock:self.peerID blocking:!currentlyBlocked completion:^(id _Nullable response, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    SSBLogError(SSBLogCategoryUI, @"   ❌ publishBlock error: %@", error.localizedDescription);
                } else if (response) {
                    SSBLogInfo(SSBLogCategoryUI, @"   ✅ publishBlock succeeded");
                } else {
                    SSBLogWarning(SSBLogCategoryUI, @"   ⏳ publishBlock queued (feed not synced)");
                }
                [self updateFollowButton];
            });
        }];
    }
}

- (void)backAction:(id)sender {
    if ([self.delegate respondsToSelector:@selector(profileViewControllerDidRequestBack:)]) {
        [self.delegate profileViewControllerDidRequestBack:self];
    }
}

- (void)syncStatusChanged:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *author = userInfo[@"author"];
    NSString *status = userInfo[@"status"];
    float progress = [userInfo[@"progress"] floatValue];
    
    if ([author isEqualToString:self.peerID]) {
        [self.headerView updateSyncProgress:progress status:status];
    }
}

#pragma mark - SRFeedViewControllerDelegate (Forwarding)

- (void)feedViewController:(SRFeedViewController *)vc didLikeMessage:(SSBMessage *)message {
    if ([self.delegate isKindOfClass:[NSViewController class]]) {
        id<SRFeedViewControllerDelegate> mainDelegate = (id)self.delegate;
        if ([mainDelegate respondsToSelector:@selector(feedViewController:didLikeMessage:)]) {
            [mainDelegate feedViewController:vc didLikeMessage:message];
        }
    }
}

- (void)feedViewController:(SRFeedViewController *)vc didSelectMessageThread:(SSBMessage *)message {
    if ([self.delegate isKindOfClass:[NSViewController class]]) {
        id<SRFeedViewControllerDelegate> mainDelegate = (id)self.delegate;
        if ([mainDelegate respondsToSelector:@selector(feedViewController:didSelectMessageThread:)]) {
            [mainDelegate feedViewController:vc didSelectMessageThread:message];
        }
    }
}

@end
