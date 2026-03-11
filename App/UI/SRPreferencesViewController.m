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
        [self.saveButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
    
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
            [[SSBFeedStore sharedStore] setDisplayName:name image:nil forAuthor:pubkey];
        }
    }
}

@end
