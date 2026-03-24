#import "SRGitRepoListViewController.h"
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBGitRepo.h"
#import "../../Sources/SSBQueryEngine.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBSecretStore.h"

@interface SRGitRepoListViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *repos;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSButton *cloneButton;
@property (nonatomic, strong) NSButton *createRepoButton;
@end

@implementation SRGitRepoListViewController

- (instancetype)initWithListType:(SRGitRepoListType)listType {
    if ((self = [super init])) {
        _listType = listType;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self refreshRepos];
}

- (void)setupUI {
    self.cloneButton = [NSButton buttonWithTitle:@"Clone Repo" target:self action:@selector(cloneRepoAction:)];
    self.cloneButton.bezelStyle = NSBezelStyleRounded;
    self.cloneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cloneButton];

    self.createRepoButton = [NSButton buttonWithTitle:@"New Repo" target:self action:@selector(initRepoAction:)];
    self.createRepoButton.bezelStyle = NSBezelStyleRounded;
    self.createRepoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.createRepoButton];

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 50;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"RepoColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.displayedWhenStopped = NO;
    self.progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.cloneButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.cloneButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        
        [self.createRepoButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.createRepoButton.trailingAnchor constraintEqualToAnchor:self.cloneButton.leadingAnchor constant:-8],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:self.cloneButton.bottomAnchor constant:10],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)cloneRepoAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Clone Repository";
    alert.informativeText = @"Enter the ssb:// URL of the repository you want to clone/follow:";
    [alert addButtonWithTitle:@"Clone"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    alert.accessoryView = input;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *url = input.stringValue;
        if ([url hasPrefix:@"ssb://"]) {
            NSString *repoID = [url substringFromIndex:6];
            // Post notification to navigate to it
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitRepoSelectedNotification"
                                                                object:nil
                                                              userInfo:@{@"SRGitRepoSelectedKey": repoID}];
        }
    }
}

- (void)initRepoAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create New Repository";
    alert.informativeText = @"Enter a name for your new SSB repository:";
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    alert.accessoryView = input;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = input.stringValue;
        if (name.length > 0 && self.currentClient) {
            [SSBGitRepo publishRepoWithName:name upstream:nil client:self.currentClient completion:^(NSString * _Nullable msgID, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (msgID) {
                        [self refreshRepos];
                    }
                });
            }];
        }
    }
}

- (void)setRepos:(NSArray<SSBMessage *> *)repos {
    self.repos = repos;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        [self.progressIndicator stopAnimation:nil];
    });
}

- (void)refreshRepos {
    [self.progressIndicator startAnimation:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *query;
        if (self.listType == SRGitRepoListTypeMyRepos) {
            NSData *secret = SSBLoadIdentitySecret();
            NSString *myID = SSBPublicIDFromSecret(secret);
            query = @{
                @"AND": @[
                    @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"git-repo" ] },
                    @{ @"EQUAL": @[ @[@"value", @"author"], myID ] }
                ]
            };
        } else {
            // For now, simplified: all git-repos not by me
            NSData *secret = SSBLoadIdentitySecret();
            NSString *myID = SSBPublicIDFromSecret(secret);
            query = @{
                @"AND": @[
                    @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"git-repo" ] },
                    @{ @"NOT": @{ @"EQUAL": @[ @[@"value", @"author"], myID ] } }
                ]
            };
        }
        
        NSArray *results = [[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @YES}];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.repos = results;
            [self.tableView reloadData];
            [self.progressIndicator stopAnimation:nil];
        });
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.repos.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"RepoCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
        cell.identifier = @"RepoCell";
        
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.font = [NSFont boldSystemFontOfSize:13];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:tf];
        cell.textField = tf;
        
        NSTextField *authorTf = [NSTextField labelWithString:@""];
        authorTf.font = [NSFont systemFontOfSize:11];
        authorTf.textColor = [NSColor secondaryLabelColor];
        authorTf.translatesAutoresizingMaskIntoConstraints = NO;
        authorTf.identifier = @"AuthorText";
        [cell addSubview:authorTf];
        
        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [tf.topAnchor constraintEqualToAnchor:cell.topAnchor constant:8],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            
            [authorTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [authorTf.topAnchor constraintEqualToAnchor:tf.bottomAnchor constant:2],
            [authorTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12]
        ]];
    }
    
    SSBMessage *msg = self.repos[row];
    NSDictionary *content = msg.content;
    
    cell.textField.stringValue = content[@"name"] ?: @"Unnamed Repository";
    
    NSTextField *authorTf = nil;
    for (NSView *v in cell.subviews) {
        if ([v.identifier isEqualToString:@"AuthorText"]) {
            authorTf = (NSTextField *)v;
            break;
        }
    }
    
    authorTf.stringValue = [NSString stringWithFormat:@"by %@", [[SRRoomManager sharedManager] displayNameForAuthor:msg.author]];
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0) return;
    
    SSBMessage *msg = self.repos[row];
    // Notify that a repo was selected
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitRepoSelectedNotification"
                                                        object:nil
                                                      userInfo:@{@"SRGitRepoSelectedKey": msg.key}];
}

@end
