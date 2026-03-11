#import "SRPeerListViewController.h"
#import "SSBFeedStore.h"

@interface SRPeerCell : NSTableCellView
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *idLabel;
@property (nonatomic, strong) NSView *followStatusDot;
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
        
        _followStatusDot = [[NSView alloc] init];
        _followStatusDot.wantsLayer = YES;
        _followStatusDot.layer.cornerRadius = 3;
        _followStatusDot.translatesAutoresizingMaskIntoConstraints = NO;
        _followStatusDot.hidden = YES;
        [self addSubview:_followStatusDot];
        
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:28],
            [_avatarView.heightAnchor constraintEqualToConstant:28],
            
            [_idLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
            [_idLabel.trailingAnchor constraintEqualToAnchor:_followStatusDot.leadingAnchor constant:-8],
            [_idLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            
            [_followStatusDot.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_followStatusDot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_followStatusDot.widthAnchor constraintEqualToConstant:6],
            [_followStatusDot.heightAnchor constraintEqualToConstant:6]
        ]];
    }
    return self;
}
@end

@interface SRPeerListViewController ()
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, copy) NSArray<NSString *> *peers;
@property (nonatomic, strong) NSTextField *headerLabel;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@end

@implementation SRPeerListViewController

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    
    self.headerLabel = [NSTextField labelWithString:@"PEERS"];
    self.headerLabel.font = [NSFont boldSystemFontOfSize:11];
    self.headerLabel.textColor = [NSColor secondaryLabelColor];
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.headerLabel];

    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.scrollView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.headerLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:40],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [self.headerLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.headerLabel.bottomAnchor constant:8],
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
    
    self.tableView.style = NSTableViewStyleSourceList;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"PeerColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.tableView addTableColumn:column];
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Follow" action:@selector(followAction:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Unfollow" action:@selector(unfollowAction:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Block" action:@selector(blockAction:) keyEquivalent:@""];
    self.tableView.menu = menu;
    
    self.scrollView.documentView = self.tableView;
    
    self.emptyLabel = [NSTextField labelWithString:@"No peers in this room"];
    self.emptyLabel.font = [NSFont systemFontOfSize:13];
    self.emptyLabel.textColor = [NSColor tertiaryLabelColor];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    
    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.controlSize = NSControlSizeSmall;
    self.progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.view addSubview:self.progressIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        
        [self.progressIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.progressIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)followAction:(id)sender {
    [self updateFollowStatus:YES];
}

- (void)unfollowAction:(id)sender {
    [self updateFollowStatus:NO];
}

- (void)blockAction:(id)sender {
    // TODO: Implement blocking
}

- (void)updateFollowStatus:(BOOL)following {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0 || (NSUInteger)row >= self.peers.count) return;
    
    NSString *peerID = self.peers[row];
    if (following) {
        if ([self.delegate respondsToSelector:@selector(peerListViewController:didRequestFollow:)]) {
            [self.delegate peerListViewController:self didRequestFollow:peerID];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(peerListViewController:didRequestUnfollow:)]) {
            [self.delegate peerListViewController:self didRequestUnfollow:peerID];
        }
    }
}

- (void)updatePeers:(NSArray<NSString *> *)peers {
    NSLog(@"[PeerList] Updating with %lu peers: %@", (unsigned long)peers.count, peers);
    self.peers = [peers copy];
    self.emptyLabel.hidden = (peers.count > 0);
    [self.progressIndicator stopAnimation:nil];
    
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
        cell.idLabel.stringValue = [[SSBFeedStore sharedStore] displayNameForAuthor:peerID];
        
        NSUInteger hash = [peerID hash];
        cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
        
        if ([[SSBFeedStore sharedStore] isFollowing:peerID]) {
            cell.followStatusDot.hidden = NO;
            cell.followStatusDot.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
        } else {
            cell.followStatusDot.hidden = YES;
        }
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