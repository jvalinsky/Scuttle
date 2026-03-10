#import "SRPeerListViewController.h"

@interface SRPeerCell : NSTableCellView
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *idLabel;
@end

@implementation SRPeerCell
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _avatarView = [[NSView alloc] init];
        _avatarView.wantsLayer = YES;
        _avatarView.layer.cornerRadius = 14;
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_avatarView];
        
        _idLabel = [NSTextField labelWithString:@""];
        _idLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
        _idLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _idLabel.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_idLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:28],
            [_avatarView.heightAnchor constraintEqualToConstant:28],
            
            [_idLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
            [_idLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_idLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    return self;
}
@end

@interface SRPeerListViewController ()
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, copy) NSArray<NSString *> *peers;
@end

@implementation SRPeerListViewController

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.scrollView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];
    
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.rowHeight = 44;
    self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    
    // In macOS 11+, we should set the style.
    if (@available(macOS 11.0, *)) {
        self.tableView.style = NSTableViewStyleSourceList;
    }
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"PeerColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.tableView addTableColumn:column];
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    self.scrollView.documentView = self.tableView;
}

- (void)updatePeers:(NSArray<NSString *> *)peers {
    NSLog(@"[PeerList] Updating with %lu peers: %@", (unsigned long)peers.count, peers);
    self.peers = [peers copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    NSLog(@"[PeerList] DEBUG: numberOfRowsInTableView called - returning %lu", (unsigned long)self.peers.count);
    return self.peers.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    SRPeerCell *cell = (SRPeerCell *)[tableView makeViewWithIdentifier:@"PeerCell" owner:self];
    if (!cell) {
        cell = [[SRPeerCell alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 44)];
        cell.identifier = @"PeerCell";
    }
    
    if (row < self.peers.count) {
        NSString *peerID = self.peers[row];
        NSLog(@"[PeerList] Rendering row %ld: %@", (long)row, peerID);
        cell.idLabel.stringValue = peerID;
        
        NSUInteger hash = [peerID hash];
        cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
    }
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && (NSUInteger)row < self.peers.count) {
        NSString *peerID = self.peers[row];
        NSLog(@"[PeerList] Peer selected: %@", peerID);
        if ([self.delegate respondsToSelector:@selector(peerListViewController:didSelectPeer:)]) {
            [self.delegate peerListViewController:self didSelectPeer:peerID];
        }
    }
}

@end