#import "SRFeedItem.h"
#import "SRMarkdownParser.h"
#import <SSBNetwork/SSBBlobStore.h>

@interface SRFeedItem ()
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, copy) NSString *currentBlobID;
@end

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
    
    _timestampLabel = [NSTextField labelWithString:@""];
    _timestampLabel.font = [NSFont systemFontOfSize:11];
    _timestampLabel.textColor = [NSColor secondaryLabelColor];
    _timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_timestampLabel];
    
    _imageHeightConstraint = [_blobImageView.heightAnchor constraintEqualToConstant:0];
    
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
        
        [_blobImageView.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_blobImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [_blobImageView.topAnchor constraintEqualToAnchor:_contentLabel.bottomAnchor constant:8],
        _imageHeightConstraint,
        [_blobImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-32],
        
        [_replyButton.leadingAnchor constraintEqualToAnchor:_authorLabel.leadingAnchor],
        [_replyButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8],
        
        [_likeButton.leadingAnchor constraintEqualToAnchor:_replyButton.trailingAnchor constant:16],
        [_likeButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8]
    ]];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Reset image state
    self.blobImageView.image = nil;
    self.blobImageView.hidden = YES;
    self.imageHeightConstraint.constant = 0;
    self.currentBlobID = nil;
    
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
            NSString *text = msg.content[@"text"] ?: @"(No text)";
            NSAttributedString *attrText = [SRMarkdownParser attributedStringFromMarkdown:text];
            [self.contentLabel setAttributedStringValue:attrText];
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
        
        // Load blob image if present
        NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
        if (blobID) {
            [self loadBlobImage:blobID];
        }
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

- (void)toggleCW:(id)sender {
    SSBMessage *msg = (SSBMessage *)self.representedObject;
    NSString *text = msg.content[@"text"] ?: @"(No text)";
    NSAttributedString *attrText = [SRMarkdownParser attributedStringFromMarkdown:text];
    [self.contentLabel setAttributedStringValue:attrText];
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
