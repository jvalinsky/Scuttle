#import "SRFeedItem.h"

@implementation SRFeedItem

- (void)loadView {
    self.view = [[NSView alloc] init];
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    self.view.layer.cornerRadius = 8;
    self.view.layer.borderWidth = 1;
    self.view.layer.borderColor = [NSColor separatorColor].CGColor;
    
    _avatarView = [[NSView alloc] init];
    _avatarView.wantsLayer = YES;
    _avatarView.layer.cornerRadius = 16;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_avatarView];
    
    _authorLabel = [NSTextField labelWithString:@""];
    _authorLabel.font = [NSFont boldSystemFontOfSize:12];
    _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_authorLabel];
    
    _cwLabel = [NSTextField labelWithString:@""];
    _cwLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    _cwLabel.textColor = [NSColor systemOrangeColor];
    _cwLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _cwLabel.hidden = YES;
    [self.view addSubview:_cwLabel];
    
    _showCWButton = [NSButton buttonWithTitle:@"Show Content" target:self action:@selector(toggleCW:)];
    _showCWButton.bezelStyle = NSBezelStyleInline;
    _showCWButton.controlSize = NSControlSizeSmall;
    _showCWButton.translatesAutoresizingMaskIntoConstraints = NO;
    _showCWButton.hidden = YES;
    [self.view addSubview:_showCWButton];
    
    _contentLabel = [NSTextField labelWithString:@""];
    _contentLabel.font = [NSFont systemFontOfSize:13];
    _contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _contentLabel.maximumNumberOfLines = 0;
    _contentLabel.cell.lineBreakMode = NSLineBreakByWordWrapping;
    [self.view addSubview:_contentLabel];
    
    _replyButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameActionTemplate] target:self action:@selector(replyAction:)];
    _replyButton.bordered = NO;
    _replyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_replyButton];
    
    _likeButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameAddTemplate] target:self action:@selector(likeAction:)];
    _likeButton.bordered = NO;
    _likeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_likeButton];
    
    _timestampLabel = [NSTextField labelWithString:@""];
    _timestampLabel.font = [NSFont systemFontOfSize:11];
    _timestampLabel.textColor = [NSColor secondaryLabelColor];
    _timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_timestampLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_avatarView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [_avatarView.widthAnchor constraintEqualToConstant:32],
        [_avatarView.heightAnchor constraintEqualToConstant:32],
        
        [_authorLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
        [_authorLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        
        [_timestampLabel.leadingAnchor constraintEqualToAnchor:_authorLabel.trailingAnchor constant:8],
        [_timestampLabel.lastBaselineAnchor constraintEqualToAnchor:_authorLabel.lastBaselineAnchor],
        [_timestampLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12],
        
        [_cwLabel.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_cwLabel.topAnchor constraintEqualToAnchor:_authorLabel.bottomAnchor constant:4],
        
        [_showCWButton.leadingAnchor constraintEqualToAnchor:_cwLabel.trailingAnchor constant:8],
        [_showCWButton.centerYAnchor constraintEqualToAnchor:_cwLabel.centerYAnchor],
        
        [_contentLabel.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_contentLabel.topAnchor constraintEqualToAnchor:_authorLabel.bottomAnchor constant:4],
        [_contentLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_contentLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-32],
        
        [_replyButton.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_replyButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        
        [_likeButton.leadingAnchor constraintEqualToAnchor:_replyButton.trailingAnchor constant:16],
        [_likeButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    if ([representedObject isKindOfClass:[SSBMessage class]]) {
        SSBMessage *msg = (SSBMessage *)representedObject;
        self.authorLabel.stringValue = [[SSBFeedStore sharedStore] displayNameForAuthor:msg.author];
        
        NSString *cw = msg.content[@"contentWarning"];
        if (cw.length > 0) {
            self.cwLabel.stringValue = [NSString stringWithFormat:@"CW: %@", cw];
            self.cwLabel.hidden = NO;
            self.showCWButton.hidden = NO;
            self.contentLabel.hidden = YES;
        } else {
            self.cwLabel.hidden = YES;
            self.showCWButton.hidden = YES;
            self.contentLabel.hidden = NO;
            self.contentLabel.stringValue = msg.content[@"text"] ?: @"(No text)";
        }
        
        NSUInteger hash = [msg.author hash];
        self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
        
        if (msg.claimedTimestamp > 0) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:msg.claimedTimestamp / 1000.0];
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            df.dateStyle = NSDateFormatterShortStyle;
            df.timeStyle = NSDateFormatterShortStyle;
            df.doesRelativeDateFormatting = YES;
            self.timestampLabel.stringValue = [df stringFromDate:date];
        } else {
            self.timestampLabel.stringValue = @"";
        }
    }
}

- (void)toggleCW:(id)sender {
    SSBMessage *msg = (SSBMessage *)self.representedObject;
    self.contentLabel.stringValue = msg.content[@"text"] ?: @"(No text)";
    self.contentLabel.hidden = NO;
    self.showCWButton.hidden = YES;
}

- (void)replyAction:(id)sender {
    if ([self.owner respondsToSelector:@selector(itemDidRequestReply:)]) {
        [self.owner performSelector:@selector(itemDidRequestReply:) withObject:self];
    }
}

- (void)likeAction:(id)sender {
    if ([self.owner respondsToSelector:@selector(itemDidRequestLike:)]) {
        [self.owner performSelector:@selector(itemDidRequestLike:) withObject:self];
    }
}

@end
