#import "SRSeedBackupViewController.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBMetafeed.h"
#import <SSBNetwork/SSBSecretStore.h>
#import "SRPlatformLog.h"

static os_log_t backup_log;

@interface SRSeedBackupViewController ()
@property (nonatomic, strong) NSTextField *metafeedIDField;
@property (nonatomic, strong) NSTextField *recipientField;
@property (nonatomic, strong) NSButton    *backupButton;
@property (nonatomic, strong) NSButton    *cancelButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation SRSeedBackupViewController

+ (void)initialize {
    if (self == [SRSeedBackupViewController class]) {
        backup_log = os_log_create("com.scuttlebutt.app", "SeedBackup");
    }
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 280)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Title
    NSTextField *title = [NSTextField labelWithString:@"Back Up Identity Seed"];
    title.font = [NSFont boldSystemFontOfSize:15];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    // Explanation
    NSTextField *explanation = [NSTextField wrappingLabelWithString:
        @"Your metafeed seed is the master secret for your identity tree. Back it up by "
        @"encrypting it to a trusted contact's public key. They can share it back with you "
        @"if you lose your device."];
    explanation.translatesAutoresizingMaskIntoConstraints = NO;
    explanation.textColor = [NSColor secondaryLabelColor];
    explanation.font = [NSFont systemFontOfSize:12];
    [self.view addSubview:explanation];

    // Metafeed ID row
    NSTextField *idLabel = [NSTextField labelWithString:@"Your Metafeed ID:"];
    idLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:idLabel];

    self.metafeedIDField = [NSTextField labelWithString:@"—"];
    self.metafeedIDField.translatesAutoresizingMaskIntoConstraints = NO;
    self.metafeedIDField.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.metafeedIDField.textColor = [NSColor secondaryLabelColor];
    self.metafeedIDField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:self.metafeedIDField];

    // Recipient row
    NSTextField *recipientLabel = [NSTextField labelWithString:@"Recipient SSB ID:"];
    recipientLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:recipientLabel];

    self.recipientField = [[NSTextField alloc] init];
    self.recipientField.placeholderString = @"@<base64>.ed25519";
    self.recipientField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.recipientField];

    // Status
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    [self.view addSubview:self.statusLabel];

    // Buttons
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelAction:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.backupButton = [NSButton buttonWithTitle:@"Back Up" target:self action:@selector(backupAction:)];
    self.backupButton.bezelStyle = NSBezelStyleRounded;
    self.backupButton.keyEquivalent = @"\r";
    self.backupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelButton];
    [self.view addSubview:self.backupButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [explanation.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [explanation.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [explanation.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [idLabel.topAnchor constraintEqualToAnchor:explanation.bottomAnchor constant:18],
        [idLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [idLabel.widthAnchor constraintEqualToConstant:130],

        [self.metafeedIDField.centerYAnchor constraintEqualToAnchor:idLabel.centerYAnchor],
        [self.metafeedIDField.leadingAnchor constraintEqualToAnchor:idLabel.trailingAnchor constant:8],
        [self.metafeedIDField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [recipientLabel.topAnchor constraintEqualToAnchor:idLabel.bottomAnchor constant:14],
        [recipientLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [recipientLabel.widthAnchor constraintEqualToConstant:130],

        [self.recipientField.centerYAnchor constraintEqualToAnchor:recipientLabel.centerYAnchor],
        [self.recipientField.leadingAnchor constraintEqualToAnchor:recipientLabel.trailingAnchor constant:8],
        [self.recipientField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.recipientField.bottomAnchor constant:10],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.backupButton.leadingAnchor constant:-8],

        [self.backupButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.backupButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];

    [self loadMetafeedID];
}

- (void)loadMetafeedID {
    NSString *rootID = SSBLoadMetafeedRootID();
    self.metafeedIDField.stringValue = rootID ?: @"No metafeed found";
}

- (void)backupAction:(id)sender {
    NSString *recipientID = [self.recipientField.stringValue stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (recipientID.length == 0) {
        self.statusLabel.stringValue = @"Enter the recipient's SSB ID.";
        self.statusLabel.textColor = [NSColor systemOrangeColor];
        return;
    }

    NSData *seed = SSBLoadMetafeedSeed();
    if (!seed) {
        self.statusLabel.stringValue = @"No metafeed seed found. Please reset your account.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!rootMetafeed) {
        self.statusLabel.stringValue = @"Failed to derive metafeed keys.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    // Encrypt the seed to the recipient's public key.
    NSData *ciphertext = [SSBMetafeed encryptSeedForBackup:seed
                                                    toFeed:recipientID
                                                  feedKeys:rootMetafeed.keys];
    if (!ciphertext) {
        self.statusLabel.stringValue = @"Encryption failed. Check the recipient ID format.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    NSData *identitySecret = SSBLoadIdentitySecret();
    NSString *classicFeedID = SSBPublicIDFromSecret(identitySecret);
    if (!classicFeedID || !identitySecret) {
        self.statusLabel.stringValue = @"No local identity found.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    NSDictionary *content = @{
        @"type":       @"metafeed/seed",
        @"metafeed":   rootMetafeed.ID,
        @"recipient":  recipientID,
        @"ciphertext": [ciphertext base64EncodedStringWithOptions:0]
    };

    SSBRoomClient *client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    if (!client) {
        self.statusLabel.stringValue = @"Not connected to a room. Connect first, then retry.";
        self.statusLabel.textColor = [NSColor systemOrangeColor];
        return;
    }

    NSError *publishError;
    SSBMessage *published = [client publishLocalMessageWithContent:content error:&publishError];
    if (published) {
        os_log_info(backup_log, "Seed backup published for recipient %{public}@", recipientID);
        self.statusLabel.stringValue = @"Backup published successfully.";
        self.statusLabel.textColor = [NSColor systemGreenColor];
        self.backupButton.enabled = NO;
    } else {
        os_log_error(backup_log, "Seed backup publish failed: %{public}@",
                     publishError.localizedDescription);
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Publish failed: %@",
                                        publishError.localizedDescription];
        self.statusLabel.textColor = [NSColor systemRedColor];
    }
}

- (void)cancelAction:(id)sender {
    [self dismissController:nil];
}

@end
