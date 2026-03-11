#import "SRPreferencesViewController.h"
#import "SRProfileHeaderView.h"
#import "../Logic/SRRoomManager.h"
#import <SSBNetwork/SSBNetwork.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBMessageCodec.h>
#import <SSBNetwork/SSBFeedStore.h>

@interface SRPreferencesViewController ()
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) NSTextField *displayNameField;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *wipeButton;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, strong) NSButton *devButton;
@end

@implementation SRPreferencesViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
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
    self.displayNameField.placeholderString = @"Your Name";
    [self.view addSubview:self.displayNameField];
    
    self.saveButton = [NSButton buttonWithTitle:@"Save Profile" target:self action:@selector(saveAction:)];
    self.saveButton.bezelStyle = NSBezelStyleRounded;
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.saveButton];
    
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
        
        [self.saveButton.topAnchor constraintEqualToAnchor:self.displayNameField.bottomAnchor constant:30],
        [self.saveButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.wipeButton.topAnchor constraintEqualToAnchor:self.saveButton.bottomAnchor constant:40],
        [self.wipeButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        
        [self.resetButton.topAnchor constraintEqualToAnchor:self.saveButton.bottomAnchor constant:40],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        
        [self.devButton.topAnchor constraintEqualToAnchor:self.wipeButton.bottomAnchor constant:20],
        [self.devButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
    
    self.wipeButton = [NSButton buttonWithTitle:@"Wipe Database" target:self action:@selector(wipeAction:)];
    self.wipeButton.bezelStyle = NSBezelStyleRounded;
    self.wipeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.wipeButton];
    
    self.resetButton = [NSButton buttonWithTitle:@"Reset Identity" target:self action:@selector(resetIdentityAction:)];
    self.resetButton.bezelStyle = NSBezelStyleRounded;
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resetButton];
    
    self.devButton = [NSButton buttonWithTitle:@"Show Developer Panel" target:self action:@selector(showDevPanelAction:)];
    self.devButton.bezelStyle = NSBezelStyleRounded;
    self.devButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.devButton];
    
    [self loadIdentity];
}

- (void)loadIdentity {
    NSData *localSecret = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
    if (localSecret && localSecret.length >= 64) {
        NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
        NSString *pubkey = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        [self.headerView updateWithIdentity:pubkey name:nil];
    }
}

- (void)saveAction:(id)sender {
    NSString *name = self.displayNameField.stringValue;
    if (name.length == 0) return;
    
    NSLog(@"[Prefs] Saving profile name: %@", name);
    
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
        window.contentViewController = vc;
        [window makeKeyAndOrderFront:nil];
    }
}

@end
