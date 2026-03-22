#import "SRSettingsGeneralViewController.h"
#import "SRStyle.h"
#import "../Logic/SRRoomManager.h"
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBMessageCodec.h"
#import <SSBNetwork/SSBSecretStore.h>

@interface SRSettingsGeneralViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@end

@implementation SRSettingsGeneralViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *label = [NSTextField labelWithString:NSLocalizedString(@"Display Name", nil)];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [SRStyle headlineFont];
    [view addSubview:label];

    self.nameField = [[NSTextField alloc] init];
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameField.placeholderString = NSLocalizedString(@"Your display name", nil);
    [view addSubview:self.nameField];

    NSButton *saveButton = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveName:)];
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";
    [view addSubview:saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:20.0],
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],

        [self.nameField.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8.0],
        [self.nameField.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
        [self.nameField.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20.0],

        [saveButton.topAnchor constraintEqualToAnchor:self.nameField.bottomAnchor constant:12.0],
        [saveButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) return;
    NSString *feedId = SSBPublicIDFromSecret(secret);
    if (!feedId) return;
    NSString *name = [[SSBFeedStore sharedStore] displayNameForAuthor:feedId];
    // Only pre-fill if we have a real name (not the ID itself)
    if (name.length > 0 && ![name isEqualToString:feedId]) {
        self.nameField.stringValue = name;
    }
}

- (void)saveName:(id)sender {
    NSString *name = [self.nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (name.length == 0) return;

    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) return;
    NSString *feedId = SSBPublicIDFromSecret(secret);
    if (!feedId) return;

    SSBRoomClient *client = [[SRRoomManager sharedManager] anyConnectedClient];
    if (!client) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Not Connected", nil);
        alert.informativeText = NSLocalizedString(@"Connect to a room before updating your display name.", nil);
        [alert runModal];
        return;
    }

    NSDictionary *content = [SSBMessageCodec aboutContentForFeed:feedId name:name description:nil];
    [client publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Failed to Save", nil);
                alert.informativeText = error.localizedDescription;
                [alert runModal];
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SRProfileUpdatedNotification"
                                                                    object:feedId];
            }
        });
    }];
}

@end
