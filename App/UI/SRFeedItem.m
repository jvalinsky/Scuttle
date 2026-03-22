#import "SRFeedItem.h"
#import "SRMarkdownParser.h"
#import "SRStyle.h"
#import "../Logic/SRQRUtils.h"
#import "../../Sources/SSBFeedStore.h"
#import <SSBNetwork/SSBBlobStore.h>

@interface SRFeedItem ()
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, copy) NSString *currentBlobID;
@property (nonatomic, strong) NSTextField *replyCountLabel;
@property (nonatomic, strong) NSTextField *likeCountLabel;
@property (nonatomic, assign) BOOL isHovered;

// Thread view support
@property (nonatomic, strong) NSView *branchLineView;
@property (nonatomic, strong) NSLayoutConstraint *avatarLeadingConstraint;
@end

@implementation SRFeedItem

- (void)loadView {
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] init];
    effectView.material = NSVisualEffectMaterialContentBackground;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    self.view = effectView;
    [SRStyle styleCardView:self.view];
    // Clear background to let material show
    self.view.layer.backgroundColor = [NSColor clearColor].CGColor;

    _avatarView = [[NSView alloc] init];
    _avatarView.wantsLayer = YES;
    _avatarView.layer.cornerRadius = [SRStyle avatarSizeMedium] / 2;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_avatarView];

    _authorLabel = [NSTextField labelWithString:@""];
    _authorLabel.font = [SRStyle headlineFont];
    _authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_authorLabel];

    _cwLabel = [NSTextField labelWithString:@""];
    _cwLabel.font = [SRStyle captionFont];
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
    _contentLabel.font = [SRStyle bodyFont];
    _contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _contentLabel.maximumNumberOfLines = 0;
    _contentLabel.cell.lineBreakMode = NSLineBreakByWordWrapping;
    _contentLabel.cell.truncatesLastVisibleLine = NO;
    [self.view addSubview:_contentLabel];
    
    _blobImageView = [[NSImageView alloc] init];
    _blobImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _blobImageView.imageAlignment = NSImageAlignCenter;
    _blobImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _blobImageView.wantsLayer = YES;
    _blobImageView.layer.cornerRadius = 6;
    _blobImageView.layer.masksToBounds = YES;
    _blobImageView.hidden = YES;
    [self.view addSubview:_blobImageView];
    
    _replyButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrowshape.turn.up.left" accessibilityDescription:@"Reply"] target:self action:@selector(replyAction:)];
    _replyButton.bordered = NO;
    _replyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_replyButton];
    
    _likeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"heart" accessibilityDescription:@"Like"] target:self action:@selector(likeAction:)];
    _likeButton.bordered = NO;
    _likeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_likeButton];

    _qrButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"qrcode" accessibilityDescription:@"Share as QR"] target:self action:@selector(showQRAction:)];
    _qrButton.bordered = NO;
    _qrButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_qrButton];
    
    _replyCountLabel = [NSTextField labelWithString:@""];
    _replyCountLabel.font = [SRStyle caption2Font];
    _replyCountLabel.textColor = [NSColor secondaryLabelColor];
    _replyCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _replyCountLabel.hidden = YES;
    [self.view addSubview:_replyCountLabel];

    _likeCountLabel = [NSTextField labelWithString:@""];
    _likeCountLabel.font = [SRStyle caption2Font];
    _likeCountLabel.textColor = [NSColor secondaryLabelColor];
    _likeCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _likeCountLabel.hidden = YES;
    [self.view addSubview:_likeCountLabel];
    
    _timestampLabel = [NSTextField labelWithString:@""];
    _timestampLabel.font = [SRStyle captionFont];
    _timestampLabel.textColor = [NSColor secondaryLabelColor];
    _timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_timestampLabel];

    _branchLineView = [[NSView alloc] init];
    _branchLineView.wantsLayer = YES;
    _branchLineView.translatesAutoresizingMaskIntoConstraints = NO;
    _branchLineView.hidden = YES;
    [self.view addSubview:_branchLineView];
    
    _imageHeightConstraint = [_blobImageView.heightAnchor constraintEqualToConstant:0];
    _avatarLeadingConstraint = [_avatarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12];
    
    [NSLayoutConstraint activateConstraints:@[
        _avatarLeadingConstraint,
        [_avatarView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [_avatarView.widthAnchor constraintEqualToConstant:32],
        [_avatarView.heightAnchor constraintEqualToConstant:32],

        [_branchLineView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [_branchLineView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_branchLineView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_branchLineView.widthAnchor constraintEqualToConstant:2],
        
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
        
        [_blobImageView.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_blobImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_blobImageView.topAnchor constraintEqualToAnchor:_contentLabel.bottomAnchor constant:8],
        _imageHeightConstraint,
        [_blobImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-32],
        
        [_replyButton.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_replyButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        
        [_replyCountLabel.leadingAnchor constraintEqualToAnchor:_replyButton.trailingAnchor constant:4],
        [_replyCountLabel.centerYAnchor constraintEqualToAnchor:_replyButton.centerYAnchor],

        [_likeButton.leadingAnchor constraintEqualToAnchor:_replyCountLabel.trailingAnchor constant:16],
        [_likeButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        
        [_likeCountLabel.leadingAnchor constraintEqualToAnchor:_likeButton.trailingAnchor constant:4],
        [_likeCountLabel.centerYAnchor constraintEqualToAnchor:_likeButton.centerYAnchor],

        [_qrButton.leadingAnchor constraintEqualToAnchor:_likeCountLabel.trailingAnchor constant:16],
        [_qrButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];

    // Cleanup that was there before
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self.view addTrackingArea:area];
}

- (void)viewDidChangeEffectiveAppearance {
    if (!self.branchLineView.hidden) {
        self.branchLineView.layer.backgroundColor = [[NSColor separatorColor] colorWithAlphaComponent:0.6].CGColor;
    }
    if (self.isHovered) {
        self.view.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.85].CGColor;
    } else {
        self.view.layer.backgroundColor = [NSColor clearColor].CGColor;
    }
}

- (void)showQRAction:(id)sender {
    SSBMessage *msg = self.representedObject;
    if (![msg isKindOfClass:[SSBMessage class]]) return;

    if (msg.feedFormat != SSBBFEFeedFormatBamboo) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Bamboo Required";
        alert.informativeText = @"Only messages in Bamboo format support logarithmic Lipmaa proofs for offline QR exchange.";
        [alert runModal];
        return;
    }

    SSBBambooProof *proof = [[SSBFeedStore sharedStore] generateBambooProofForAuthor:msg.author sequence:msg.sequence];
    if (!proof) return;

    NSData *proofData = [SSBBamboo serializeProof:proof];
    if (!proofData) return;

    // We use a URI scheme to identify this as a Bamboo proof
    NSString *qrString = [NSString stringWithFormat:@"ssb:bamboo-proof:%@", [proofData base64EncodedStringWithOptions:0]];
    NSImage *qrImage = [SRQRUtils generateQRCodeFromString:qrString size:CGSizeMake(450, 450)];
    
    if (qrImage) {
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 450, 450)];
        iv.image = qrImage;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Share Message via QR (Sneakernet)";
        alert.informativeText = @"This QR code contains the message and a Lipmaa inclusion proof, allowing it to be verified offline without your full history.";
        [alert setAccessoryView:iv];
        [alert addButtonWithTitle:@"Close"];
        [alert runModal];
    }
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Reset image state
    self.blobImageView.image = nil;
    self.blobImageView.hidden = YES;
    self.imageHeightConstraint.constant = 0;
    self.currentBlobID = nil;
    
    self.replyCountLabel.hidden = YES;
    self.replyCountLabel.stringValue = @"";
    self.likeCountLabel.hidden = YES;
    self.likeCountLabel.stringValue = @"";
    
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
            NSString *text = msg.content[@"text"];
            if (!text) {
                NSString *type = msg.contentType;
                if ([type isEqualToString:@"about"]) {
                    NSString *name = msg.content[@"name"];
                    text = [NSString stringWithFormat:@"Updated profile Name: %@", name ?: @"(unnamed)"];
                } else if ([type isEqualToString:@"contact"]) {
                    NSString *target = msg.content[@"contact"];
                    BOOL following = [msg.content[@"following"] boolValue];
                    text = [NSString stringWithFormat:@"%@ @%@", following ? @"Followed" : @"Unfollowed", [target substringToIndex:MIN(10, target.length)]];
                } else if ([type isEqualToString:@"pub"]) {
                    text = @"Announced a pub location.";
                } else if ([type isEqualToString:@"metafeed"]) {
                    text = @"Created a metafeed node.";
                } else {
                    text = [NSString stringWithFormat:@"[%@] message.", type ?: @"(unknown)"];
                }
            }
            NSAttributedString *attrText = [SRMarkdownParser attributedStringFromMarkdown:text];
            [self.contentLabel setAttributedStringValue:attrText];
        }
        
        NSUInteger hash = [msg.author hash];
        self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.65 alpha:1.0].CGColor;
        
        if (msg.claimedTimestamp > 0) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:msg.claimedTimestamp / 1000.0];
            self.timestampLabel.stringValue = [self _relativeTimestampForDate:date];
        } else {
            self.timestampLabel.stringValue = @"";
        }
        
        // Load blob image if present
        NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
        if (blobID) {
            [self loadBlobImage:blobID];
        }

        // Accessibility: describe the post as "Author: text snippet"
        NSString *authorName = self.authorLabel.stringValue;
        NSString *bodyText = msg.content[@"text"] ?: msg.contentType ?: @"message";
        NSString *snippet = bodyText.length > 80 ? [bodyText substringToIndex:80] : bodyText;
        [self.view setAccessibilityLabel:[NSString stringWithFormat:@"%@: %@", authorName, snippet]];
        [self.view setAccessibilityRole:NSAccessibilityGroupRole];
    }
}

