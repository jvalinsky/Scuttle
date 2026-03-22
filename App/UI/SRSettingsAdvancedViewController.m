#import "SRSettingsAdvancedViewController.h"
#import "SRDevPanelViewController.h"
#import "SRStyle.h"

@implementation SRSettingsAdvancedViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Advanced"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [SRStyle headlineLargeFont];
    [view addSubview:titleLabel];

    NSButton *devPanelButton = [NSButton buttonWithTitle:@"Show Developer Panel"
                                                  target:self
                                                  action:@selector(showDevPanel:)];
    devPanelButton.translatesAutoresizingMaskIntoConstraints = NO;
    devPanelButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:devPanelButton];

    // Reset Identity routes through the responder chain to AppDelegate.resetIdentity:
    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Identity"
                                               target:nil
                                               action:@selector(resetIdentity:)];
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

- (void)showDevPanel:(id)sender {
    SRDevPanelViewController *vc = [[SRDevPanelViewController alloc] init];
    [self presentViewControllerAsSheet:vc];
}

@end
