#import "SRSettingsStorageViewController.h"

@implementation SRSettingsStorageViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Storage Usage"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:13.0];
    [view addSubview:titleLabel];

    // Placeholder visualization view
    NSView *vizView = [[NSView alloc] init];
    vizView.translatesAutoresizingMaskIntoConstraints = NO;
    vizView.wantsLayer = YES;
    vizView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    vizView.layer.cornerRadius = 8.0;
    [view addSubview:vizView];

    NSButton *wipeButton = [NSButton buttonWithTitle:@"Wipe Database" target:nil action:nil];
    wipeButton.translatesAutoresizingMaskIntoConstraints = NO;
    wipeButton.bezelStyle = NSBezelStyleRounded;
    if (@available(macOS 14.0, *)) {
        wipeButton.bezelColor = NSColor.systemRedColor;
    } else {
        wipeButton.contentTintColor = NSColor.systemRedColor;
    }
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

@end
