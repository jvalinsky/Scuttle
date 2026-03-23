#import "SRRoomManagementViewController.h"
#import "../Logic/SRRoomManager.h"
#import "SRPlatformUI.h"

@interface SRRoomManagementViewController ()

@property (nonatomic, strong) NSTextField *inviteField;
@property (nonatomic, strong) NSButton *joinButton;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<RoomConfig *> *rooms;

@end

@implementation SRRoomManagementViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    self.view.wantsLayer = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViews];
    [self reloadData];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(reloadData) 
                                                 name:SRRoomManagerDidUpdateRoomsNotification 
                                               object:nil];
}

- (void)setupViews {
    // Join section top bar
    NSStackView *topBar = [[NSStackView alloc] initWithFrame:NSZeroRect];
    topBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topBar.spacing = 10;
    topBar.distribution = NSStackViewDistributionFill;
    topBar.alignment = NSLayoutAttributeCenterY;
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.inviteField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.inviteField.placeholderString = @"Enter Room Invite Code...";
    self.inviteField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.inviteField setAccessibilityIdentifier:@"room-invite-field"];

    self.joinButton = [NSButton buttonWithTitle:@"Join Room" target:self action:@selector(joinAction:)];
    self.joinButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.joinButton.bezelStyle = NSBezelStyleRegularSquare;
    [self.joinButton setAccessibilityIdentifier:@"room-join-button"];
    
    [topBar addArrangedSubview:self.inviteField];
    [topBar addArrangedSubview:self.joinButton];
    [self.view addSubview:topBar];
    
    // ScrollView & TableView
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.autohidesScrollers = YES;
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView setAccessibilityIdentifier:@"rooms-table"];
    
    // Add columns
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"Name"];
    nameCol.title = @"Room Host";
    nameCol.width = 300;
    [self.tableView addTableColumn:nameCol];
    
    NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:@"Status"];
    statusCol.title = @"Status";
    statusCol.width = 120;
    [self.tableView addTableColumn:statusCol];
    
    NSTableColumn *actionCol = [[NSTableColumn alloc] initWithIdentifier:@"Action"];
    actionCol.title = @"Action";
    actionCol.width = 100;
    [self.tableView addTableColumn:actionCol];
    
    scrollView.documentView = self.tableView;
    [self.view addSubview:scrollView];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [topBar.heightAnchor constraintEqualToConstant:32],
        
        [self.inviteField.widthAnchor constraintGreaterThanOrEqualToConstant:200],
        
        [scrollView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor constant:20],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadData {
    self.rooms = [SRRoomManager sharedManager].rooms;
    [self.tableView reloadData];
}

- (void)joinAction:(id)sender {
    NSString *invite = self.inviteField.stringValue;
    if (invite.length == 0) return;
    
    self.joinButton.enabled = NO;
    [[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.joinButton.enabled = YES;
            if (success) {
                self.inviteField.stringValue = @"";
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Failed to Join Room";
                alert.informativeText = error.localizedDescription ?: @"Unknown error";
                [alert runModal];
            }
        });
    }];
}

- (void)leaveAction:(id)sender {
    NSInteger row = [self.tableView rowForView:sender];
    if (row < 0 || row >= self.rooms.count) return;
    
    RoomConfig *room = self.rooms[row];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Leave Room?"];
    alert.informativeText = [NSString stringWithFormat:@"Are you sure you want to disconnect and forget room %@?", room.host];
    [alert addButtonWithTitle:@"Leave"];
    [alert addButtonWithTitle:@"Cancel"];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SRRoomManager sharedManager] disconnectFromRoom:room.host];
        [[SRRoomManager sharedManager] removeRoom:room];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rooms.count;
}

#pragma mark - NSTableViewDelegate

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= self.rooms.count) return nil;
    RoomConfig *room = self.rooms[row];
    
    if ([tableColumn.identifier isEqualToString:@"Name"]) {
        NSTextField *tf = [tableView makeViewWithIdentifier:@"NameField" owner:self];
        if (!tf) {
            tf = [NSTextField labelWithString:room.host ?: @"Unknown"];
            tf.identifier = @"NameField";
        } else {
            tf.stringValue = room.host ?: @"Unknown";
        }
        [tf setAccessibilityIdentifier:[NSString stringWithFormat:@"room-name-%ld", (long)row]];
        return tf;
    } else if ([tableColumn.identifier isEqualToString:@"Status"]) {
        NSTextField *tf = [tableView makeViewWithIdentifier:@"StatusField" owner:self];
        if (!tf) {
            tf = [NSTextField labelWithString:@"Checking..."];
            tf.identifier = @"StatusField";
        }
        SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
        tf.stringValue = client.isConnected ? @"🟢 Connected" : @"🔴 Disconnected";
        [tf setAccessibilityIdentifier:[NSString stringWithFormat:@"room-status-%ld", (long)row]];
        return tf;
    } else if ([tableColumn.identifier isEqualToString:@"Action"]) {
        NSButton *btn = [tableView makeViewWithIdentifier:@"ActionCell" owner:self];
        if (!btn) {
            btn = [NSButton buttonWithTitle:@"Leave" target:self action:@selector(leaveAction:)];
            btn.identifier = @"ActionCell";
            btn.bezelStyle = NSBezelStyleSmallSquare;
        }
        [btn setAccessibilityIdentifier:[NSString stringWithFormat:@"room-leave-%ld", (long)row]];
        return btn;
    }
    
    return nil;
}

@end
