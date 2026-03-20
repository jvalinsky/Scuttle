#import "SRPeerListViewController.h"
#import "SSBFeedStore.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "SRPlatformLog.h"

static os_log_t peer_list_log;

@interface SRPeerCell : NSTableCellView
@property (nonatomic, strong) NSView *avatarView;
@property (nonatomic, strong) NSTextField *idLabel;
@property (nonatomic, strong) NSView *followStatusDot;
@property (nonatomic, strong) NSProgressIndicator *syncProgressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
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
        _statusLabel.font = [NSFont systemFontOfSize:9];
        _statusLabel.textColor = [NSColor tertiaryLabelColor];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_statusLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:28],
            [_avatarView.heightAnchor constraintEqualToConstant:28],
            
            [_idLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
            [_idLabel.trailingAnchor constraintEqualToAnchor:_followStatusDot.leadingAnchor constant:-8],
            [_idLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            
            [_statusLabel.leadingAnchor constraintEqualToAnchor:_idLabel.leadingAnchor],
            [_statusLabel.topAnchor constraintEqualToAnchor:_idLabel.bottomAnchor constant:0],
            
            [_syncProgressBar.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:6],
            [_syncProgressBar.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
            [_syncProgressBar.widthAnchor constraintEqualToConstant:60],
            [_syncProgressBar.heightAnchor constraintEqualToConstant:4],
            
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *peerSyncProgress;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *peerSyncStatus;
@end

@implementation SRPeerListViewController

+ (void)initialize {
    if (self == [SRPeerListViewController class]) {
        peer_list_log = os_log_create("com.scuttlebutt.app", "PeerList");
    }
}

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
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
    
    self.peerSyncProgress = [NSMutableDictionary dictionary];
    self.peerSyncStatus = [NSMutableDictionary dictionary];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncStatusChanged:) name:SRRoomSyncStatusChangedNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setRoomHost:(NSString *)roomHost {
    if ((_roomHost == roomHost) || [_roomHost isEqualToString:roomHost]) {
        return;
    }

    _roomHost = [roomHost copy];
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
    NSString *status = userInfo[SRRoomSyncStatusKey];
    float progress = [userInfo[SRRoomSyncStatusProgressKey] floatValue];

    if (self.roomHost.length == 0 || ![host isEqualToString:self.roomHost]) {
        return;
    }
    
    if (author) {
        os_log_debug(peer_list_log, "Sync status updated for %{public}@: %{public}@ (%f)", author, status, progress);
        self.peerSyncProgress[author] = @(progress);
        self.peerSyncStatus[author] = status;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger row = [self.peers indexOfObject:author];
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
    os_log_info(peer_list_log, "Updating with %lu peers: %{public}@", (unsigned long)peers.count, peers);
    self.peers = [peers copy];
    self.emptyLabel.hidden = (peers.count > 0);
    [self.progressIndicator stopAnimation:nil];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    os_log_debug(peer_list_log, "numberOfRowsInTableView called - returning %lu", (unsigned long)self.peers.count);
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
        
        NSUInteger hash = [peerID hash];
        cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
        
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
            } else {
                cell.statusLabel.textColor = [NSColor tertiaryLabelColor];
            }
        } else {
            cell.statusLabel.hidden = YES;
            cell.syncProgressBar.hidden = YES;
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
