#import "SRSidebarViewController.h"
#import "SRSidebarItem.h"
#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "../Logic/SRQRUtils.h"
#import "SRMainSplitViewController.h"
#import "SRStyle.h"
#import "../../Sources/SSBBamboo.h"
#import "../../Sources/SSBFeedStore.h"
#import "SRPlatformLog.h"

static os_log_t sidebar_log;

@interface SRSidebarViewController () <SRScannerDelegate>
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) SRProfileHeaderView *profileHeader;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSArray<SSBMessage *> *gitRepos;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSButton *joinButton;
@property (nonatomic, strong) NSButton *scanButton;
@property (nonatomic, strong) NSView *syncStatusContainer;
@property (nonatomic, strong) NSProgressIndicator *syncProgress;
@property (nonatomic, strong) NSTextField *syncLabel;
@property (nonatomic, copy, nullable) NSString *selectedRoomHost;
@property (nonatomic, strong) NSMutableArray<SRSidebarItem *> *sections;
@end

@implementation SRSidebarViewController

+ (void)initialize {
    if (self == [SRSidebarViewController class]) {
        sidebar_log = os_log_create("com.scuttlebutt.app", "Sidebar");
    }
}

- (void)loadView {
    self.effectView = [[NSVisualEffectView alloc] init];
    self.effectView.material = NSVisualEffectMaterialSidebar;
    self.effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.effectView.state = NSVisualEffectStateActive;
    self.view = self.effectView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sections = [NSMutableArray array];
    [self setupUI];
    [self loadGitRepos];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(roomsDidUpdate:)
                                                 name:SRRoomManagerDidUpdateRoomsNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusDidUpdate:)
                                                 name:SRRoomManagerConnectionStatusChangedNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(endpointsDidUpdate:)
                                                 name:SRRoomManagerDidUpdateEndpointsNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(syncStatusDidUpdate:)
                                                 name:SRRoomSyncStatusChangedNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(roomSelected:)
                                                 name:SRRoomManagerRoomSelectedNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gitReposDidUpdate:)
                                                 name:SRGitRepoCreatedNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gitReposDidUpdate:)
                                                 name:SRNewMessageNotification
                                               object:nil];
}

- (void)gitReposDidUpdate:(NSNotification *)notification {
    [self loadGitRepos];
}

- (void)loadGitRepos {
    self.gitRepos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
    });
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
    });
}

- (void)statusDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
    });
}

- (void)syncStatusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[SRRoomSyncStatusHostKey];
    if (self.selectedRoomHost.length == 0 || ![host isEqualToString:self.selectedRoomHost]) {
        return;
    }

    [self applySyncStatus:userInfo[SRRoomSyncStatusKey] progress:[userInfo[SRRoomSyncStatusProgressKey] floatValue]];
}

- (void)roomsDidUpdate:(NSNotification *)notification {
    os_log_info(sidebar_log, "Rooms updated notification received");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
        // Auto-select first room if nothing is selected and rooms exist
        if ([SRRoomManager sharedManager].rooms.count > 0) {
            SRSidebarItem *roomsSection = self.sections.count > 0 ? self.sections[0] : nil;
            if (roomsSection && roomsSection.children.count > 0) {
                SRSidebarItem *firstRoom = roomsSection.children[0];
                NSInteger row = [self.outlineView rowForItem:firstRoom];
                if (row >= 0 && self.outlineView.selectedRow < 0) {
                    os_log_info(sidebar_log, "Auto-selecting first room");
                    [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
                }
            }
        }
    });
}

- (void)roomSelected:(NSNotification *)notification {
    RoomConfig *room = notification.userInfo[SRRoomManagerRoomSelectedKey];
    self.selectedRoomHost = room.host;
    [self refreshSelectedRoomSyncStatus];
}

#pragma mark - Rebuild Sections

