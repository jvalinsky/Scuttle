#import "SRSettingsGeneralViewController.h"

@implementation SRSettingsGeneralViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 460)];

    NSTextField *label = [NSTextField labelWithString:@"Display Name"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont boldSystemFontOfSize:13.0];
    [view addSubview:label];

    NSTextField *nameField = [[NSTextField alloc] init];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.placeholderString = @"Your display name";
    [view addSubview:nameField];

    NSButton *saveButton = [NSButton buttonWithTitle:@"Save" target:nil action:nil];
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    saveButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:20.0],
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],

        [nameField.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8.0],
        [nameField.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
        [nameField.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20.0],

        [saveButton.topAnchor constraintEqualToAnchor:nameField.bottomAnchor constant:12.0],
        [saveButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20.0],
    ]];

    self.view = view;
}

@end
