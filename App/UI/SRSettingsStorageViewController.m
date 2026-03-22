#import "SRSettingsStorageViewController.h"
#import "SRStyle.h"
#import "../Logic/SRRoomManager.h"

@interface SRSettingsStorageViewController ()
@property (nonatomic, strong) NSView *vizView;
@end

@implementation SRSettingsStorageViewController

- (void)viewDidChangeEffectiveAppearance {
    self.vizView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:NSLocalizedString(@"Storage Usage", nil)];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [SRStyle headlineLargeFont];
    [view addSubview:titleLabel];

    // Placeholder visualization — will be filled with SRStorageUsageView in a future pass
    self.vizView = [[NSView alloc] init];
    self.vizView.translatesAutoresizingMaskIntoConstraints = NO;
    self.vizView.wantsLayer = YES;
    self.vizView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    self.vizView.layer.cornerRadius = [SRStyle cornerRadiusMedium];
    NSView *vizView = self.vizView;
    [view addSubview:vizView];

    NSButton *wipeButton = [NSButton buttonWithTitle:NSLocalizedString(@"Wipe Database", nil) target:self action:@selector(wipeDatabase:)];
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
    alert.messageText = NSLocalizedString(@"Wipe Database?", nil);
    alert.informativeText = NSLocalizedString(@"This will delete all locally stored messages and reset sync state. Your identity is preserved. This cannot be undone.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Wipe", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    alert.alertStyle = NSAlertStyleCritical;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [[SRRoomManager sharedManager] resetAccount];
        }
    }];
}

@end
