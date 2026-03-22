#import "SRSettingsIdentityViewController.h"

@implementation SRSettingsIdentityViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Identity"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:16.0];
    [view addSubview:titleLabel];

    NSArray<NSString *> *buttonTitles = @[
        @"Back Up Identity Seed",
        @"Recover from Backup",
        @"Rotate Feed Key",
        @"Manage Devices",
    ];

    NSView *previousAnchor = titleLabel;
    BOOL isFirst = YES;
    for (NSString *title in buttonTitles) {
        NSButton *button = [NSButton buttonWithTitle:title target:nil action:nil];
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

@end
