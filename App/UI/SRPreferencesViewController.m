#import "SRPreferencesViewController.h"
#import "SRProfileHeaderView.h"
#import "SRSeedBackupViewController.h"
#import "SRSeedRecoveryViewController.h"
#import "../Logic/SRRoomManager.h"
#import <SSBNetwork/SSBNetwork.h>
#import <SSBNetwork/SSBKeychain.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBMessageCodec.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <os/log.h>

static os_log_t prefs_log;

@interface SRStorageUsageView : NSView
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *stats;
@end

@implementation SRStorageUsageView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    if (self.stats.count == 0) {
        [[NSColor tertiaryLabelColor] set];
        NSRectFill(self.bounds);
        return;
    }
    
    NSArray *sortedAuthors = [self.stats.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [self.stats[b] compare:self.stats[a]];
    }];
    
    long long total = 0;
    for (NSNumber *n in self.stats.allValues) total += n.longLongValue;
    
    CGFloat x = 0;
    int i = 0;
    NSArray *colors = @[[NSColor systemBlueColor], [NSColor systemOrangeColor], [NSColor systemPurpleColor], [NSColor systemGreenColor], [NSColor systemRedColor]];
    
    for (NSString *author in sortedAuthors) {
        long long count = self.stats[author].longLongValue;
        CGFloat width = (CGFloat)count / total * self.bounds.size.width;
        
        NSRect rect = NSMakeRect(x, 0, width, self.bounds.size.height);
        [(NSColor *)colors[i % colors.count] set];
        NSRectFill(rect);
        
        x += width;
        i++;
        if (i > 10) break; // Only show top 10
    }
    
    // Remaining gray
    if (x < self.bounds.size.width) {
        [[NSColor systemGrayColor] set];
        NSRectFill(NSMakeRect(x, 0, self.bounds.size.width - x, self.bounds.size.height));
    }
}

@end

@interface SRPreferencesViewController ()
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) NSTextField *displayNameField;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *wipeButton;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, strong) NSButton *backupSeedButton;
@property (nonatomic, strong) NSButton *recoverSeedButton;
@property (nonatomic, strong) NSButton *devButton;
@property (nonatomic, strong) SRStorageUsageView *usageView;
@property (nonatomic, strong) NSTextField *usageLegend;
@end

@implementation SRPreferencesViewController

