#import "SRProfileViewController.h"
#import "SRFeedViewController.h"
#import "SRProfileHeaderView.h"

@interface SRProfileViewController () <SRFeedViewControllerDelegate>
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) SRFeedViewController *feedVC;
@property (nonatomic, strong) NSButton *backButton;
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
    
    self.backButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Back"] target:self action:@selector(backAction:)];
    self.backButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backButton];
    
    self.feedVC = [[SRFeedViewController alloc] init];
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
        
        [self.feedVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.feedVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.feedVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.feedVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [self.headerView updateWithIdentity:self.peerID name:nil];
    [self.feedVC loadFeedForAuthor:self.peerID client:self.client];
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
