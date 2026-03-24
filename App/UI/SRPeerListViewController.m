#import "SRPeerListViewController.h"
#import "SSBFeedStore.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "SRPlatformLog.h"

static os_log_t peer_list_log;

@interface SRPeerCell : NSTableCellView
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSView *connectionStatusDot; // Online/Offline Indicator
@property (nonatomic, strong) NSTextField *idLabel; // Also serves as peer-name-label
@property (nonatomic, strong) NSView *followStatusDot;
@property (nonatomic, strong) NSProgressIndicator *syncProgressBar;
@property (nonatomic, strong) NSTextField *statusLabel; // Also serves as peer-sync-status-label
@end

@implementation SRPeerCell

- (void)viewDidChangeEffectiveAppearance {
    self.connectionStatusDot.layer.borderColor = [NSColor windowBackgroundColor].CGColor;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        _avatarView = [[NSView alloc] init];
        _avatarView.wantsLayer = YES;
        _avatarView.layer.cornerRadius = 20; // Half of 40
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_avatarView];

        _connectionStatusDot = [[NSView alloc] init];
        _connectionStatusDot.wantsLayer = YES;
        _connectionStatusDot.layer.cornerRadius = 5;
        _connectionStatusDot.layer.borderWidth = 1.5;
        _connectionStatusDot.layer.borderColor = [NSColor windowBackgroundColor].CGColor; // updated in viewDidChangeEffectiveAppearance
        _connectionStatusDot.translatesAutoresizingMaskIntoConstraints = NO;
        _connectionStatusDot.accessibilityIdentifier = @"peer-status-dot";
        [self addSubview:_connectionStatusDot];
        
        _idLabel = [NSTextField labelWithString:@""];
        _idLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _idLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _idLabel.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _idLabel.accessibilityIdentifier = @"peer-name-label";
        [self addSubview:_idLabel];
        
        _followStatusDot = [[NSView alloc] init];
        _followStatusDot.wantsLayer = YES;
        _followStatusDot.layer.cornerRadius = 3;
        _followStatusDot.translatesAutoresizingMaskIntoConstraints = NO;
        _followStatusDot.hidden = YES;
        [self addSubview:_followStatusDot];
        
        _syncProgressBar = [[NSProgressIndicator alloc] init];
        _syncProgressBar.style = NSProgressIndicatorStyleBar;
        _syncProgressBar.controlSize = NSControlSizeMini;
        _syncProgressBar.minValue = 0;
        _syncProgressBar.maxValue = 1.0;
        _syncProgressBar.doubleValue = 0;
        _syncProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
        _syncProgressBar.hidden = YES;
        [self addSubview:_syncProgressBar];
        
        _statusLabel = [NSTextField labelWithString:@""];
        _statusLabel.font = [NSFont systemFontOfSize:11];
        _statusLabel.textColor = [NSColor tertiaryLabelColor];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.accessibilityIdentifier = @"peer-sync-status-label";
        [self addSubview:_statusLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:40],
            [_avatarView.heightAnchor constraintEqualToConstant:40],

            [_connectionStatusDot.trailingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:2],
            [_connectionStatusDot.bottomAnchor constraintEqualToAnchor:_avatarView.bottomAnchor constant:2],
            [_connectionStatusDot.widthAnchor constraintEqualToConstant:10],
            [_connectionStatusDot.heightAnchor constraintEqualToConstant:10],
            
            [_idLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
            [_idLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-32],
            [_idLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            
            [_statusLabel.leadingAnchor constraintEqualToAnchor:_idLabel.leadingAnchor],
            [_statusLabel.topAnchor constraintEqualToAnchor:_idLabel.bottomAnchor constant:2],
            
            [_syncProgressBar.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:8],
            [_syncProgressBar.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
            [_syncProgressBar.widthAnchor constraintEqualToConstant:60],
            [_syncProgressBar.heightAnchor constraintEqualToConstant:4],
            
            [_followStatusDot.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *peerSyncProgress;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *peerSyncStatus;
@property (nonatomic, strong) NSMutableArray *observerTokens;
@end

@implementation SRPeerListViewController

+ (void)initialize {
    if (self == [SRPeerListViewController class]) {
        peer_list_log = os_log_create("com.scuttlebutt.app", "PeerList");
    }
}

- (void)viewDidChangeEffectiveAppearance {
    self.view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
}

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    NSLayoutGuide *safeArea = view.safeAreaLayoutGuide;
    
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
        [self.headerLabel.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:12],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [self.headerLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.headerLabel.bottomAnchor constant:8],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor]
    ]];
    
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.rowHeight = 52; // Increased for larger avatars
    [self.tableView setAccessibilityIdentifier:@"peer-list-table"];
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
    [self.emptyLabel setAccessibilityIdentifier:@"peer-list-empty"];
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
    
    self.peerSyncProgress = [NSMutableDictionary dictionary];
    self.peerSyncStatus = [NSMutableDictionary dictionary];
    self.observerTokens = [NSMutableArray array];
    
    __weak typeof(self) weakSelf = self;
    id syncToken = [[NSNotificationCenter defaultCenter] addObserverForName:SRRoomSyncStatusChangedNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification * _Nonnull note) {
        [weakSelf syncStatusChanged:note];
    }];
    [self.observerTokens addObject:syncToken];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(endpointsDidUpdate:)
                                                 name:SRRoomManagerDidUpdateEndpointsNotification
                                               object:nil];

    if (self.roomHost.length == 0) {
        [self loadPeers];
    }
}