- (void)_rebuildSections {
    [self.sections removeAllObjects];

    // TOP section for Home/Global
    SRSidebarItem *topSection = [SRSidebarItem sectionItemWithTitle:@"SSB"];
    SRSidebarItem *homeItem = [SRSidebarItem roomItemWithTitle:@"Home" representedObject:@"home"];
    [topSection.children addObject:homeItem];
    
    SRSidebarItem *channelsItem = [SRSidebarItem roomItemWithTitle:@"Channels" representedObject:@"channels"];
    [topSection.children addObject:channelsItem];
    
    SRSidebarItem *reposItem = [SRSidebarItem roomItemWithTitle:@"Repositories" representedObject:@"repos"];
    [topSection.children addObject:reposItem];
    
    SRSidebarItem *peersItem = [SRSidebarItem peerItemWithTitle:@"Peers" representedObject:@"peers"];
    [topSection.children addObject:peersItem];
    
    [self.sections addObject:topSection];

    // ROOMS section
    SRSidebarItem *roomsSection = [SRSidebarItem sectionItemWithTitle:@"ROOMS"];
    for (RoomConfig *room in [SRRoomManager sharedManager].rooms) {
        SRSidebarItem *roomItem = [SRSidebarItem roomItemWithTitle:room.host representedObject:room];
        [roomsSection.children addObject:roomItem];
    }
    [self.sections addObject:roomsSection];

    // CHANNELS section (empty for now; populate from feed store when available)
    SRSidebarItem *channelsSection = [SRSidebarItem sectionItemWithTitle:@"CHANNELS"];
    [self.sections addObject:channelsSection];

    // REPOSITORIES section
    SRSidebarItem *reposSection = [SRSidebarItem sectionItemWithTitle:@"REPOSITORIES"];
    for (SSBMessage *repoMsg in self.gitRepos) {
        NSString *repoName = repoMsg.content[@"name"] ?: @"Unnamed Repo";
        SRSidebarItem *repoItem = [SRSidebarItem repoItemWithTitle:repoName representedObject:repoMsg];
        [reposSection.children addObject:repoItem];
    }
    [self.sections addObject:reposSection];

    [self.outlineView reloadData];

    // Expand all sections
    for (SRSidebarItem *section in self.sections) {
        [self.outlineView expandItem:section];
    }
}

#pragma mark - Setup UI

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileHeader = [[SRProfileHeaderView alloc] initWithFrame:NSZeroRect];
    self.profileHeader.compactMode = YES;
    self.profileHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.profileHeader];

    [self.view addSubview:self.scrollView];

    // Create the outline view
    self.outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    self.outlineView.headerView = nil;
    self.outlineView.backgroundColor = [NSColor clearColor];
    self.outlineView.style = NSTableViewStyleSourceList;
    self.outlineView.rowSizeStyle = NSTableViewRowSizeStyleMedium;
    self.outlineView.floatsGroupRows = NO;
    self.outlineView.allowsEmptySelection = YES;
    self.outlineView.indentationPerLevel = 12;
    self.outlineView.delegate = self;
    self.outlineView.dataSource = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"MainColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.outlineView addTableColumn:column];
    self.outlineView.outlineTableColumn = column;

    // Context menu (acts on clicked room item)
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Disconnect" action:@selector(disconnectAction:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Remove Room" action:@selector(removeRoomAction:) keyEquivalent:@""];
    self.outlineView.menu = menu;

    self.scrollView.documentView = self.outlineView;

    self.joinButton = [NSButton buttonWithTitle:@"Join..." target:self action:@selector(joinRoomAction:)];
    self.joinButton.bezelStyle = NSBezelStyleRounded;
    self.joinButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.joinButton];

    self.scanButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"qrcode.viewfinder" accessibilityDescription:@"Scan Sneakernet QR"] target:self action:@selector(scanQRAction:)];
    self.scanButton.bezelStyle = NSBezelStyleRounded;
    self.scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scanButton];

    self.syncStatusContainer = [[NSView alloc] init];
    self.syncStatusContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.syncStatusContainer.hidden = YES;
    [self.view addSubview:self.syncStatusContainer];

    self.syncProgress = [[NSProgressIndicator alloc] init];
    self.syncProgress.style = NSProgressIndicatorStyleSpinning;
    self.syncProgress.controlSize = NSControlSizeSmall;
    self.syncProgress.displayedWhenStopped = NO;
    self.syncProgress.translatesAutoresizingMaskIntoConstraints = NO;
    [self.syncStatusContainer addSubview:self.syncProgress];

    self.syncLabel = [NSTextField labelWithString:@"Idle"];
    self.syncLabel.font = [NSFont systemFontOfSize:10];
    self.syncLabel.textColor = [NSColor secondaryLabelColor];
    self.syncLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.syncLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.syncStatusContainer addSubview:self.syncLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.profileHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.profileHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.profileHeader.heightAnchor constraintEqualToConstant:64],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.profileHeader.bottomAnchor constant:4],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.joinButton.topAnchor constant:-12],

        [self.joinButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.joinButton.bottomAnchor constraintEqualToAnchor:self.syncStatusContainer.topAnchor constant:-8],

        [self.scanButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.scanButton.centerYAnchor constraintEqualToAnchor:self.joinButton.centerYAnchor],
        [self.scanButton.leadingAnchor constraintEqualToAnchor:self.joinButton.trailingAnchor constant:8],

        [self.syncStatusContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.syncStatusContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.syncStatusContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12],
        [self.syncStatusContainer.heightAnchor constraintEqualToConstant:20],

        [self.syncProgress.leadingAnchor constraintEqualToAnchor:self.syncStatusContainer.leadingAnchor],
        [self.syncProgress.centerYAnchor constraintEqualToAnchor:self.syncStatusContainer.centerYAnchor],
        [self.syncProgress.widthAnchor constraintEqualToConstant:16],
        [self.syncProgress.heightAnchor constraintEqualToConstant:16],

        [self.syncLabel.leadingAnchor constraintEqualToAnchor:self.syncProgress.trailingAnchor constant:6],
        [self.syncLabel.trailingAnchor constraintEqualToAnchor:self.syncStatusContainer.trailingAnchor],
        [self.syncLabel.centerYAnchor constraintEqualToAnchor:self.syncStatusContainer.centerYAnchor]
    ]];

    [self.profileHeader.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor].active = YES;

    // Initial data load
    [self _rebuildSections];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (item == nil) {
        return (NSInteger)self.sections.count;
    }
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    return (NSInteger)sidebarItem.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (item == nil) {
        return self.sections[(NSUInteger)index];
    }
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    return sidebarItem.children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    return sidebarItem.expandable;
}

