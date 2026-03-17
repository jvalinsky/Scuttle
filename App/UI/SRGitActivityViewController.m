#import "SRGitActivityViewController.h"
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBQueryEngine.h"
#import "../Logic/SRRoomManager.h"
#import <os/log.h>

@interface SRGitActivityViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SSBMessage *> *messages;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@end

@implementation SRGitActivityViewController

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self refreshActivity];
}

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:self.view.bounds];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 60;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"ActivityColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.displayedWhenStopped = NO;
    self.progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)refreshActivity {
    [self.progressIndicator startAnimation:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *query = @{
            @"OR": @[
                @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"git-update" ] },
                @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"issue" ] },
                @{ @"EQUAL": @[ @[@"value", @"content", @"pull-request" ] ] }
            ]
        };
        
        NSArray *results = [[SSBFeedStore sharedStore] querySubset:query options:@{@"descending": @YES, @"limit": @50}];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.messages = results;
            [self.tableView reloadData];
            [self.progressIndicator stopAnimation:nil];
        });
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.messages.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"GitActivityCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
        cell.identifier = @"GitActivityCell";
        
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.font = [NSFont systemFontOfSize:13];
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
    
    SSBMessage *msg = self.messages[row];
    NSDictionary *content = msg.content;
    NSString *type = content[@"type"];
    
    NSTextField *subTf = nil;
    for (NSView *v in cell.subviews) {
        if ([v.identifier isEqualToString:@"SubText"]) {
            subTf = (NSTextField *)v;
            break;
        }
    }
    
    if ([type isEqualToString:@"git-update"]) {
        cell.textField.stringValue = [NSString stringWithFormat:@"%@ pushed to %@", [[SRRoomManager sharedManager] displayNameForAuthor:msg.author], content[@"repo"]];
        subTf.stringValue = [NSString stringWithFormat:@"Commits updated: %@", [content[@"refs"] allKeys]];
    } else if ([type isEqualToString:@"issue"]) {
        cell.textField.stringValue = [NSString stringWithFormat:@"%@ opened issue: %@", [[SRRoomManager sharedManager] displayNameForAuthor:msg.author], content[@"title"]];
        subTf.stringValue = [NSString stringWithFormat:@"Repo: %@", content[@"repo"]];
    } else if ([type isEqualToString:@"pull-request"]) {
        cell.textField.stringValue = [NSString stringWithFormat:@"%@ opened PR: %@", [[SRRoomManager sharedManager] displayNameForAuthor:msg.author], content[@"title"]];
        subTf.stringValue = [NSString stringWithFormat:@"Repo: %@", content[@"repo"]];
    }
    
    return cell;
}

@end