+ (nullable NSString *)extractBlobIDFromMessage:(SSBMessage *)msg {
    // Check mentions for blob references
    NSArray *mentions = msg.content[@"mentions"];
    if ([mentions isKindOfClass:[NSArray class]]) {
        for (id mention in mentions) {
            if ([mention isKindOfClass:[NSDictionary class]]) {
                NSString *link = mention[@"link"];
                if ([link hasPrefix:@"&"] && [link hasSuffix:@".sha256"]) {
                    NSString *type = mention[@"type"];
                    if (!type || [type hasPrefix:@"image/"]) {
                        return link;
                    }
                }
            }
        }
    }
    
    // Check for image blob refs in markdown text: ![alt](&blobid.sha256)
    NSString *text = msg.content[@"text"];
    if (text) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"!\\[.*?\\]\\((&[A-Za-z0-9+/=]+\\.sha256)\\)" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (match && match.numberOfRanges > 1) {
            return [text substringWithRange:[match rangeAtIndex:1]];
        }
    }
    
    return nil;
}

- (void)loadBlobImage:(NSString *)blobID {
    self.currentBlobID = blobID;
    
    // Check local cache first
    NSString *localPath = [[SSBBlobStore sharedStore] localPathForBlobID:blobID];
    if (localPath) {
        [self displayImageAtPath:localPath forBlobID:blobID];
        return;
    }
    
    // Fetch from peer if client is available
    if (self.client) {
        __weak typeof(self) weakSelf = self;
        [self.client fetchBlob:blobID completion:^(NSString * _Nullable path, NSError * _Nullable error) {
            if (path && [weakSelf.currentBlobID isEqualToString:blobID]) {
                [weakSelf displayImageAtPath:path forBlobID:blobID];
            }
        }];
    }
}

