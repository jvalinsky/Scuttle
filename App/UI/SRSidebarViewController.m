#import "SRSidebarViewController.h"
#import "../Logic/SRRoomManager.h"

@interface SRSidebarViewController ()
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSButton *joinButton;
@end

@implementation SRSidebarViewController

- (void)loadView {
    self.effectView = [[NSVisualEffectView alloc] init];
    self.effectView.material = NSVisualEffectMaterialSidebar;
    self.effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.effectView.state = NSVisualEffectStateActive;
    self.view = self.effectView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(roomsDidUpdate:) 
                                                 name:SRRoomManagerDidUpdateRoomsNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(statusDidUpdate:) 
                                                 name:SRRoomManagerConnectionStatusChangedNotification 
                                               object:nil];
}

- (void)statusDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)roomsDidUpdate:(NSNotification *)notification {
    NSLog(@"[Sidebar] Rooms updated notification received");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        if (self.tableView.selectedRow < 0 && [SRRoomManager sharedManager].rooms.count > 0) {
            NSLog(@"[Sidebar] Auto-selecting first room");
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        }
    });
}

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.rowHeight = 44;
    
    // In macOS 12+, we should set the style.
    if (@available(macOS 11.0, *)) {
        self.tableView.style = NSTableViewStyleSourceList;
    }
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"RoomColumn"];
    [self.tableView addTableColumn:column];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Disconnect" action:@selector(disconnectAction:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Remove Room" action:@selector(removeRoomAction:) keyEquivalent:@""];
    self.tableView.menu = menu;
    
    self.scrollView.documentView = self.tableView;
    
    self.joinButton = [NSButton buttonWithTitle:@"Join Room..." target:self action:@selector(joinRoomAction:)];
    self.joinButton.bezelStyle = NSBezelStyleRounded;
    self.joinButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.joinButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:40],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.joinButton.topAnchor constant:-12],
        
        [self.joinButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.joinButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20]
    ]];
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
        [[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) {
                    NSAlert *err = [[NSAlert alloc] init];
                    err.messageText = @"Join Failed";
                    err.informativeText = error.localizedDescription ?: @"Unknown error";
                    [err runModal];
                } else {
                    [self.tableView reloadData];
                }
            });
        }];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0) return;
    
    if (row == 0) return; // Header
    
    NSInteger roomCount = [SRRoomManager sharedManager].rooms.count;
    if (row <= roomCount) {
        RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
        NSLog(@"[Sidebar] Notifying room selected: %@", room.host);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SRRoomSelectedNotification" object:room];
    } else if (row == roomCount + 1) {
        // Discovery Header
        return;
    } else if (row == roomCount + 2) {
        // Browse Channels
        if ([self.view.window.contentViewController respondsToSelector:@selector(showChannelBrowser)]) {
            [self.view.window.contentViewController performSelector:@selector(showChannelBrowser)];
        }
    }
}

- (void)disconnectAction:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) return;
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row];
    [[SRRoomManager sharedManager] disconnectFromRoom:room.host];
}

- (void)removeRoomAction:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) return;
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row];
    [[SRRoomManager sharedManager] removeRoom:room];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    NSInteger rooms = [SRRoomManager sharedManager].rooms.count;
    // Section 1: Rooms Header + Rooms
    // Section 2: Discovery Header + Browse Channels
    return (1 + rooms) + 2;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    NSInteger rooms = [SRRoomManager sharedManager].rooms.count;
    return (row == 0 || row == rooms + 1);
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSInteger rooms = [SRRoomManager sharedManager].rooms.count;
    
    if (row == 0) {
        NSTableCellView *header = [tableView makeViewWithIdentifier:@"HeaderCell" owner:self];
        if (!header) {
            header = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
            header.identifier = @"HeaderCell";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.font = [NSFont boldSystemFontOfSize:11];
            tf.textColor = [NSColor secondaryLabelColor];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [header addSubview:tf];
            header.textField = tf;
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
                [tf.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
            ]];
        }
        header.textField.stringValue = @"ROOMS";
        return header;
    }
    
    if (row == rooms + 1) {
        NSTableCellView *header = [tableView makeViewWithIdentifier:@"HeaderCell" owner:self];
        if (!header) {
            header = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
            header.identifier = @"HeaderCell";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.font = [NSFont boldSystemFontOfSize:11];
            tf.textColor = [NSColor secondaryLabelColor];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [header addSubview:tf];
            header.textField = tf;
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
                [tf.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
            ]];
        }
        header.textField.stringValue = @"DISCOVERY";
        return header;
    }
    
    if (row == rooms + 2) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ActionCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
            cell.identifier = @"ActionCell";
            NSTextField *tf = [NSTextField labelWithString:@""];
            tf.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:tf];
            cell.textField = tf;
            [NSLayoutConstraint activateConstraints:@[
                [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
                [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = @"Browse Channels";
        return cell;
    }
    
    // Room Cells
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"RoomCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 44)];
        cell.identifier = @"RoomCell";
        
        NSView *statusDot = [[NSView alloc] init];
        statusDot.wantsLayer = YES;
        statusDot.layer.cornerRadius = 4;
        statusDot.translatesAutoresizingMaskIntoConstraints = NO;
        statusDot.identifier = @"StatusDot";
        [cell addSubview:statusDot];
        
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:textField];
        cell.textField = textField;
        
        NSTextField *peerCountLabel = [NSTextField labelWithString:@""];
        peerCountLabel.font = [NSFont systemFontOfSize:11];
        peerCountLabel.textColor = [NSColor secondaryLabelColor];
        peerCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        peerCountLabel.identifier = @"PeerCountLabel";
        [cell addSubview:peerCountLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [statusDot.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [statusDot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [statusDot.widthAnchor constraintEqualToConstant:8],
            [statusDot.heightAnchor constraintEqualToConstant:8],
            
            [textField.leadingAnchor constraintEqualToAnchor:statusDot.trailingAnchor constant:8],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            
            [peerCountLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:textField.trailingAnchor constant:8],
            [peerCountLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            [peerCountLabel.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
    cell.textField.stringValue = room.name.length > 0 ? room.name : room.host;
    
    NSTextField *peerCountLabel = nil;
    NSView *statusDot = nil;
    for (NSView *subview in cell.subviews) {
        if ([subview.identifier isEqualToString:@"PeerCountLabel"]) {
            peerCountLabel = (NSTextField *)subview;
        } else if ([subview.identifier isEqualToString:@"StatusDot"]) {
            statusDot = subview;
        }
    }
    
    NSArray *peers = [SRRoomManager sharedManager].roomEndpoints[room.host];
    if (peers.count > 0) {
        peerCountLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)peers.count];
    } else {
        peerCountLabel.stringValue = @"";
    }
    
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
    if (client.isConnected) {
        statusDot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
    } else {
        statusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
    }
    
    return cell;
}

@end