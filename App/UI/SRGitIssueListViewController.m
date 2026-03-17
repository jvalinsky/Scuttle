#import "SRGitIssueListViewController.h"
#import "SRGitNewIssueViewController.h"
#import "../Logic/SRRoomManager.h"

@interface SRGitIssueListViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *issues;
@property (nonatomic, strong) NSButton *newIssueButton;
@end

@implementation SRGitIssueListViewController

- (instancetype)initWithIssueStore:(SSBGitIssueStore *)issueStore {
    if (self = [super init]) {
        _issueStore = issueStore;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadIssues];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadIssues) name:@"SRGitIssueCreatedNotification" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    self.newIssueButton = [NSButton buttonWithTitle:@"New Issue" target:self action:@selector(showNewIssue:)];
    self.newIssueButton.bezelStyle = NSBezelStyleRounded;
    self.newIssueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.newIssueButton];
    
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 50;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"IssueColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.newIssueButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.newIssueButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.newIssueButton.bottomAnchor constant:10],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)showNewIssue:(id)sender {
    if (!self.currentClient) return;
    SRGitNewIssueViewController *vc = [[SRGitNewIssueViewController alloc] initWithRepoID:self.issueStore.repoID client:self.currentClient];
    [self presentViewControllerAsSheet:vc];
}

- (void)loadIssues {
    self.issues = [self.issueStore issues];
    [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.issues.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"IssueCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
        cell.identifier = @"IssueCell";
        
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
            [tf.topAnchor constraintEqualToAnchor:cell.topAnchor constant:8],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            
            [subTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [subTf.topAnchor constraintEqualToAnchor:tf.bottomAnchor constant:2],
            [subTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12]
        ]];
    }
    
    SSBMessage *msg = self.issues[row];
    NSDictionary *content = msg.content;
    
    cell.textField.stringValue = content[@"title"] ?: @"(No title)";
    
    NSTextField *subTf = nil;
    for (NSView *v in cell.subviews) {
        if ([v.identifier isEqualToString:@"SubText"]) {
            subTf = (NSTextField *)v;
            break;
        }
    }
    
    subTf.stringValue = [NSString stringWithFormat:@"#%@ by %@", [msg.key substringWithRange:NSMakeRange(1, 6)], [[SRRoomManager sharedManager] displayNameForAuthor:msg.author]];
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0) return;
    
    SSBMessage *msg = self.issues[row];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitIssueSelectedNotification"
                                                        object:nil
                                                      userInfo:@{@"issueID": msg.key}];
}

@end
