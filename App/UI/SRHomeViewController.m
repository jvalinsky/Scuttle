#import "SRHomeViewController.h"

@interface SRHomeViewController ()
@property (nonatomic, strong, readwrite) SRFeedViewController *feedVC;
@property (nonatomic, strong, readwrite) SRComposeViewController *composeVC;
@property (nonatomic, strong, readwrite) SRProfileHeaderView *headerView;
@property (nonatomic, strong, readwrite) SRErrorBannerView *errorBanner;
@end

@implementation SRHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.errorBanner = [[SRErrorBannerView alloc] init];
    self.errorBanner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.errorBanner];

    self.headerView = [[SRProfileHeaderView alloc] init];
    self.headerView.hidesProfileButton = YES;
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];

    self.feedVC = [[SRFeedViewController alloc] init];
    [self addChildViewController:self.feedVC];
    self.feedVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.feedVC.view];

    self.composeVC = [[SRComposeViewController alloc] init];
    [self addChildViewController:self.composeVC];
    self.composeVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.composeVC.view];

    [NSLayoutConstraint activateConstraints:@[
        [self.errorBanner.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.errorBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.errorBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.headerView.topAnchor constraintEqualToAnchor:self.errorBanner.bottomAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:60],

        [self.feedVC.view.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.feedVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.feedVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.feedVC.view.bottomAnchor constraintEqualToAnchor:self.composeVC.view.topAnchor constant:-12],

        [self.composeVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.composeVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.composeVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20],
        [self.composeVC.view.heightAnchor constraintEqualToConstant:120],
    ]];
}

@end
