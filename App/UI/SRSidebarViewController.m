#import "SRSidebarViewController.h"
#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import "../Logic/SRQRUtils.h"
#import "SRMainSplitViewController.h"
#import "../../Sources/SSBBamboo.h"
#import "../../Sources/SSBFeedStore.h"
#import <os/log.h>

static os_log_t sidebar_log;

@interface SRSidebarViewController () <SRScannerDelegate>
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) SRProfileHeaderView *profileHeader;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSButton *joinButton;
@property (nonatomic, strong) NSButton *scanButton;
@property (nonatomic, strong) NSView *syncStatusContainer;
@property (nonatomic, strong) NSProgressIndicator *syncProgress;
@property (nonatomic, strong) NSTextField *syncLabel;
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
    [self setupUI];
    
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
}

- (void)endpointsDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)statusDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)syncStatusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *status = userInfo[@"status"];
    float progress = [userInfo[@"progress"] floatValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.syncLabel.stringValue = status ?: @"Idle";
        if (progress < 1.0 && progress >= 0.0) {
            [self.syncProgress startAnimation:nil];
            self.syncStatusContainer.hidden = NO;
        } else {
            [self.syncProgress stopAnimation:nil];
            // Hide after a short delay if idle
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([self.syncLabel.stringValue isEqualToString:@"Idle"] || [self.syncLabel.stringValue hasPrefix:@"Synced"]) {
                    self.syncStatusContainer.hidden = YES;
                }
            });
        }
    });
}

- (void)roomsDidUpdate:(NSNotification *)notification {
    os_log_info(sidebar_log, "Rooms updated notification received");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        if (self.tableView.selectedRow < 0 && [SRRoomManager sharedManager].rooms.count > 0) {
            os_log_info(sidebar_log, "Auto-selecting first room");
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        }
    });
}

- (void)setupUI {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileHeader = [[SRProfileHeaderView alloc] initWithFrame:NSZeroRect];
    self.profileHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.profileHeader];

    [self.view addSubview:self.scrollView];

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.rowHeight = 44;

    self.tableView.style = NSTableViewStyleSourceList;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"RoomColumn"];
    [self.tableView addTableColumn:column];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Disconnect" action:@selector(disconnectAction:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Remove Room" action:@selector(removeRoomAction:) keyEquivalent:@""];
    self.tableView.menu = menu;

    self.scrollView.documentView = self.tableView;

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
}

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
                    [self.tableView reloadData];
                }
            });
        }];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0) return;
    
    NSInteger rooms = [SRRoomManager sharedManager].rooms.count;
    
    if (row == 0) return; // ROOMS Header
    
    if (row <= rooms) {
        RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification 
                                                            object:nil 
                                                          userInfo:@{SRRoomManagerRoomSelectedKey: room}];
    }
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [SRRoomManager sharedManager].rooms.count + 1; // +1 for Header
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row == 0) {
        NSTextField *header = [NSTextField labelWithString:@"ROOMS"];
        header.font = [NSFont boldSystemFontOfSize:11];
        header.textColor = [NSColor secondaryLabelColor];
        return header;
    }
    
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"RoomCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 44)];
        cell.identifier = @"RoomCell";
        
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:textField];
        cell.textField = textField;
        
        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    
    cell.textField.stringValue = room.host;
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
    if (client.isConnected) {
        cell.textField.textColor = [NSColor labelColor];
    } else {
        cell.textField.textColor = [NSColor secondaryLabelColor];
    }
    
    return cell;
}

- (void)removeRoomAction:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row <= 0) return;
    
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Remove %@?", room.host];
    alert.informativeText = @"You will be disconnected from this room.";
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SRRoomManager sharedManager] removeRoom:room];
        [self.tableView reloadData];
    }
}

- (void)disconnectAction:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row <= 0) return;
    
    RoomConfig *room = [SRRoomManager sharedManager].rooms[row - 1];
    SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
    [client disconnect];
    [self.tableView reloadData];
}

@end
