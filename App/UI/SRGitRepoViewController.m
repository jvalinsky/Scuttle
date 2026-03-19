#import "SRGitRepoViewController.h"
#import "SRGitFileTreeViewController.h"
#import "SRGitFileViewController.h"
#import "SRGitCommitLogViewController.h"
#import "SRGitDiffViewController.h"
#import "SRGitIssueListViewController.h"
#import "SRGitIssueDetailViewController.h"
#import "SRGitPRListViewController.h"
#import "SRGitPRDetailViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBGitIssueStore.h"
#import "../../Sources/SSBGitPRStore.h"

@interface SRGitRepoViewController () <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, strong) NSSegmentedControl *segmentedControl;
@property (nonatomic, strong) NSButton *forkButton;
@property (nonatomic, strong) SRGitFileTreeViewController *fileTreeVC;
@property (nonatomic, strong) SRGitFileViewController *fileVC;
@property (nonatomic, strong) SRGitCommitLogViewController *commitLogVC;
@property (nonatomic, strong) SRGitDiffViewController *diffVC;
@property (nonatomic, strong) SRGitIssueListViewController *issueListVC;
@property (nonatomic, strong) SRGitIssueDetailViewController *issueDetailVC;
@property (nonatomic, strong) SRGitPRListViewController *prListVC;
@property (nonatomic, strong) SRGitPRDetailViewController *prDetailVC;
@property (nonatomic, strong) NSView *containerView;

@property (nonatomic, strong) NSScrollView *activityScrollView;
@property (nonatomic, strong) NSTableView *activityTableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *activityMessages;
@end

@implementation SRGitRepoViewController

- (instancetype)initWithRepo:(SSBGitRepo *)repo {
    if ((self = [super init])) {
        _repo = repo;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileSelected:) name:@"SRGitFileSelectedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commitSelected:) name:@"SRGitCommitSelectedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(issueSelected:) name:@"SRGitIssueSelectedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prSelected:) name:@"SRGitPRSelectedNotification" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)fileSelected:(NSNotification *)notification {
    NSString *sha1 = notification.userInfo[@"sha1"];
    NSString *name = notification.userInfo[@"name"];
    if (sha1 && name) {
        [self.fileVC loadFileWithSHA1:sha1 name:name objectStore:self.repo.objectStore];
    }
}

- (void)commitSelected:(NSNotification *)notification {
    NSString *sha1 = notification.userInfo[@"sha1"];
    if (sha1) {
        [self.diffVC loadDiffForCommit:sha1 repo:self.repo];
    }
}

- (void)issueSelected:(NSNotification *)notification {
    NSString *issueID = notification.userInfo[@"issueID"];
    if (issueID) {
        [self.issueDetailVC loadIssue:issueID];
    }
}

- (void)prSelected:(NSNotification *)notification {
    NSString *prID = notification.userInfo[@"prID"];
    if (prID) {
        [self.prDetailVC loadPR:prID];
    }
}

- (void)setupUI {
    self.segmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Code", @"Activity", @"Commits", @"Issues", @"PRs"]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:self
                                                                    action:@selector(segmentChanged:)];
    self.segmentedControl.selectedSegment = 0;
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.segmentedControl];

    self.forkButton = [NSButton buttonWithTitle:@"Fork" target:self action:@selector(fork:)];
    self.forkButton.bezelStyle = NSBezelStyleRounded;
    self.forkButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.forkButton];
    
    self.containerView = [[NSView alloc] init];
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.containerView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.segmentedControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.forkButton.centerYAnchor constraintEqualToAnchor:self.segmentedControl.centerYAnchor],
        [self.forkButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        [self.containerView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:10],
        [self.containerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.containerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    [self showCodeView];
}

- (void)segmentChanged:(id)sender {
    switch (self.segmentedControl.selectedSegment) {
        case 0: [self showCodeView]; break;
        case 1: [self showActivityView]; break;
        case 2: [self showCommitsView]; break;
        case 3: [self showIssuesView]; break;
        case 4: [self showPRsView]; break;
        default: break;
    }
}

- (void)fork:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Fork Repository";
    alert.informativeText = @"Enter a name for your new fork:";
    [alert addButtonWithTitle:@"Fork"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    // Default name is current repo name (needs investigation to get actual name, 
    // but repoID is what we have. Let's assume we want a name.)
    input.placeholderString = @"my-fork-name";
    alert.accessoryView = input;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = input.stringValue;
        if (name.length == 0) return;
        
        [self.forkButton setEnabled:NO];
        [SSBGitRepo publishRepoWithName:name upstream:self.repo.repoID client:self.currentClient completion:^(NSString * _Nullable msgID, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.forkButton setEnabled:YES];
                if (error) {
                    NSAlert *err = [[NSAlert alloc] init];
                    err.messageText = @"Fork Failed";
                    err.informativeText = error.localizedDescription;
                    [err runModal];
                } else {
                    NSAlert *success = [[NSAlert alloc] init];
                    success.messageText = @"Repository Forked";
                    success.informativeText = [NSString stringWithFormat:@"Successfully created fork: %@", name];
                    [success runModal];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitRepoCreatedNotification" object:nil];
                }
            });
        }];
    }
}

