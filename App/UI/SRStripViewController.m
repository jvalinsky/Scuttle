#import "SRStripViewController.h"

@interface SRStripViewController ()
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) NSView *avatarContainer;
@property (nonatomic, strong) NSMutableArray<NSButton *> *itemButtons;
@end

@implementation SRStripViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 60, 600)];
    self.view.wantsLayer = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.itemButtons = [NSMutableArray array];
    [self setupUI];
}

- (void)setupUI {
    // 1. Avatar at Top
    self.avatarContainer = [[NSView alloc] init];
    self.avatarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarContainer.wantsLayer = YES;
    self.avatarContainer.layer.cornerRadius = 20;
    self.avatarContainer.layer.backgroundColor = NSColor.systemTealColor.CGColor;
    [self.view addSubview:self.avatarContainer];

    // 2. Buttons Stack
    self.stackView = [[NSStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stackView.alignment = NSLayoutAttributeCenterX;
    self.stackView.spacing = 24.0;
    [self.view addSubview:self.stackView];

    // Create Buttons
    [self addButtonWithSymbol:@"house" context:SRWorkspaceContextFeeds tooltip:@"Feeds" accessibilityID:@"strip-btn-home"];
    [self addButtonWithSymbol:@"shippingbox" context:SRWorkspaceContextGit tooltip:@"Git SSB" accessibilityID:@"strip-btn-git"];
    [self addButtonWithSymbol:@"network" context:SRWorkspaceContextNetwork tooltip:@"Network" accessibilityID:@"strip-btn-network"];

    [NSLayoutConstraint activateConstraints:@[
        [self.avatarContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.avatarContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:40],
        [self.avatarContainer.widthAnchor constraintEqualToConstant:40],
        [self.avatarContainer.heightAnchor constraintEqualToConstant:40],

        [self.stackView.topAnchor constraintEqualToAnchor:self.avatarContainer.bottomAnchor constant:40],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    [self updateSelectionStates];
}

- (void)addButtonWithSymbol:(NSString *)symbolName context:(SRWorkspaceContext)context tooltip:(NSString *)tooltip accessibilityID:(NSString *)accessibilityID {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
    if (image) {
        [image setSize:NSMakeSize(20, 20)];
    }

    NSButton *btn = [NSButton buttonWithImage:image target:self action:@selector(buttonAction:)];
    btn.bordered = NO;
    btn.tag = context;
    btn.toolTip = tooltip;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.contentTintColor = NSColor.secondaryLabelColor;
    btn.wantsLayer = YES;
    [btn setAccessibilityIdentifier:accessibilityID];

    [self.stackView addArrangedSubview:btn];
    [self.itemButtons addObject:btn];

    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:36],
        [btn.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)buttonAction:(NSButton *)sender {
    self.selectedContext = sender.tag;
    [self updateSelectionStates];

    if ([self.delegate respondsToSelector:@selector(stripDidSelectContext:)]) {
        [self.delegate stripDidSelectContext:self.selectedContext];
    }
}

- (void)updateSelectionStates {
    for (NSButton *btn in self.itemButtons) {
        if (btn.tag == self.selectedContext) {
            btn.contentTintColor = NSColor.whiteColor;
            btn.layer.backgroundColor = [NSColor controlAccentColor].CGColor;
            btn.layer.cornerRadius = 10;
        } else {
            btn.contentTintColor = NSColor.secondaryLabelColor;
            btn.layer.backgroundColor = [NSColor clearColor].CGColor;
        }
    }
}

@end