#pragma mark - NSOutlineViewDelegate

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    return sidebarItem.type == SRSidebarItemTypeSection;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;

    if (sidebarItem.type == SRSidebarItemTypeSection) {
        NSTextField *label = [outlineView makeViewWithIdentifier:@"SectionHeader" owner:self];
        if (!label) {
            label = [NSTextField labelWithString:@""];
            label.identifier = @"SectionHeader";
            label.font = [SRStyle caption2Font];
            label.textColor = [NSColor tertiaryLabelColor];
        }
        label.stringValue = sidebarItem.title.uppercaseString;
        return label;
    }

    if (sidebarItem.type == SRSidebarItemTypeRoom || sidebarItem.type == SRSidebarItemTypePeer) {
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"RoomCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 36)];
            cell.identifier = @"RoomCell";

            // SF Symbol icon
            NSImageView *iconView = [[NSImageView alloc] init];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.identifier = @"IconView";
            [cell addSubview:iconView];

            // Connection status dot
            NSView *dotView = [[NSView alloc] init];
            dotView.translatesAutoresizingMaskIntoConstraints = NO;
            dotView.wantsLayer = YES;
            dotView.layer.cornerRadius = 4.0;
            dotView.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
            dotView.identifier = @"StatusDot";
            [cell addSubview:dotView];

            // Room name label
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [SRStyle bodyFont];
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;

            [NSLayoutConstraint activateConstraints:@[
                [iconView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [iconView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [iconView.widthAnchor constraintEqualToConstant:16],
                [iconView.heightAnchor constraintEqualToConstant:16],

                [dotView.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:4],
                [dotView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [dotView.widthAnchor constraintEqualToConstant:8],
                [dotView.heightAnchor constraintEqualToConstant:8],

                [textField.leadingAnchor constraintEqualToAnchor:dotView.trailingAnchor constant:6],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }

        cell.textField.stringValue = sidebarItem.title;

        // Update icon and connection status dot color
        for (NSView *subview in cell.subviews) {
            if ([subview.identifier isEqualToString:@"IconView"]) {
                NSImageView *iv = (NSImageView *)subview;
                NSString *symbolName = @"network";
                if ([sidebarItem.representedObject isEqual:@"home"]) symbolName = @"house";
                else if ([sidebarItem.representedObject isEqual:@"channels"]) symbolName = @"number";
                else if ([sidebarItem.representedObject isEqual:@"repos"]) symbolName = @"folder";
                else if ([sidebarItem.representedObject isEqual:@"peers"]) symbolName = @"person.2";
                
                NSImage *icon = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:sidebarItem.title];
                iv.image = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular]];
            }
            if ([subview.identifier isEqualToString:@"StatusDot"]) {
                if ([sidebarItem.representedObject isKindOfClass:[RoomConfig class]]) {
                    subview.hidden = NO;
                    RoomConfig *room = (RoomConfig *)sidebarItem.representedObject;
                    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
                    NSColor *dotColor = client.isConnected ? [NSColor systemGreenColor] : [NSColor systemGrayColor];
                    subview.layer.backgroundColor = dotColor.CGColor;
                } else {
                    subview.hidden = YES;
                }
            }
        }

        return cell;
    }

    if (sidebarItem.type == SRSidebarItemTypeChannel) {
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"ChannelCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 36)];
            cell.identifier = @"ChannelCell";

            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [SRStyle bodyFont];
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;

            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = [NSString stringWithFormat:@"# %@", sidebarItem.title];
        return cell;
    }

    if (sidebarItem.type == SRSidebarItemTypeRepo) {
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"RepoCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 36)];
            cell.identifier = @"RepoCell";

            // SF Symbol icon for code/repo
            NSImageView *iconView = [[NSImageView alloc] init];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;

            // Determine icon based on title heuristics
            NSImage *repoIcon = nil;
            NSString *title = sidebarItem.title.lowercaseString;
            if ([title containsString:@"git"]) {
                repoIcon = [NSImage imageWithSystemSymbolName:@"chevron.left.forwardslash.chevron.right" accessibilityDescription:@"Repository"];
            } else {
                // Leave icon nil if no match
            }
            if (repoIcon) {
                repoIcon = [repoIcon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular]];
                iconView.image = repoIcon;
            }
            iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
            [cell addSubview:iconView];

            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [SRStyle bodyFont];
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;

            [NSLayoutConstraint activateConstraints:@[
                [iconView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [iconView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [iconView.widthAnchor constraintEqualToConstant:16],
                [iconView.heightAnchor constraintEqualToConstant:16],

                [textField.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:6],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = sidebarItem.title;
        return cell;
    }

    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    // Only select leaf items (non-expandable)
    return sidebarItem.expandable == NO;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    SRSidebarItem *sidebarItem = (SRSidebarItem *)item;
    return sidebarItem.type == SRSidebarItemTypeSection ? 22.0 : 36.0;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.outlineView.selectedRow;
    if (row < 0) return;

    SRSidebarItem *item = [self.outlineView itemAtRow:row];
    if (!item) return;

    if (item.type == SRSidebarItemTypeRoom) {
        if ([item.representedObject isKindOfClass:[NSString class]]) {
            // General destination (Home/Global)
            if (self.delegate && [self.delegate respondsToSelector:@selector(sidebarViewController:didSelectDestination:)]) {
                [self.delegate sidebarViewController:self didSelectDestination:(NSString *)item.representedObject];
            }
            return;
        }

        RoomConfig *room = (RoomConfig *)item.representedObject;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification
                                                            object:nil
                                                          userInfo:@{SRRoomManagerRoomSelectedKey: room}];
        return;
    }

    if (item.type == SRSidebarItemTypeRepo) {
        SSBMessage *repoMsg = (SSBMessage *)item.representedObject;
        [[NSNotificationCenter defaultCenter] postNotificationName:SRGitRepoSelectedNotification
                                                            object:nil
                                                          userInfo:@{SRGitRepoSelectedKey: repoMsg.key}];
        return;
    }

    if (item.type == SRSidebarItemTypePeer) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(sidebarViewController:didSelectDestination:)]) {
            [self.delegate sidebarViewController:self didSelectDestination:(NSString *)item.representedObject];
        }
        return;
    }
}

