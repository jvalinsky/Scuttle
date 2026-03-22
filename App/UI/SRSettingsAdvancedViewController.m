#import "SRSettingsAdvancedViewController.h"

@implementation SRSettingsAdvancedViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Advanced"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:13.0];
    [view addSubview:titleLabel];

    NSButton *devPanelButton = [NSButton buttonWithTitle:@"Show Developer Panel" target:nil action:nil];
    devPanelButton.translatesAutoresizingMaskIntoConstraints = NO;
    devPanelButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:devPanelButton];

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Identity" target:nil action:nil];
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    resetButton.bezelStyle = NSBezelStyleRounded;
    resetButton.contentTintColor = NSColor.systemRedColor;
    [view addSubview:resetButton];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:20.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],

        [devPanelButton.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20.0],
        [devPanelButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],

        [resetButton.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-20.0],
        [resetButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
    ]];

    self.view = view;
}

@end
