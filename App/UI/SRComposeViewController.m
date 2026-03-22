#import "SRComposeViewController.h"
#import "SRStyle.h"
#import "../Logic/SRRoomManager.h"
#import "../Logic/SRNotificationNames.h"
#import <SSBNetwork/SSBRoomClient.h>

#import "SRNotificationBannerView.h"

@interface SRComposeViewController () <NSTextViewDelegate>
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSTextField *cwField;
@property (nonatomic, strong) NSButton *publishButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextField *charCountLabel;
@property (nonatomic, strong) NSView *replyBanner;
@property (nonatomic, strong) NSTextField *replyLabel;
@property (nonatomic, strong) NSMutableArray *observerTokens;
@end

@implementation SRComposeViewController

- (void)loadView {
    NSView *view = [[NSView alloc] init];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    view.layer.cornerRadius = 8;
    view.layer.borderWidth = 1;
    view.layer.borderColor = [NSColor separatorColor].CGColor;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.observerTokens = [NSMutableArray array];
    [self setupUI];
    
    __weak typeof(self) weakSelf = self;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:SRRoomSyncStatusChangedNotification
                                                                 object:nil
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification * _Nonnull note) {
        [weakSelf syncStatusDidUpdate:note];
    }];
    [self.observerTokens addObject:token];
}

- (void)dealloc {
    for (id token in self.observerTokens) {
        [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
}

- (void)setRoomHost:(NSString *)roomHost {
    if ((_roomHost == roomHost) || [_roomHost isEqualToString:roomHost]) {
        return;
    }

    _roomHost = [roomHost copy];
    [self refreshPublishState];
}

- (void)setReplyToKey:(NSString *)replyToKey {
    _replyToKey = [replyToKey copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.replyBanner.hidden = (replyToKey.length == 0);
        if (replyToKey.length > 0) {
            self.replyLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Replying to... %@", nil), [replyToKey substringToIndex:MIN(10, replyToKey.length)]];
        }
    });
}

- (void)setupUI {
    // 1. Reply Banner (at top)
    self.replyBanner = [[NSVisualEffectView alloc] init];
    ((NSVisualEffectView *)self.replyBanner).material = NSVisualEffectMaterialHeaderView;
    self.replyBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyBanner.hidden = YES; // Shown only on reply to something
    [self.view addSubview:self.replyBanner];

    self.replyLabel = [NSTextField labelWithString:NSLocalizedString(@"Replying to...", nil)];
    self.replyLabel.font = [SRStyle captionFont];
    self.replyLabel.textColor = [NSColor secondaryLabelColor];
    self.replyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.replyBanner addSubview:self.replyLabel];

    NSButton *closeReplyButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Cancel Reply"] target:self action:@selector(cancelReplyAction:)];
    closeReplyButton.bordered = NO;
    closeReplyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.replyBanner addSubview:closeReplyButton];

    // 2. CW Field
    self.cwField = [[NSTextField alloc] init];
    self.cwField.placeholderString = NSLocalizedString(@"Content Warning (optional)", nil);
    self.cwField.accessibilityLabel = NSLocalizedString(@"Content Warning", nil);
    self.cwField.translatesAutoresizingMaskIntoConstraints = NO;
    self.cwField.bezelStyle = NSTextFieldSquareBezel;
    self.cwField.backgroundColor = [SRStyle surfaceColor];
    [self.view addSubview:self.cwField];
    
    // 3. Formatting Toolbar (Bold, Italic, Code, Link)
    NSView *toolbar = [[NSView alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = [NSColor controlColor].CGColor;
    [self.view addSubview:toolbar];

    NSButton *boldButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"bold" accessibilityDescription:@"Bold"] target:self action:@selector(formatBold:)];
    boldButton.bordered = NO;
    boldButton.keyEquivalent = @"b";
    boldButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    boldButton.toolTip = @"Bold (Cmd+B)";
    
    NSButton *italicButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"italic" accessibilityDescription:@"Italic"] target:self action:@selector(formatItalic:)];
    italicButton.bordered = NO;
    italicButton.keyEquivalent = @"i";
    italicButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    italicButton.toolTip = @"Italic (Cmd+I)";
    
    NSButton *codeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"curlybraces" accessibilityDescription:@"Code"] target:self action:@selector(formatCode:)];
    codeButton.bordered = NO;
    codeButton.keyEquivalent = @"k";
    codeButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    codeButton.toolTip = @"Code (Cmd+K)";
    
    boldButton.translatesAutoresizingMaskIntoConstraints = NO;
    italicButton.translatesAutoresizingMaskIntoConstraints = NO;
    codeButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [toolbar addSubview:boldButton];
    [toolbar addSubview:italicButton];
    [toolbar addSubview:codeButton];

    // 4. ScrollView and TextView
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.textView.accessibilityLabel = NSLocalizedString(@"Message Content", nil);
    self.textView.editable = YES;
    self.textView.selectable = YES;
    self.textView.richText = NO;
    self.textView.font = [SRStyle bodyFont];
    self.textView.textContainerInset = NSMakeSize(8, 8);
    self.textView.delegate = self;
    self.scrollView.documentView = self.textView;
    
    // 5. Character Count (placed bottom-left)
    self.charCountLabel = [NSTextField labelWithString:NSLocalizedString(@"0 / 1000", nil)];
    self.charCountLabel.accessibilityLabel = NSLocalizedString(@"0 of 1000 characters used", nil);
    self.charCountLabel.font = [SRStyle captionFont];
    self.charCountLabel.textColor = [NSColor tertiaryLabelColor];
    self.charCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.charCountLabel];

    // 6. Publish Button
    self.publishButton = [NSButton buttonWithTitle:NSLocalizedString(@"Publish", nil) target:self action:@selector(publishAction:)];
    self.publishButton.accessibilityLabel = NSLocalizedString(@"Publish Message", nil);
    self.publishButton.bezelStyle = NSBezelStyleRounded;
    self.publishButton.keyEquivalent = @"\r";
    self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    self.publishButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.publishButton.keyEquivalent = @"\r"; // Enter triggers publish
    self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [self.view addSubview:self.publishButton];
    
    [NSLayoutConstraint activateConstraints:@[
        // Reply Banner
        [self.replyBanner.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.replyBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.replyBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.replyBanner.heightAnchor constraintEqualToConstant:26],

        [self.replyLabel.leadingAnchor constraintEqualToAnchor:self.replyBanner.leadingAnchor constant:12],
        [self.replyLabel.centerYAnchor constraintEqualToAnchor:self.replyBanner.centerYAnchor],
        [closeReplyButton.trailingAnchor constraintEqualToAnchor:self.replyBanner.trailingAnchor constant:-8],
        [closeReplyButton.centerYAnchor constraintEqualToAnchor:self.replyBanner.centerYAnchor],

        // CW Field — position depends on replyBanner hidden state (will update dynamically but fixed for now top)
        [self.cwField.topAnchor constraintEqualToAnchor:self.replyBanner.bottomAnchor constant:4],
        [self.cwField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.cwField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.cwField.heightAnchor constraintEqualToConstant:24],
        
        // Toolbar
        [toolbar.topAnchor constraintEqualToAnchor:self.cwField.bottomAnchor constant:4],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:28],

        [boldButton.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:8],
        [boldButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [italicButton.leadingAnchor constraintEqualToAnchor:boldButton.trailingAnchor constant:12],
        [italicButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [codeButton.leadingAnchor constraintEqualToAnchor:italicButton.trailingAnchor constant:12],
        [codeButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        // ScrollView
        [self.scrollView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:4],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.publishButton.topAnchor constant:-8],
        
        // Resizable height constraint on scrollView or view
        [self.view.heightAnchor constraintGreaterThanOrEqualToConstant:150],
        [self.view.heightAnchor constraintLessThanOrEqualToConstant:400],

        // Char Count
        [self.charCountLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.charCountLabel.centerYAnchor constraintEqualToAnchor:self.publishButton.centerYAnchor],

        // Publish Button
        [self.publishButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.publishButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12]
    ]];
}