#pragma mark - Context Menu Actions

- (void)removeRoomAction:(id)sender {
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0) return;

    SRSidebarItem *item = [self.outlineView itemAtRow:row];
    if (!item || item.type != SRSidebarItemTypeRoom) return;

    RoomConfig *room = (RoomConfig *)item.representedObject;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Remove %@?", room.host];
    alert.informativeText = @"You will be disconnected from this room.";
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SRRoomManager sharedManager] removeRoom:room];
        [self _rebuildSections];
    }
}

- (void)disconnectAction:(id)sender {
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0) return;

    SRSidebarItem *item = [self.outlineView itemAtRow:row];
    if (!item || item.type != SRSidebarItemTypeRoom) return;

    RoomConfig *room = (RoomConfig *)item.representedObject;
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
    [client disconnect];
    [self _rebuildSections];
}

#pragma mark - Actions

- (void)scanQRAction:(id)sender {
    SRScannerViewController *scanner = [[SRScannerViewController alloc] init];
    scanner.delegate = self;
    [self presentViewControllerAsSheet:scanner];
}

- (void)scannerDidScanString:(NSString *)string {
    if ([string hasPrefix:@"ssb:bamboo-proof:"]) {
        NSString *base64 = [string substringFromIndex:17];
        NSData *proofData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        if (!proofData) return;

        SSBBambooProof *proof = [SSBBamboo deserializeProof:proofData];
        if (!proof) return;

        NSError *error;
        if ([SSBBamboo verifyProof:proof error:&error]) {
            // Success! We have an authenticated message from a "sneakernet" exchange.
            // Import it into our store.
            SSBMessage *msg = [[SSBMessage alloc] init];
            msg.author = [SSBBFE sigilStringFromBFE:proof.authorPubKey];
            msg.valueJSON = proof.targetMessage;
            msg.feedFormat = SSBBFEFeedFormatBamboo;

            // Extract some metadata for the object
            // (In a real app, we'd use the codec to fully parse)

            if ([[SSBFeedStore sharedStore] appendMessage:msg error:&error]) {
                NSAlert *success = [[NSAlert alloc] init];
                success.messageText = @"Message Verified & Imported";
                success.informativeText = [NSString stringWithFormat:@"Successfully imported message from %@ via sneakernet.", msg.author];
                [success runModal];
            } else {
                NSAlert *err = [[NSAlert alloc] init];
                err.messageText = @"Import Failed";
                err.informativeText = error.localizedDescription;
                [err runModal];
            }
        } else {
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Verification Failed";
            err.informativeText = error.localizedDescription;
            [err runModal];
        }
    } else if ([string hasPrefix:@"ssb:room-invite:"] || [string hasPrefix:@"https://"]) {
        // Handle room invites via QR too!
        [[SRRoomManager sharedManager] joinRoomWithInvite:string completion:^(BOOL success, NSError * _Nullable error) {
            // ... handled by notifications usually
        }];
    }
}

