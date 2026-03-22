#import "SRSettingsIdentityViewController.h"
#import "SRSeedBackupViewController.h"
#import "SRSeedRecoveryViewController.h"
#import "SRDevicePairingViewController.h"
#import "SRStyle.h"
#import "../Logic/SRRoomManager.h"
#import <SSBNetwork/SSBSecretStore.h>

@implementation SRSettingsIdentityViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Identity"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [SRStyle headlineLargeFont];
    [view addSubview:titleLabel];

    struct { NSString *title; SEL action; } buttons[] = {
        { @"Back Up Identity Seed",  @selector(backupSeed:) },
        { @"Recover from Backup",    @selector(recoverFromBackup:) },
        { @"Rotate Feed Key",        @selector(rotateFeedKey:) },
        { @"Manage Devices",         @selector(manageDevices:) },
    };
    NSUInteger count = sizeof(buttons) / sizeof(buttons[0]);

    NSView *previousAnchor = titleLabel;
    BOOL isFirst = YES;
    for (NSUInteger i = 0; i < count; i++) {
        NSButton *button = [NSButton buttonWithTitle:buttons[i].title target:self action:buttons[i].action];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.bezelStyle = NSBezelStyleRounded;
        [view addSubview:button];

        CGFloat topSpacing = isFirst ? 20.0 : 12.0;
        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor constraintEqualToAnchor:previousAnchor.bottomAnchor constant:topSpacing],
            [button.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
        ]];

        previousAnchor = button;
        isFirst = NO;
    }

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:20.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
    ]];

    self.view = view;
}

- (void)backupSeed:(id)sender {
    SRSeedBackupViewController *vc = [[SRSeedBackupViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

- (void)recoverFromBackup:(id)sender {
    SRSeedRecoveryViewController *vc = [[SRSeedRecoveryViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

- (void)rotateFeedKey:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rotate Feed Key?";
    alert.informativeText = @"This will derive a new sub-feed key and tombstone the old one. Your identity remains the same. Continue?";
    [alert addButtonWithTitle:@"Rotate Key"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            NSData *secret = SSBLoadIdentitySecret();
            NSString *currentFeedID = secret ? SSBPublicIDFromSecret(secret) : @"";
            [[SRRoomManager sharedManager] replaceSubfeed:currentFeedID completion:^(NSString *newFeedID, NSError *error) {
                if (error) {
                    NSAlert *errAlert = [[NSAlert alloc] init];
                    errAlert.messageText = @"Rotation Failed";
                    errAlert.informativeText = error.localizedDescription;
                    [errAlert runModal];
                }
            }];
        }
    }];
}

- (void)manageDevices:(id)sender {
    SRDevicePairingViewController *vc = [[SRDevicePairingViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

@end
