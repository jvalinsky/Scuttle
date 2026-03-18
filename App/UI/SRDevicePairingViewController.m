#import "SRDevicePairingViewController.h"
#import "../Logic/SRDeviceManager.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRQRUtils.h"
#import "../../Sources/SSBMetafeed.h"
#import <SSBNetwork/SSBKeychain.h>
#import <os/log.h>

static os_log_t pairing_log;

@interface SRDevicePairingViewController () <SRScannerDelegate>
@property (nonatomic, strong) NSTableView     *devicesTable;
@property (nonatomic, strong) NSScrollView    *scrollView;
@property (nonatomic, strong) NSButton        *deregisterButton;
@property (nonatomic, strong) NSButton        *pairButton;
@property (nonatomic, strong) NSButton        *showQRButton;
@property (nonatomic, strong) NSButton        *scanQRButton;
@property (nonatomic, strong) NSButton        *doneButton;
@property (nonatomic, strong) NSTextField     *statusLabel;
@property (nonatomic, copy)   NSArray<NSString *> *deviceFeedIDs;
@end

@implementation SRDevicePairingViewController

+ (void)initialize {
    if (self == [SRDevicePairingViewController class]) {
        pairing_log = os_log_create("com.scuttlebutt.app", "DevicePairing");
    }
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 420)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSTextField *title = [NSTextField labelWithString:@"Manage Devices"];
    title.font = [NSFont boldSystemFontOfSize:15];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    NSTextField *explanation = [NSTextField wrappingLabelWithString:
        @"Each device has its own sub-feed derived from your metafeed seed. "
        @"Messages from all registered devices appear in your followers' timelines."];
    explanation.font = [NSFont systemFontOfSize:12];
    explanation.textColor = [NSColor secondaryLabelColor];
    explanation.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:explanation];

    // Devices table.
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.borderType = NSBezelBorder;
    [self.view addSubview:self.scrollView];

    self.devicesTable = [[NSTableView alloc] init];
    self.devicesTable.headerView = nil;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"feedID"];
    col.title = @"Device Feed ID";
    [self.devicesTable addTableColumn:col];
    self.devicesTable.dataSource = (id)self;
    self.devicesTable.delegate = (id)self;
    self.scrollView.documentView = self.devicesTable;

    // Status label.
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Buttons.
    self.deregisterButton = [NSButton buttonWithTitle:@"Deregister Selected"
                                               target:self
                                               action:@selector(deregisterAction:)];
    self.deregisterButton.bezelStyle = NSBezelStyleRounded;
    self.deregisterButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.deregisterButton.enabled = NO;
    [self.view addSubview:self.deregisterButton];

    self.pairButton = [NSButton buttonWithTitle:@"Pair New Device…"
                                         target:self
                                         action:@selector(pairAction:)];
    self.pairButton.bezelStyle = NSBezelStyleRounded;
    self.pairButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pairButton];

    self.showQRButton = [NSButton buttonWithTitle:@"Show QR"
                                           target:self
                                           action:@selector(showQRAction:)];
    self.showQRButton.bezelStyle = NSBezelStyleRounded;
    self.showQRButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.showQRButton];

    self.scanQRButton = [NSButton buttonWithTitle:@"Scan QR"
                                           target:self
                                           action:@selector(scanQRAction:)];
    self.scanQRButton.bezelStyle = NSBezelStyleRounded;
    self.scanQRButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scanQRButton];

    self.doneButton = [NSButton buttonWithTitle:@"Done"
                                         target:self
                                         action:@selector(doneAction:)];
    self.doneButton.bezelStyle = NSBezelStyleRounded;
    self.doneButton.keyEquivalent = @"\r";
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.doneButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [explanation.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [explanation.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [explanation.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.scrollView.topAnchor constraintEqualToAnchor:explanation.bottomAnchor constant:14],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.scrollView.heightAnchor constraintEqualToConstant:150],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.deregisterButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.deregisterButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [self.pairButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.pairButton.leadingAnchor constraintEqualToAnchor:self.deregisterButton.trailingAnchor constant:8],

        [self.showQRButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.showQRButton.leadingAnchor constraintEqualToAnchor:self.pairButton.trailingAnchor constant:8],

        [self.scanQRButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.scanQRButton.leadingAnchor constraintEqualToAnchor:self.showQRButton.trailingAnchor constant:8],

        [self.doneButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.doneButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    [self reloadDevices];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tableSelectionDidChange:)
                                                 name:NSTableViewSelectionDidChangeNotification
                                               object:self.devicesTable];
}

- (void)reloadDevices {
    self.deviceFeedIDs = [[SRDeviceManager sharedManager] registeredDeviceFeedIDs];
    [self.devicesTable reloadData];
    if (self.deviceFeedIDs.count == 0) {
        self.statusLabel.stringValue = @"No registered devices found.";
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:
            @"%lu device(s) registered.", (unsigned long)self.deviceFeedIDs.count];
    }
}