- (void)showCodeView {
    if (!self.fileTreeVC) {
        self.fileTreeVC = [[SRGitFileTreeViewController alloc] initWithRepo:self.repo];
        self.fileVC = [[SRGitFileViewController alloc] init];
    }
    NSSplitViewController *svc = [[NSSplitViewController alloc] init];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.fileTreeVC]];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.fileVC]];
    [self setMainView:svc.view];
}

- (void)showActivityView {
    if (!self.activityTableView) {
        self.activityScrollView = [[NSScrollView alloc] init];
        self.activityScrollView.hasVerticalScroller = YES;
        
        self.activityTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
        self.activityTableView.delegate = self;
        self.activityTableView.dataSource = self;
        self.activityTableView.headerView = nil;
        self.activityTableView.rowHeight = 60;
        
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ActivityCol"];
        [self.activityTableView addTableColumn:col];
        self.activityScrollView.documentView = self.activityTableView;
    }
    
    self.activityMessages = [self.repo updateMessages];
    [self.activityTableView reloadData];
    [self setMainView:self.activityScrollView];
}

- (void)showCommitsView {
    if (!self.commitLogVC) {
        self.commitLogVC = [[SRGitCommitLogViewController alloc] initWithRepo:self.repo];
        self.diffVC = [[SRGitDiffViewController alloc] init];
    }
    NSSplitViewController *svc = [[NSSplitViewController alloc] init];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.commitLogVC]];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.diffVC]];
    [self setMainView:svc.view];
}

- (void)showIssuesView {
    if (!self.issueListVC) {
        SSBGitIssueStore *store = [[SSBGitIssueStore alloc] initWithRepoID:self.repo.repoID feedStore:self.repo.feedStore];
        self.issueListVC = [[SRGitIssueListViewController alloc] initWithIssueStore:store];
        self.issueListVC.currentClient = self.currentClient;
        self.issueDetailVC = [[SRGitIssueDetailViewController alloc] initWithIssueStore:store];
        self.issueDetailVC.currentClient = self.currentClient;
    }
    NSSplitViewController *svc = [[NSSplitViewController alloc] init];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.issueListVC]];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.issueDetailVC]];
    [self setMainView:svc.view];
}

- (void)showPRsView {
    if (!self.prListVC) {
        SSBGitPRStore *store = [[SSBGitPRStore alloc] initWithRepoID:self.repo.repoID feedStore:self.repo.feedStore];
        self.prListVC = [[SRGitPRListViewController alloc] initWithPRStore:store];
        self.prDetailVC = [[SRGitPRDetailViewController alloc] initWithPRStore:store];
        self.prDetailVC.currentClient = self.currentClient;
    }
    NSSplitViewController *svc = [[NSSplitViewController alloc] init];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.prListVC]];
    [svc addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.prDetailVC]];
    [self setMainView:svc.view];
}

- (void)setMainView:(NSView *)view {
    for (NSView *subview in self.containerView.subviews) {
        [subview removeFromSuperview];
    }
    view.frame = self.containerView.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.containerView addSubview:view];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.activityTableView) {
        return self.activityMessages.count;
    }
    return 0;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.activityTableView) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"GitActivityCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
            cell.identifier = @"GitActivityCell";
            
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.font = [NSFont boldSystemFontOfSize:13];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:tf];
            cell.textField = tf;
            
            NSTextField *subTf = [NSTextField labelWithString:@""];
            subTf.font = [NSFont systemFontOfSize:11];
            subTf.textColor = [NSColor secondaryLabelColor];
            subTf.translatesAutoresizingMaskIntoConstraints = NO;
            subTf.identifier = @"SubText";
            [cell addSubview:subTf];
            
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
                [tf.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
                [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
                
                [subTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
                [subTf.topAnchor constraintEqualToAnchor:tf.bottomAnchor constant:4],
                [subTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12]
            ]];
        }
        
        SSBMessage *msg = self.activityMessages[row];
        NSDictionary *content = msg.content;
        
        cell.textField.stringValue = [NSString stringWithFormat:@"Pushed by %@", [[SRRoomManager sharedManager] displayNameForAuthor:msg.author]];
        
        NSTextField *subTf = nil;
        for (NSView *v in cell.subviews) {
            if ([v.identifier isEqualToString:@"SubText"]) {
                subTf = (NSTextField *)v;
                break;
            }
        }
        
        NSDictionary *refs = content[@"refs"];
        subTf.stringValue = [NSString stringWithFormat:@"Updated refs: %@", [refs.allKeys componentsJoinedByString:@", "]];
        
        return cell;
    }
    return nil;
}

@end