- (void)publishAction:(id)sender {
    NSString *text = [self.textView.string copy];
    NSString *cw = self.cwField.stringValue;
    if (text.length == 0) return;
    
    if (self.onPublish) {
        self.onPublish(text, cw.length > 0 ? cw : nil, self.replyToKey);
    }

    if (self.view.window.contentView) {
        [SRNotificationBannerView showInView:self.view.window.contentView message:NSLocalizedString(@"Message published successfully!", nil) type:SRNotificationTypeSuccess];
    }
    
    [self clear];
}

- (void)clear {
    self.textView.string = @"";
    self.cwField.stringValue = @"";
    self.replyToKey = nil;
    self.replyBanner.hidden = YES;
    [self textDidChange:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self.textView]];
}

#pragma mark - Actions

- (void)cancelReplyAction:(id)sender {
    self.replyToKey = nil;
    self.replyBanner.hidden = YES;
}

- (void)formatBold:(id)sender {
    [self insertFormatting:@"**" suffix:@"**"];
}

- (void)formatItalic:(id)sender {
    [self insertFormatting:@"*" suffix:@"*"];
}

- (void)formatCode:(id)sender {
    [self insertFormatting:@"`" suffix:@"`"];
}

- (void)insertFormatting:(NSString *)prefix suffix:(NSString *)suffix {
    NSRange range = [self.textView selectedRange];
    if (range.location == NSNotFound) return;

    NSString *selectedText = [self.textView.string substringWithRange:range];
    NSString *newText = [NSString stringWithFormat:@"%@%@%@ ", prefix, selectedText, suffix];
    
    [self.textView insertText:newText replacementRange:range];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification {
    NSInteger count = self.textView.string.length;
    self.charCountLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"%ld / 1000", nil), (long)count];
    self.charCountLabel.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"%ld of 1000 characters used", nil), (long)count];
    if (count > 1000) {
        self.charCountLabel.textColor = [NSColor systemRedColor];
    } else {
        self.charCountLabel.textColor = [NSColor tertiaryLabelColor];
    }
}

- (void)syncStatusDidUpdate:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *host = userInfo[SRRoomSyncStatusHostKey];

    if (self.roomHost.length == 0 || ![host isEqualToString:self.roomHost]) {
        return;
    }

    [self applySyncStatus:userInfo[SRRoomSyncStatusKey]];
}

- (void)refreshPublishState {
    NSString *status = self.roomHost.length > 0 ? [[SRRoomManager sharedManager] syncStatusForHost:self.roomHost] : nil;
    [self applySyncStatus:status];
}

- (void)applySyncStatus:(nullable NSString *)status {
    NSString *resolvedStatus = status ?: @"Idle";
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Disable publish if syncing or queued
        BOOL isSyncing = [resolvedStatus containsString:@"Syncing"] || [resolvedStatus containsString:@"Queued"];
        self.publishButton.enabled = !isSyncing;
        
        if ([resolvedStatus containsString:@"Queued"]) {
            self.publishButton.title = [NSString stringWithFormat:NSLocalizedString(@"Publish (%@)", nil), resolvedStatus];
        } else if (isSyncing) {
            self.publishButton.title = NSLocalizedString(@"Syncing...", nil);
        } else {
            self.publishButton.title = NSLocalizedString(@"Publish", nil);
        }
    });
}

@end
