#import "SRGitIssueDetailViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBMessageCodec.h"

@interface SRGitIssueDetailViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *thread;

@property (nonatomic, strong) NSView *composeContainer;
@property (nonatomic, strong) NSTextView *composeTextView;
@property (nonatomic, strong) NSButton *commentButton;
@end

@implementation SRGitIssueDetailViewController

- (instancetype)initWithIssueStore:(nullable SSBGitIssueStore *)issueStore {
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
}

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.usesAutomaticRowHeights = YES;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"ThreadColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    self.composeContainer = [[NSView alloc] init];
    self.composeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.composeContainer];
    
    NSScrollView *textScroll = [[NSScrollView alloc] init];
    textScroll.hasVerticalScroller = YES;
    textScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composeContainer addSubview:textScroll];
    
    self.composeTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.composeTextView.font = [NSFont systemFontOfSize:13];
    textScroll.documentView = self.composeTextView;
    
    self.commentButton = [NSButton buttonWithTitle:@"Comment" target:self action:@selector(postComment:)];
    self.commentButton.bezelStyle = NSBezelStyleRounded;
    self.commentButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composeContainer addSubview:self.commentButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.composeContainer.topAnchor],
        
        [self.composeContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.composeContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.composeContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.composeContainer.heightAnchor constraintEqualToConstant:120],
        
        [textScroll.topAnchor constraintEqualToAnchor:self.composeContainer.topAnchor constant:10],
        [textScroll.leadingAnchor constraintEqualToAnchor:self.composeContainer.leadingAnchor constant:10],
        [textScroll.trailingAnchor constraintEqualToAnchor:self.composeContainer.trailingAnchor constant:-10],
        [textScroll.bottomAnchor constraintEqualToAnchor:self.commentButton.topAnchor constant:-8],
        
        [self.commentButton.trailingAnchor constraintEqualToAnchor:self.composeContainer.trailingAnchor constant:-10],
        [self.commentButton.bottomAnchor constraintEqualToAnchor:self.composeContainer.bottomAnchor constant:-10]
    ]];
}

- (void)postComment:(id)sender {
    NSString *text = self.composeTextView.string;
    if (text.length == 0 || !self.currentRootID || !self.currentClient) return;
    
    // In git-ssb, comments are standard 'post' messages with root pointing to the issue/PR
    // and branch pointing to the previous message in the thread.
    NSString *root = self.currentRootID;
    NSString *branch = (self.thread.lastObject).key ?: root;
    
    NSDictionary *content = [SSBMessageCodec replyContentWithText:text
                                                             root:root
                                                           branch:branch
                                                          channel:nil
                                                   contentWarning:nil
                                                         mentions:nil
                                                            recps:nil];
    
    [self.commentButton setEnabled:NO];
    [self.currentClient publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.commentButton setEnabled:YES];
            if (!error) {
                self.composeTextView.string = @"";
                [self refreshThread];
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Failed to post comment";
                alert.informativeText = error.localizedDescription;
                [alert runModal];
            }
        });
    }];
}

- (void)refreshThread {
    if (self.issueStore) {
        [self loadIssue:self.currentRootID];
    } else {
        // Must be a PR
        [self performSelector:@selector(loadPR:) withObject:self.currentRootID];
    }
}

- (void)loadIssue:(NSString *)issueID {
    self.currentRootID = issueID;
    
    NSMutableArray *thread = [NSMutableArray array];
    // Find the original issue message
    NSArray *issues = [self.issueStore issues];
    for (SSBMessage *msg in issues) {
        if ([msg.key isEqualToString:issueID]) {
            [thread addObject:msg];
            break;
        }
    }
    
    [thread addObjectsFromArray:[self.issueStore commentsForIssue:issueID]];
    self.thread = thread;
    [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.thread.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ThreadCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 120)];
        cell.identifier = @"ThreadCell";
        
        NSTextField *authorTf = [NSTextField labelWithString:@""];
        authorTf.font = [NSFont boldSystemFontOfSize:12];
        authorTf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:authorTf];

        NSTextField *prInfoTf = [NSTextField labelWithString:@""];
        prInfoTf.font = [NSFont systemFontOfSize:11];
        prInfoTf.textColor = [NSColor secondaryLabelColor];
        prInfoTf.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:prInfoTf];
        
        NSTextField *bodyTf = [NSTextField labelWithString:@""];
        bodyTf.font = [NSFont systemFontOfSize:13];
        bodyTf.translatesAutoresizingMaskIntoConstraints = NO;
        bodyTf.cell.wraps = YES;
        [cell addSubview:bodyTf];
        cell.textField = bodyTf;
        
        [NSLayoutConstraint activateConstraints:@[
            [authorTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [authorTf.topAnchor constraintEqualToAnchor:cell.topAnchor constant:10],
            [authorTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],

            [prInfoTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [prInfoTf.topAnchor constraintEqualToAnchor:authorTf.bottomAnchor constant:4],
            [prInfoTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            
            [bodyTf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [bodyTf.topAnchor constraintEqualToAnchor:prInfoTf.bottomAnchor constant:8],
            [bodyTf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            [bodyTf.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-10]
        ]];
    }
    
    SSBMessage *msg = self.thread[row];
    NSDictionary *content = msg.content;
    
    NSTextField *authorTf = (NSTextField *)cell.subviews[0];
    NSTextField *prInfoTf = (NSTextField *)cell.subviews[1];
    
    authorTf.stringValue = [[SRRoomManager sharedManager] displayNameForAuthor:msg.author];
    
    if ([content[@"type"] isEqualToString:@"pull-request"]) {
        NSString *base = content[@"baseBranch"] ?: @"main";
        NSString *head = content[@"headBranch"] ?: @"feature";
        NSString *headRepo = content[@"headRepo"];
        NSString *repo = content[@"repo"];
        
        if (headRepo && ![headRepo isEqualToString:repo]) {
            // Cross-repo PR: find fork name and author
            SSBMessage *forkMsg = nil;
            NSArray *allRepos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:500];
            for (SSBMessage *m in allRepos) {
                if ([m.key isEqualToString:headRepo]) {
                    forkMsg = m;
                    break;
                }
            }
            
            if (forkMsg) {
                NSString *forkName = forkMsg.content[@"name"] ?: @"fork";
                NSString *forkAuthor = [[SRRoomManager sharedManager] displayNameForAuthor:forkMsg.author];
                prInfoTf.stringValue = [NSString stringWithFormat:@"wants to merge %@/%@:%@ → %@", forkAuthor, forkName, head, base];
            } else {
                prInfoTf.stringValue = [NSString stringWithFormat:@"wants to merge fork:%@ → %@", head, base];
            }
        } else {
            // Same-repo PR
            prInfoTf.stringValue = [NSString stringWithFormat:@"wants to merge %@ → %@", head, base];
        }
        prInfoTf.hidden = NO;
    } else {
        prInfoTf.hidden = YES;
    }
    
    cell.textField.stringValue = content[@"text"] ?: content[@"title"] ?: @"";
    
    return cell;
}

@end