- (void)joinRoomAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Join SSB Room";
    alert.informativeText = @"Enter an SSB Room invite code (ssb:room-invite:...) or an HTTPS join link.";
    [alert addButtonWithTitle:@"Join"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
    input.placeholderString = @"https://example.com/join?invite=...";
    input.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    input.cell.usesSingleLineMode = YES;
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *invite = input.stringValue;
        if (invite.length == 0) {
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Invalid Invite";
            err.informativeText = @"Please enter an invite code.";
            [err runModal];
            return;
        }

        // Show joining indicator
        self.syncLabel.stringValue = @"Joining room...";
        self.syncStatusContainer.hidden = NO;
        [self.syncProgress startAnimation:nil];

        [[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.syncProgress stopAnimation:nil];
                self.syncStatusContainer.hidden = YES;

                if (!success) {
                    NSAlert *err = [[NSAlert alloc] init];
                    err.messageText = @"Join Failed";
                    err.informativeText = error.localizedDescription ?: @"Unknown error";
                    [err runModal];
                } else {
                    // Show success briefly
                    self.syncLabel.stringValue = @"Joined room!";
                    self.syncStatusContainer.hidden = NO;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        self.syncStatusContainer.hidden = YES;
                    });
                    [self _rebuildSections];
                }
            });
        }];
    }
}

#pragma mark - Sync Status

- (void)refreshSelectedRoomSyncStatus {
    NSString *status = self.selectedRoomHost.length > 0 ? [[SRRoomManager sharedManager] syncStatusForHost:self.selectedRoomHost] : nil;
    float progress = self.selectedRoomHost.length > 0 ? [[SRRoomManager sharedManager] syncProgressForHost:self.selectedRoomHost] : 1.0f;
    [self applySyncStatus:status progress:progress];
}

- (void)applySyncStatus:(nullable NSString *)status progress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *resolvedStatus = status ?: @"Idle";
        self.syncLabel.stringValue = resolvedStatus;
        if (progress < 1.0f && progress >= 0.0f) {
            [self.syncProgress startAnimation:nil];
            self.syncStatusContainer.hidden = NO;
        } else {
            [self.syncProgress stopAnimation:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([self.syncLabel.stringValue isEqualToString:@"Idle"] || [self.syncLabel.stringValue hasPrefix:@"Synced"]) {
                    self.syncStatusContainer.hidden = YES;
                }
            });
        }
    });
}

- (void)selectDestination:(NSString *)identifier {
    for (NSInteger i = 0; i < self.outlineView.numberOfRows; i++) {
        SRSidebarItem *item = [self.outlineView itemAtRow:i];
        if ([item.representedObject isEqual:identifier]) {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            return;
        }
    }
}

@end
