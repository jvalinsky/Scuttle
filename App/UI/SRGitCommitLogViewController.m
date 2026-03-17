#import "SRGitCommitLogViewController.h"
#import "../../Sources/SSBGitObjectStore.h"
#import "../Logic/SRRoomManager.h"

@interface SRGitCommitItem : NSObject
@property (nonatomic, copy) NSString *sha1;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *date;
@property (nonatomic, copy) NSString *summary;
@end

@implementation SRGitCommitItem
@end

@interface SRGitCommitLogViewController ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<SRGitCommitItem *> *commits;
@end

@implementation SRGitCommitLogViewController

- (instancetype)initWithRepo:(SSBGitRepo *)repo {
    if (self = [super init]) {
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
    [self loadCommits];
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
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"CommitColumn"];
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
}

- (void)loadCommits {
    // Start from current refs and walk back
    NSDictionary *refs = [self.repo currentRefs];
    NSString *headSha1 = refs[@"refs/heads/main"] ?: refs.allValues.firstObject;
    if (!headSha1) return;
    
    NSMutableArray *commits = [NSMutableArray array];
    NSMutableSet *visited = [NSMutableSet set];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:headSha1];
    
    // Simple breadth-first walk (not exactly git log order, but sufficient for Phase 4)
    while (queue.count > 0 && commits.count < 100) {
        NSString *sha1 = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        if ([visited containsObject:sha1]) continue;
        [visited addObject:sha1];
        
        SSBGitObject *obj = [self.repo.objectStore objectForSHA1:sha1];
        if (obj && obj.type == SSBGitObjectTypeCommit) {
            NSString *content = [[NSString alloc] initWithData:obj.data encoding:NSUTF8StringEncoding];
            SRGitCommitItem *item = [[SRGitCommitItem alloc] init];
            item.sha1 = sha1;
            
            NSArray *lines = [content componentsSeparatedByString:@"\n"];
            for (NSString *line in lines) {
                if ([line hasPrefix:@"author "]) {
                    item.author = [line substringFromIndex:7];
                } else if (line.length == 0) {
                    // Message starts after first empty line
                    NSUInteger idx = [lines indexOfObject:line];
                    if (idx + 1 < lines.count) {
                        item.summary = lines[idx + 1];
                    }
                    break;
                } else if ([line hasPrefix:@"parent "]) {
                    [queue addObject:[line substringFromIndex:7]];
                }
            }
            [commits addObject:item];
        }
    }
    
    self.commits = commits;
    [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.commits.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"CommitCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
        cell.identifier = @"CommitCell";
        
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
    
    SRGitCommitItem *item = self.commits[row];
    cell.textField.stringValue = item.summary ?: @"(No message)";
    
    NSTextField *subTf = nil;
    for (NSView *v in cell.subviews) {
        if ([v.identifier isEqualToString:@"SubText"]) {
            subTf = (NSTextField *)v;
            break;
        }
    }
    
    subTf.stringValue = [NSString stringWithFormat:@"%@ - %@", [item.sha1 substringToIndex:7], item.author];
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0) return;
    
    SRGitCommitItem *item = self.commits[row];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRGitCommitSelectedNotification"
                                                        object:nil
                                                      userInfo:@{@"sha1": item.sha1}];
}

@end