+ (void)initialize {
    if (self == [SRPreferencesViewController class]) {
        prefs_log = os_log_create("com.scuttlebutt.app", "Preferences");
    }
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 750)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.headerView = [[SRProfileHeaderView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];
    
    NSTextField *label = [NSTextField labelWithString:@"Display Name:"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    
    self.displayNameField = [[NSTextField alloc] init];
    self.displayNameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.displayNameField];
    
    self.saveButton = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveAction:)];
    self.saveButton.bezelStyle = NSBezelStyleRounded;
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.saveButton];
    
    NSTextField *usageLabel = [NSTextField labelWithString:@"Database Storage Usage:"];
    usageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usageLabel.font = [NSFont boldSystemFontOfSize:13];
    [self.view addSubview:usageLabel];
    
    self.usageView = [[SRStorageUsageView alloc] init];
    self.usageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.usageView.wantsLayer = YES;
    self.usageView.layer.cornerRadius = 4;
    [self.view addSubview:self.usageView];
    
    self.usageLegend = [NSTextField labelWithString:@"Loading stats..."];
    self.usageLegend.translatesAutoresizingMaskIntoConstraints = NO;
    self.usageLegend.font = [NSFont systemFontOfSize:11];
    self.usageLegend.textColor = [NSColor secondaryLabelColor];
    [self.view addSubview:self.usageLegend];

    self.wipeButton = [NSButton buttonWithTitle:@"Wipe Database" target:self action:@selector(wipeAction:)];
    self.wipeButton.bezelStyle = NSBezelStyleRounded;
    self.wipeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.wipeButton];
    
    self.resetButton = [NSButton buttonWithTitle:@"Reset Identity" target:self action:@selector(resetIdentityAction:)];
    self.resetButton.bezelStyle = NSBezelStyleRounded;
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resetButton];
    
    self.backupSeedButton = [NSButton buttonWithTitle:@"Back Up Identity Seed…"
                                              target:self
                                              action:@selector(backupSeedAction:)];
    self.backupSeedButton.bezelStyle = NSBezelStyleRounded;
    self.backupSeedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.backupSeedButton];

    self.recoverSeedButton = [NSButton buttonWithTitle:@"Recover from Backup…"
                                                target:self
                                                action:@selector(recoverSeedAction:)];
    self.recoverSeedButton.bezelStyle = NSBezelStyleRounded;
    self.recoverSeedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.recoverSeedButton];

    self.devButton = [NSButton buttonWithTitle:@"Show Developer Panel" target:self action:@selector(showDevPanelAction:)];
    self.devButton.bezelStyle = NSBezelStyleRounded;
    self.devButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.devButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.headerView.heightAnchor constraintEqualToConstant:80],
        
        [label.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:30],
        [label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        
        [self.displayNameField.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [self.displayNameField.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [self.displayNameField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        
        [self.saveButton.topAnchor constraintEqualToAnchor:self.displayNameField.bottomAnchor constant:20],
        [self.saveButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [usageLabel.topAnchor constraintEqualToAnchor:self.saveButton.bottomAnchor constant:40],
        [usageLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        
        [self.usageView.topAnchor constraintEqualToAnchor:usageLabel.bottomAnchor constant:10],
        [self.usageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.usageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.usageView.heightAnchor constraintEqualToConstant:24],
        
        [self.usageLegend.topAnchor constraintEqualToAnchor:self.usageView.bottomAnchor constant:8],
        [self.usageLegend.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.usageLegend.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        
        [self.wipeButton.topAnchor constraintEqualToAnchor:self.usageLegend.bottomAnchor constant:40],
        [self.wipeButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],

        [self.resetButton.topAnchor constraintEqualToAnchor:self.usageLegend.bottomAnchor constant:40],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],

        [self.backupSeedButton.topAnchor constraintEqualToAnchor:self.wipeButton.bottomAnchor constant:14],
        [self.backupSeedButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],

        [self.recoverSeedButton.topAnchor constraintEqualToAnchor:self.wipeButton.bottomAnchor constant:14],
        [self.recoverSeedButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],

        [self.devButton.topAnchor constraintEqualToAnchor:self.backupSeedButton.bottomAnchor constant:20],
        [self.devButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
    
    [self loadIdentity];
    [self updateStorageStats];
}

- (void)updateStorageStats {
    NSDictionary<NSString *, NSNumber *> *stats = [[SSBFeedStore sharedStore] storageStatistics];
    self.usageView.stats = stats;
    [self.usageView setNeedsDisplay:YES];
    
    NSInteger total = [[SSBFeedStore sharedStore] totalMessageCount];
    if (total > 0) {
        self.usageLegend.stringValue = [NSString stringWithFormat:@"Total messages: %ld across %lu authors.", (long)total, (unsigned long)stats.count];
    } else {
        self.usageLegend.stringValue = @"Database is empty.";
    }
}

- (void)loadIdentity {
    NSData *localSecret = [SSBKeychain loadIdentitySecret];
    if (localSecret && localSecret.length >= 64) {
        NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
        NSString *pubkey = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        [self.headerView updateWithIdentity:pubkey name:nil];
    }
}

- (void)saveAction:(id)sender {
    NSString *name = self.displayNameField.stringValue;
    if (name.length == 0) return;
    
    os_log_info(prefs_log, "Saving profile name: %{public}@", name);
    
    NSData *localSecret = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
    if (!localSecret || localSecret.length < 64) return;
    
    NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
    NSString *pubkey = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
    
    SSBRoomClient *client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    if (client) {
        NSDictionary *content = [SSBMessageCodec aboutContentForFeed:pubkey name:name description:nil];
        NSError *error = nil;
        [client publishLocalMessageWithContent:content error:&error];
        if (!error) {
            [self.headerView updateWithIdentity:pubkey name:name];
        }
    }
}

- (void)wipeAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Wipe Database?";
    alert.informativeText = @"This will delete all stored messages and cannot be undone.";
    [alert addButtonWithTitle:@"Wipe"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleCritical;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SSBFeedStore sharedStore] wipeDatabase];
    }
}

- (void)resetIdentityAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset Identity?";
    alert.informativeText = @"This will wipe your current SSB identity and generate a new one. All peers will see you as a new user.";
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleCritical;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SRRoomManager sharedManager] resetAccount];
    }
}

- (void)backupSeedAction:(id)sender {
    SRSeedBackupViewController *vc = [[SRSeedBackupViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

- (void)recoverSeedAction:(id)sender {
    SRSeedRecoveryViewController *vc = [[SRSeedRecoveryViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

- (void)showDevPanelAction:(id)sender {
    // We need to import the class header or use reflection/dynamic creation if not imported
    // Since I'm adding it, I should ensure it's imported in SRPreferencesViewController.m
    Class devPanelClass = NSClassFromString(@"SRDevPanelViewController");
    if (devPanelClass) {
        NSViewController *vc = [[devPanelClass alloc] init];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Developer Panel";
        window.releasedWhenClosed = NO;
        window.contentViewController = vc;
        [window makeKeyAndOrderFront:nil];
    }
}

@end
