#import "SRGitPRListViewController.h"
#import "SRGitNewPRViewController.h"
#import "../Logic/SRRoomManager.h"

@interface SRGitPRListViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *pullRequests;
@property (nonatomic, strong) NSButton *newPRButton;
@end

@implementation SRGitPRListViewController

- (instancetype)initWithPRStore:(SSBGitPRStore *)prStore {
    if (self = [super init]) {
        _prStore = prStore;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadPRs];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadPRs) name:@"SRGitPRCreatedNotification" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    self.newPRButton = [NSButton buttonWithTitle:@"New Pull Request" target:self action:@selector(showNewPR:)];
    self.newPRButton.bezelStyle = NSBezelStyleRounded;
    self.newPRButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.newPRButton];

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 50;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"PRColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.newPRButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.newPRButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.newPRButton.bottomAnchor constant:10],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)showNewPR:(id)sender {
    if (!self.currentClient) return;
    SRGitNewPRViewController *vc = [[SRGitNewPRViewController alloc] initWithRepoID:self.prStore.repoID client:self.currentClient];
    [self presentViewControllerAsSheet:vc];
}

- (void)loadPRs {
    self.pullRequests = [self.prStore pullRequests];
    [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.pullRequests.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"PRCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
        cell.identifier = @"PRCell";
        
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
    
    SSBMessage *msg = self.pullRequests[row];
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
    
    SSBMessage *msg = self.pullRequests[row];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitPRSelectedNotification"
                                                        object:nil
                                                      userInfo:@{@"prID": msg.key}];
}

@end
