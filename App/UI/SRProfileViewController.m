#import "SRProfileViewController.h"
#import "SRFeedViewController.h"
#import "SRFeedItem.h"
#import <SSBNetwork/SSBNetwork.h>
#import <SSBNetwork/SSBRoomClient.h>
#import "SRProfileHeaderView.h"

@interface SRProfileViewController () <SRFeedViewControllerDelegate>
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *followButton;
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
    
    self.headerView = [[SRProfileHeaderView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];
    
    self.backButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarGoBackTemplate] target:self action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backButton];
    
    self.followButton = [NSButton buttonWithTitle:@"Follow" target:self action:@selector(followAction:)];
    self.followButton.bezelStyle = NSBezelStyleRounded;
    self.followButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.followButton];
    self.feedVC.delegate = self;
    [self addChildViewController:self.feedVC];
    [self.view addSubview:self.feedVC.view];
    self.feedVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.backButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:12],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:80],
        
        [self.followButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [self.followButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.feedVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.feedVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.feedVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.feedVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [self.headerView updateWithIdentity:self.peerID name:nil];
    [self.feedVC loadFeedForAuthor:self.peerID client:self.client];
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
}

- (void)followAction:(id)sender {
    BOOL currentlyFollowing = [[SSBFeedStore sharedStore] isFollowing:self.peerID];
    if (self.client) {
        [self.client publishContact:self.peerID following:!currentlyFollowing completion:^(NSError *error, id result) {
            dispatch_async(dispatch_get_main_queue(), ^{
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
