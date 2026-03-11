#import "SRErrorBannerView.h"

@interface SRErrorBannerView ()
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@end

@implementation SRErrorBannerView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor systemRedColor].CGColor;
    
    self.messageLabel = [NSTextField labelWithString:@""];
    self.messageLabel.textColor = [NSColor whiteColor];
    self.messageLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.messageLabel];
    
    self.closeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"] target:self action:@selector(hide)];
    self.closeButton.bordered = NO;
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.closeButton];
    
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    
    [NSLayoutConstraint activateConstraints:@[
        self.heightConstraint,
        
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [self.messageLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-12],
        
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:20],
        [self.closeButton.heightAnchor constraintEqualToConstant:20]
    ]];
    
    self.hidden = YES;
}

- (void)showMessage:(NSString *)message {
    self.messageLabel.stringValue = message;
    self.heightConstraint.constant = 40;
    self.hidden = NO;
}

- (void)hide {
    self.heightConstraint.constant = 0;
    self.hidden = YES;
}

@end