- (void)displayImageAtPath:(NSString *)path forBlobID:(NSString *)blobID {
    if (![self.currentBlobID isEqualToString:blobID]) return;
    
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image && image.size.width > 0) {
        self.blobImageView.image = image;
        self.blobImageView.hidden = NO;
        CGFloat maxWidth = self.view.bounds.size.width - 66;
        if (maxWidth < 100) maxWidth = 300;
        CGFloat aspectRatio = image.size.height / image.size.width;
        CGFloat height = MIN(maxWidth * aspectRatio, 300);
        self.imageHeightConstraint.constant = height;
    }
}

- (void)setIsReply:(BOOL)isReply {
    _isReply = isReply;
    self.avatarLeadingConstraint.constant = isReply ? 48 : 12;
    self.branchLineView.hidden = !isReply;
    if (isReply) {
        self.branchLineView.layer.backgroundColor = [[NSColor separatorColor] colorWithAlphaComponent:0.6].CGColor;
    }
}

- (NSString *)_relativeTimestampForDate:(NSDate *)date {
    NSRelativeDateTimeFormatter *fmt = [[NSRelativeDateTimeFormatter alloc] init];
    fmt.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleAbbreviated;
    return [fmt localizedStringForDate:date relativeToDate:[NSDate date]];
}



- (void)mouseEntered:(NSEvent *)event {
    self.isHovered = YES;
    self.view.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.85].CGColor;
}

- (void)mouseExited:(NSEvent *)event {
    self.isHovered = NO;
    self.view.layer.backgroundColor = [NSColor clearColor].CGColor;
}

- (void)toggleCW:(id)sender {
    SSBMessage *msg = (SSBMessage *)self.representedObject;
    NSString *text = msg.content[@"text"] ?: @"(No text)";
    NSAttributedString *attrText = [SRMarkdownParser attributedStringFromMarkdown:text];
    [self.contentLabel setAttributedStringValue:attrText];
    self.contentLabel.hidden = NO;
    self.showCWButton.hidden = YES;
}

- (void)replyAction:(id)sender {
    [self.owner itemDidRequestReply:self];
}

- (void)likeAction:(id)sender {
    [self.owner itemDidRequestLike:self];
}

@end
