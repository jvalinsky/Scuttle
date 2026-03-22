#import "SRNotificationBannerView.h"
#import "SRStyle.h"
#import <QuartzCore/QuartzCore.h>

@interface SRNotificationBannerView ()
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@end

@implementation SRNotificationBannerView

+ (void)showInView:(NSView *)view message:(NSString *)message type:(SRNotificationType)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        SRNotificationBannerView *banner = [[SRNotificationBannerView alloc] initWithFrame:NSMakeRect(0, 0, 320, 50)];
        [view addSubview:banner];
        
        banner.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [banner.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
            [banner.widthAnchor constraintEqualToConstant:340],
            [banner.heightAnchor constraintEqualToConstant:44]
        ]];
        
        banner.topConstraint = [banner.topAnchor constraintEqualToAnchor:view.topAnchor constant:-60]; // Off-screen initially
        banner.topConstraint.active = YES;
        
        [banner configureWithMessage:message type:type];
        [banner animateIn];
    });
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.material = NSVisualEffectMaterialHeaderView;
        self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        self.state = NSVisualEffectStateActive;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [[NSColor separatorColor] colorWithAlphaComponent:0.4].CGColor;
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _iconView = [[NSImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_iconView];
    
    _messageLabel = [NSTextField labelWithString:@""];
    _messageLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _messageLabel.textColor = [NSColor labelColor];
    _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_messageLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:20],
        [_iconView.heightAnchor constraintEqualToConstant:20],
        
        [_messageLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
        [_messageLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_messageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16]
    ]];
}

- (void)configureWithMessage:(NSString *)message type:(SRNotificationType)type {
    self.messageLabel.stringValue = message;
    
    NSString *symbolName = @"info.circle.fill";
    NSColor *tintColor = [NSColor systemBlueColor];
    
    switch (type) {
        case SRNotificationTypeInfo:
            symbolName = @"info.circle.fill";
            tintColor = [NSColor systemBlueColor];
            break;
        case SRNotificationTypeSuccess:
            symbolName = @"checkmark.circle.fill";
            tintColor = [NSColor systemGreenColor];
            break;
        case SRNotificationTypeWarning:
            symbolName = @"exclamationmark.triangle.fill";
            tintColor = [NSColor systemOrangeColor];
            break;
        case SRNotificationTypeError:
            symbolName = @"xmark.circle.fill";
            tintColor = [NSColor systemRedColor];
            break;
    }
    
    self.iconView.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:@"Notification"];
    self.iconView.contentTintColor = tintColor;
}

- (void)animateIn {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.3;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.topConstraint.animator.constant = 20; // Slide down 20pt from top
    } completionHandler:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self animateOut];
        });
    }];
}

- (void)animateOut {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.25;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        self.topConstraint.animator.constant = -60; // Slide back up
    } completionHandler:^{
        [self removeFromSuperview];
    }];
}

@end
