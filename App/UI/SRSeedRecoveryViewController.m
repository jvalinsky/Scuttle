#import "SRSeedRecoveryViewController.h"
#import "../../Sources/SSBMetafeed.h"
#import <SSBNetwork/SSBKeychain.h>
#import <os/log.h>

static os_log_t recovery_log;

@interface SRSeedRecoveryViewController ()
@property (nonatomic, strong) NSScrollView  *scrollView;
@property (nonatomic, strong) NSTextView    *messageTextView;
@property (nonatomic, strong) NSButton      *recoverButton;
@property (nonatomic, strong) NSButton      *cancelButton;
@property (nonatomic, strong) NSTextField   *statusLabel;
@end

@implementation SRSeedRecoveryViewController

+ (void)initialize {
    if (self == [SRSeedRecoveryViewController class]) {
        recovery_log = os_log_create("com.scuttlebutt.app", "SeedRecovery");
    }
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Title
    NSTextField *title = [NSTextField labelWithString:@"Recover from Seed Backup"];
    title.font = [NSFont boldSystemFontOfSize:15];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    // Explanation
    NSTextField *explanation = [NSTextField wrappingLabelWithString:
        @"Paste the full JSON of a metafeed/seed backup message below. The app will "
        @"attempt to decrypt it using your current device's metafeed key. On success "
        @"the recovered seed will replace the current metafeed seed."];
    explanation.translatesAutoresizingMaskIntoConstraints = NO;
    explanation.textColor = [NSColor secondaryLabelColor];
    explanation.font = [NSFont systemFontOfSize:12];
    [self.view addSubview:explanation];

    // Text area
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.borderType = NSBezelBorder;
    [self.view addSubview:self.scrollView];

    self.messageTextView = [[NSTextView alloc] init];
    self.messageTextView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.messageTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.documentView = self.messageTextView;

    // Status
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    [self.view addSubview:self.statusLabel];

    // Buttons
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelAction:)];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.recoverButton = [NSButton buttonWithTitle:@"Recover" target:self action:@selector(recoverAction:)];
    self.recoverButton.bezelStyle = NSBezelStyleRounded;
    self.recoverButton.keyEquivalent = @"\r";
    self.recoverButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cancelButton];
    [self.view addSubview:self.recoverButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [explanation.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [explanation.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [explanation.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.scrollView.topAnchor constraintEqualToAnchor:explanation.bottomAnchor constant:14],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.scrollView.heightAnchor constraintEqualToConstant:120],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.recoverButton.leadingAnchor constant:-8],

        [self.recoverButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.recoverButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (void)recoverAction:(id)sender {
    NSString *json = [self.messageTextView.string
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (json.length == 0) {
        self.statusLabel.stringValue = @"Paste a backup message first.";
        self.statusLabel.textColor = [NSColor systemOrangeColor];
        return;
    }

    // Parse the pasted JSON.
    NSData *jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *parseError;
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:jsonData
                                                            options:0
                                                              error:&parseError];
    if (!message || ![message isKindOfClass:[NSDictionary class]]) {
        self.statusLabel.stringValue = @"Invalid JSON. Paste the full message object.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    // Load the local metafeed keys to attempt decryption.
    NSData *localSeed = [SSBKeychain loadMetafeedSeed];
    if (!localSeed) {
        self.statusLabel.stringValue = @"No local metafeed seed. Cannot decrypt.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }
    SSBMetafeed *localMetafeed = [SSBMetafeed createRootMetafeedFromSeed:localSeed];
    if (!localMetafeed) {
        self.statusLabel.stringValue = @"Failed to derive local metafeed keys.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    NSData *recoveredSeed = [SSBMetafeed decryptSeedFromMessage:message
                                                       feedKeys:localMetafeed.keys];
    if (!recoveredSeed || recoveredSeed.length != 32) {
        self.statusLabel.stringValue = @"Decryption failed. This backup may not be addressed to you.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    // Derive the root metafeed for the recovered seed.
    SSBMetafeed *recoveredMetafeed = [SSBMetafeed createRootMetafeedFromSeed:recoveredSeed];
    if (!recoveredMetafeed) {
        self.statusLabel.stringValue = @"Recovered seed is invalid.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    // Persist the recovered seed and root ID.
    if (![SSBKeychain saveMetafeedSeed:recoveredSeed] ||
        ![SSBKeychain saveMetafeedRootID:recoveredMetafeed.ID]) {
        self.statusLabel.stringValue = @"Failed to save recovered seed to keychain.";
        self.statusLabel.textColor = [NSColor systemRedColor];
        return;
    }

    // The announce for the recovered metafeed still needs to be published.
    [SSBKeychain saveMetafeedAnnounced:NO];

    os_log_info(recovery_log, "Seed recovered; new root metafeed: %{public}@", recoveredMetafeed.ID);
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Recovered metafeed: %@",
                                    recoveredMetafeed.ID];
    self.statusLabel.textColor = [NSColor systemGreenColor];
    self.recoverButton.enabled = NO;
}

- (void)cancelAction:(id)sender {
    [self dismissController:nil];
}

@end