- (void)loadPeers {
    NSMutableSet *allPeers = [NSMutableSet setWithArray:[[SSBFeedStore sharedStore] allKnownAuthors]];
    
    if (self.roomHost.length > 0) {
        NSArray *endpoints = [SRRoomManager sharedManager].roomEndpoints[self.roomHost];
        if (endpoints) {
            [allPeers addObjectsFromArray:endpoints];
        }
    }
    
    [self updatePeers:[allPeers allObjects]];
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[SRRoomManagerEndpointsHostKey];
    NSArray *list = userInfo[SRRoomManagerEndpointsListKey];
    
    if (self.roomHost.length > 0 && [host isEqualToString:self.roomHost]) {
        NSMutableSet *allPeers = [NSMutableSet setWithArray:[[SSBFeedStore sharedStore] allKnownAuthors]];
        if (list) {
            [allPeers addObjectsFromArray:list];
        }
        [self updatePeers:[allPeers allObjects]];
    }
}

- (void)dealloc {
    os_log_info(peer_list_log, "dealloc called for %{public}@", self.roomHost);
    for (id token in self.observerTokens) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
}

- (void)setRoomHost:(NSString *)roomHost {
    if ((_roomHost == roomHost) || [_roomHost isEqualToString:roomHost]) {
        return;
    }

    _roomHost = [roomHost copy];
    [self loadPeers];
    [self reloadSyncStateFromManager];
}

- (void)reloadSyncStateFromManager {
    if (self.roomHost.length > 0) {
        self.peerSyncProgress = [[[SRRoomManager sharedManager] peerSyncProgressForHost:self.roomHost] mutableCopy];
        self.peerSyncStatus = [[[SRRoomManager sharedManager] peerSyncStatesForHost:self.roomHost] mutableCopy];
    } else {
        self.peerSyncProgress = [NSMutableDictionary dictionary];
        self.peerSyncStatus = [NSMutableDictionary dictionary];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)syncStatusChanged:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[SRRoomSyncStatusHostKey];
    NSString *author = userInfo[SRRoomSyncStatusAuthorKey];
    NSString *peerID = userInfo[SRRoomSyncStatusPeerKey];
    NSString *status = userInfo[SRRoomSyncStatusKey];
    float progress = [userInfo[SRRoomSyncStatusProgressKey] floatValue];

    if (self.roomHost.length == 0 || ![host isEqualToString:self.roomHost]) {
        return;
    }
    
    NSString *key = peerID ?: author;
    if (key) {
        os_log_debug(peer_list_log, "Sync status updated for %{public}@: %{public}@ (%f)", key, status, progress);
        self.peerSyncProgress[key] = @(progress);
        self.peerSyncStatus[key] = status;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger row = [self.peers indexOfObject:key];
            if (row != NSNotFound) {
                [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            }
        });
    }
}

