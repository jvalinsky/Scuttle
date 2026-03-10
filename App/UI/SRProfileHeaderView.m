#import "SRProfileHeaderView.h"

@implementation SRProfileHeaderView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    
    _avatarView = [[NSView alloc] init];
    _avatarView.wantsLayer = YES;
    _avatarView.layer.cornerRadius = 24;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_avatarView];
    
    _nameLabel = [NSTextField labelWithString:@"Loadining..."];
    _nameLabel.font = [NSFont boldSystemFontOfSize:18];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_nameLabel];
    
    _pubkeyLabel = [NSTextField labelWithString:@""];
    _pubkeyLabel.font = [NSFont userFixedPitchFontOfSize:11];
    _pubkeyLabel.textColor = [NSColor secondaryLabelColor];
    _pubkeyLabel.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pubkeyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_pubkeyLabel];
    
    _actionButton = [NSButton buttonWithTitle:@"Set Profile" target:nil action:NULL];
    _actionButton.bezelStyle = NSBezelStyleRounded;
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_actionButton];
    
    NSView *separator = [[NSView alloc] init];
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor separatorColor].CGColor;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:separator];
    
    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:48],
        [_avatarView.heightAnchor constraintEqualToConstant:48],
        
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
        [_nameLabel.topAnchor constraintEqualToAnchor:_avatarView.topAnchor constant:2],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-12],
        
        [_pubkeyLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_pubkeyLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
        [_pubkeyLabel.widthAnchor constraintEqualToConstant:300],
        
        [_actionButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        
        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:1]
    ]];
}

- (void)updateWithIdentity:(NSString *)pubkey name:(nullable NSString *)name {
    self.pubkeyLabel.stringValue = pubkey;
    self.nameLabel.stringValue = name ?: @"Anonymous";
    
    NSUInteger hash = [pubkey hash];
    self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
}

@end
