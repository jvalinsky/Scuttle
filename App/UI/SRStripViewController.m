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
    [self addButtonWithSymbol:@"house" context:SRWorkspaceContextFeeds tooltip:@"Feeds"];
    [self addButtonWithSymbol:@"shippingbox" context:SRWorkspaceContextGit tooltip:@"Git SSB"];
    [self addButtonWithSymbol:@"network" context:SRWorkspaceContextNetwork tooltip:@"Network"];

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

- (void)addButtonWithSymbol:(NSString *)symbolName context:(SRWorkspaceContext)context tooltip:(NSString *)tooltip {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
    if (image) {
        // Double size for rich look
        [image setSize:NSMakeSize(22, 22)];
    }

    NSButton *btn = [NSButton buttonWithImage:image target:self action:@selector(buttonAction:)];
    btn.bordered = NO;
    btn.tag = context;
    btn.toolTip = tooltip;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.contentTintColor = NSColor.secondaryLabelColor;

    [self.stackView addArrangedSubview:btn];
    [self.itemButtons addObject:btn];
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
            btn.contentTintColor = NSColor.controlAccentColor;
        } else {
            btn.contentTintColor = NSColor.secondaryLabelColor;
        }
    }
}

@end