- (void)followAction:(id)sender {
    [self updateFollowStatus:YES];
}

- (void)unfollowAction:(id)sender {
    [self updateFollowStatus:NO];
}

- (void)blockAction:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0 || (NSUInteger)row >= self.peers.count) return;
    
    NSString *peerID = self.peers[row];
    BOOL isBlocked = [[SSBFeedStore sharedStore] isBlocked:peerID];
    
    // For now we don't have a delegate method for blocking directly in this interface
    // but we can post a notification or add a delegate method. Let's add it via a notification or delegate.
    // To keep it simple, we can just let the user block from the Profile View. But let's add it to the delegate anyway.
    if ([self.delegate respondsToSelector:@selector(peerListViewController:didRequestBlock:blocking:)]) {
        [self.delegate peerListViewController:self didRequestBlock:peerID blocking:!isBlocked];
    }
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
    os_log_info(peer_list_log, "Updating with %lu peers", (unsigned long)peers.count);
    self.peers = [peers copy];
    self.emptyLabel.hidden = (peers.count > 0);
    [self.progressIndicator stopAnimation:nil];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
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
        os_log_debug(peer_list_log, "Rendering row %ld: %{public}@", (long)row, peerID);
        cell.idLabel.stringValue = [[SSBFeedStore sharedStore] displayNameForAuthor:peerID];

        // Cell-level accessibility identifier for XCTest automation
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"peer-cell-%@", peerID];
        
        NSUInteger hash = [peerID hash];
        cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.65 alpha:1.0].CGColor;
        
        if ([[SSBFeedStore sharedStore] isFollowing:peerID]) {
            cell.followStatusDot.hidden = NO;
            cell.followStatusDot.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
        } else {
            cell.followStatusDot.hidden = YES;
        }
        
        float progress = [self.peerSyncProgress[peerID] floatValue];
        NSString *status = self.peerSyncStatus[peerID];
        
        if (status) {
            cell.statusLabel.stringValue = status;
            cell.statusLabel.hidden = NO;
            
            // Show progress bar for Receiving and Sending states
            BOOL isSyncing = [status containsString:@"Receiving"] || [status containsString:@"Sending"];
            if (isSyncing && progress < 1.0) {
                cell.syncProgressBar.hidden = NO;
                cell.syncProgressBar.doubleValue = progress;
            } else {
                cell.syncProgressBar.hidden = YES;
            }
            
            if ([status isEqualToString:@"Ready"]) {
                cell.statusLabel.textColor = [NSColor systemGreenColor];
                cell.connectionStatusDot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
            } else if (isSyncing) {
                cell.statusLabel.textColor = [NSColor systemBlueColor];
                cell.connectionStatusDot.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
            } else {
                cell.statusLabel.textColor = [NSColor tertiaryLabelColor];
                cell.connectionStatusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
            }
        } else {
            cell.statusLabel.hidden = YES;
            cell.syncProgressBar.hidden = YES;
            cell.connectionStatusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
        }
    }
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && (NSUInteger)row < self.peers.count) {
        NSString *peerID = self.peers[row];
        os_log_info(peer_list_log, "Peer selected: %{public}@", peerID);
        if ([self.delegate respondsToSelector:@selector(peerListViewController:didSelectPeer:)]) {
            [self.delegate peerListViewController:self didSelectPeer:peerID];
        }
    }
}

@end