#pragma mark - Table View

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.deviceFeedIDs.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.deviceFeedIDs.count) return nil;
    return self.deviceFeedIDs[row];
}

- (void)tableSelectionDidChange:(NSNotification *)note {
    self.deregisterButton.enabled = (self.devicesTable.selectedRow >= 0);
}

#pragma mark - Actions

- (void)deregisterAction:(id)sender {
    NSInteger row = self.devicesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.deviceFeedIDs.count) return;

    NSString *feedID = self.deviceFeedIDs[row];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Deregister Device?";
    alert.informativeText = [NSString stringWithFormat:
        @"This will tombstone feed %@ so peers stop replicating it. "
        @"Messages already received will remain in peers' stores.", feedID];
    [alert addButtonWithTitle:@"Deregister"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [[SRDeviceManager sharedManager] deregisterDeviceWithFeedID:feedID];
    [self reloadDevices];
}

- (void)pairAction:(id)sender {
    NSAlert *inputAlert = [[NSAlert alloc] init];
    inputAlert.messageText = @"Pair New Device";
    inputAlert.informativeText =
        @"Enter the new device's ephemeral SSB public key. The metafeed seed will be "
        @"encrypted to it. Paste it into the recovery screen on the new device to complete pairing.";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 340, 24)];
    input.placeholderString = @"@<base64>.ed25519";
    [inputAlert setAccessoryView:input];
    [inputAlert addButtonWithTitle:@"Encrypt & Copy"];
    [inputAlert addButtonWithTitle:@"Cancel"];

    if ([inputAlert runModal] != NSAlertFirstButtonReturn) return;

    NSString *recipientID = [input.stringValue stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self _performPairingToRecipient:recipientID];
}

- (void)showQRAction:(id)sender {
    NSAlert *inputAlert = [[NSAlert alloc] init];
    inputAlert.messageText = @"Show Pairing QR";
    inputAlert.informativeText = @"Enter the new device's ephemeral SSB public key.";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 340, 24)];
    input.placeholderString = @"@<base64>.ed25519";
    [inputAlert setAccessoryView:input];
    [inputAlert addButtonWithTitle:@"Generate QR"];
    [inputAlert addButtonWithTitle:@"Cancel"];

    if ([inputAlert runModal] != NSAlertFirstButtonReturn) return;

    NSString *recipientID = [input.stringValue stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pairingJSON = [self _pairingPayloadForRecipient:recipientID];
    if (!pairingJSON) return;

    NSImage *qr = [SRQRUtils generateQRCodeFromString:pairingJSON size:CGSizeMake(400, 400)];
    if (qr) {
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
        iv.image = qr;
        NSAlert *qrAlert = [[NSAlert alloc] init];
        qrAlert.messageText = @"Scan this on the new device";
        [qrAlert setAccessoryView:iv];
        [qrAlert addButtonWithTitle:@"Done"];
        [qrAlert runModal];
    }
}

- (void)scanQRAction:(id)sender {
    SRScannerViewController *scanner = [[SRScannerViewController alloc] init];
    scanner.delegate = self;
    [self presentViewControllerAsSheet:scanner];
}

- (void)scannerDidScanString:(NSString *)string {
    self.statusLabel.stringValue = @"QR Scanned. Processing...";
    NSError *error;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[string dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (payload && [payload[@"type"] isEqualToString:@"metafeed/seed"]) {
        self.statusLabel.stringValue = @"Valid pairing QR detected.";
        self.statusLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.statusLabel.stringValue = @"Scanned data is not a valid pairing payload.";
        self.statusLabel.textColor = [NSColor systemRedColor];
    }
}

- (nullable NSString *)_pairingPayloadForRecipient:(NSString *)recipientID {
    if (recipientID.length == 0) return nil;

    NSData *seed = [SSBKeychain loadMetafeedSeed];
    if (!seed) {
        self.statusLabel.stringValue = @"No metafeed seed found.";
        return nil;
    }
    SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!rootMetafeed) return nil;

    NSData *ciphertext = [SSBMetafeed encryptSeedForBackup:seed
                                                    toFeed:recipientID
                                                  feedKeys:rootMetafeed.keys];
    if (!ciphertext) {
        self.statusLabel.stringValue = @"Encryption failed.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return nil;
    }

    NSDictionary *payload = @{
        @"type":       @"metafeed/seed",
        @"metafeed":   rootMetafeed.ID,
        @"recipient":  recipientID,
        @"ciphertext": [ciphertext base64EncodedStringWithOptions:0]
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)_performPairingToRecipient:(NSString *)recipientID {
    NSString *jsonStr = [self _pairingPayloadForRecipient:recipientID];
    if (jsonStr) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:jsonStr forType:NSPasteboardTypeString];
        self.statusLabel.stringValue = @"Pairing payload copied to clipboard.";
        self.statusLabel.textColor = [NSColor systemGreenColor];
        os_log_info(pairing_log, "Pairing payload copied for recipient %{public}@", recipientID);
    }
}

- (void)doneAction:(id)sender {
    [self dismissController:nil];
}

@end
