#import "SRSettingsStorageViewController.h"
#import "SRStyle.h"
#import "../Logic/SRRoomManager.h"

@implementation SRSettingsStorageViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Storage Usage"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [SRStyle headlineLargeFont];
    [view addSubview:titleLabel];

    // Placeholder visualization — will be filled with SRStorageUsageView in a future pass
    NSView *vizView = [[NSView alloc] init];
    vizView.translatesAutoresizingMaskIntoConstraints = NO;
    vizView.wantsLayer = YES;
    vizView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    vizView.layer.cornerRadius = [SRStyle cornerRadiusMedium];
    [view addSubview:vizView];

    NSButton *wipeButton = [NSButton buttonWithTitle:@"Wipe Database" target:self action:@selector(wipeDatabase:)];
    wipeButton.translatesAutoresizingMaskIntoConstraints = NO;
    wipeButton.bezelStyle = NSBezelStyleRounded;
    wipeButton.contentTintColor = NSColor.systemRedColor;
    [view addSubview:wipeButton];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:20.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],

        [vizView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [vizView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
        [vizView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20.0],
        [vizView.heightAnchor constraintEqualToConstant:200.0],

        [wipeButton.topAnchor constraintEqualToAnchor:vizView.bottomAnchor constant:20.0],
        [wipeButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
    ]];

    self.view = view;
}

- (void)wipeDatabase:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Wipe Database?";
    alert.informativeText = @"This will delete all locally stored messages and reset sync state. Your identity is preserved. This cannot be undone.";
    [alert addButtonWithTitle:@"Wipe"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleCritical;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [[SRRoomManager sharedManager] resetAccount];
        }
    }];
}

@end
