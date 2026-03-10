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
    NSLog(@"[Sidebar] Selection changed to row %ld", (long)row);
    if (row >= 0) {
        RoomConfig *room = [SRRoomManager sharedManager].rooms[row];
        NSLog(@"[Sidebar] Notifying room selected: %@", room.host);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SRRoomSelectedNotification" object:room];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [SRRoomManager sharedManager].rooms.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
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
        
        [NSLayoutConstraint activateConstraints:@[
            [statusDot.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
            [statusDot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [statusDot.widthAnchor constraintEqualToConstant:8],
            [statusDot.heightAnchor constraintEqualToConstant:8],
            
            [textField.leadingAnchor constraintEqualToAnchor:statusDot.trailingAnchor constant:8],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12]
        ]];
    }
    
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row];
    cell.textField.stringValue = room.host;
    
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
    NSView *statusDot = nil;
    for (NSView *subview in cell.subviews) {
        if ([subview.identifier isEqualToString:@"StatusDot"]) {
            statusDot = subview;
            break;
        }
    }
    
    if (client.isConnected) {
        statusDot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
    } else {
        statusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
    }
    
    return cell;
}

@end