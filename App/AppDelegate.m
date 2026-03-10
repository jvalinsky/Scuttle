#import "AppDelegate.h"
#import "../Sources/tweetnacl.h"
#import "../Sources/RoomStorage.h"
#import "../Sources/RoomInviteHandler.h"
#import <os/log.h>

static os_log_t ssb_app_log;

@implementation PeerCellView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _avatarView = [[NSView alloc] initWithFrame:NSMakeRect(6, 6, 28, 28)];
        _avatarView.wantsLayer = YES;
        _avatarView.layer.cornerRadius = 14;
        _avatarView.layer.backgroundColor = [NSColor systemPurpleColor].CGColor;
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_avatarView];
        
        _pubKeyLabel = [[NSTextField alloc] init];
        _pubKeyLabel.editable = NO;
        _pubKeyLabel.bezeled = NO;
        _pubKeyLabel.drawsBackground = NO;
        _pubKeyLabel.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
        _pubKeyLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        _pubKeyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_pubKeyLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:28],
            [_avatarView.heightAnchor constraintEqualToConstant:28],
            
            [_pubKeyLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:10],
            [_pubKeyLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_pubKeyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    return self;
}
@end

@implementation FeedItemView : NSView
- (instancetype)initWithMessage:(NSDictionary *)msg {
    self = [super initWithFrame:NSMakeRect(0, 0, 300, 80)];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        self.layer.cornerRadius = 8;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        
        NSString *text = msg[@"value"][@"content"][@"text"] ?: @"(Non-text message)";
        NSString *contentType = msg[@"value"][@"content"][@"type"] ?: @"unknown";
        NSString *author = msg[@"value"][@"author"] ?: @"";
        
        // Truncate author for display
        NSString *shortAuthor = author.length > 16 ? [NSString stringWithFormat:@"%@...", [author substringToIndex:16]] : author;
        
        // Timestamp
        NSString *timeStr = @"";
        NSNumber *ts = msg[@"value"][@"timestamp"];
        if (ts) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:[ts doubleValue] / 1000.0];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateStyle = NSDateFormatterShortStyle;
            fmt.timeStyle = NSDateFormatterShortStyle;
            fmt.doesRelativeDateFormatting = YES;
            timeStr = [fmt stringFromDate:date];
        }
        
        // Header: type badge + author + time
        NSTextField *typeLabel = [NSTextField labelWithString:[contentType uppercaseString]];
        typeLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
        typeLabel.textColor = [NSColor systemBlueColor];
        typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:typeLabel];
        
        NSTextField *authorLabel = [NSTextField labelWithString:shortAuthor];
        authorLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
        authorLabel.textColor = [NSColor tertiaryLabelColor];
        authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:authorLabel];
        
        NSTextField *timeLabel = [NSTextField labelWithString:timeStr];
        timeLabel.font = [NSFont systemFontOfSize:10];
        timeLabel.textColor = [NSColor tertiaryLabelColor];
        timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        timeLabel.alignment = NSTextAlignmentRight;
        [self addSubview:timeLabel];
        
        NSTextField *label = [NSTextField labelWithString:text];
        label.font = [NSFont systemFontOfSize:13];
        label.textColor = [NSColor labelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.maximumNumberOfLines = 3;
        label.cell.lineBreakMode = NSLineBreakByWordWrapping;
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:label];
        
        [NSLayoutConstraint activateConstraints:@[
            [typeLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [typeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [authorLabel.leadingAnchor constraintEqualToAnchor:typeLabel.trailingAnchor constant:8],
            [authorLabel.centerYAnchor constraintEqualToAnchor:typeLabel.centerYAnchor],
            [timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [timeLabel.centerYAnchor constraintEqualToAnchor:typeLabel.centerYAnchor],
            [label.topAnchor constraintEqualToAnchor:typeLabel.bottomAnchor constant:4],
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
@end

@implementation MetaCardView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8;
        self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        
        _titleLabel = [[NSTextField alloc] init];
        _titleLabel.editable = NO;
        _titleLabel.bezeled = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];
        
        _valueLabel = [[NSTextField alloc] init];
        _valueLabel.editable = NO;
        _valueLabel.bezeled = NO;
        _valueLabel.drawsBackground = NO;
        _valueLabel.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightMedium];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12]
        ]];
    }
    return self;
}
@end

@implementation AppDelegate

+ (void)initialize {
    if (self == [AppDelegate class]) {
        ssb_app_log = os_log_create("com.scuttlebutt.room", "App");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _clients = [NSMutableDictionary dictionary];
        _roomEndpoints = [NSMutableDictionary dictionary];
        _connectedRoomHosts = [NSMutableArray array];
    }
    return self;
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu setSubmenu:appMenu forItem:appMenuItem];
    
    // Edit Menu (required for Copy/Paste in text fields)
    NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [mainMenu setSubmenu:editMenu forItem:editMenuItem];
    
    [NSApp setMainMenu:mainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self setupMenu];
    
    // UI Setup on next run loop cycle to ensure AppKit is ready
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupUI];
    });
}

- (void)setupUI {
    NSRect frame = NSMakeRect(0, 0, 1200, 800);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame 
                                            styleMask:styleMask 
                                              backing:NSBackingStoreBuffered 
                                                defer:NO];
    self.window.title = @"ScuttleRoom";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.minSize = NSMakeSize(1000, 700);
    self.window.restorable = NO;
    
    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];
    
    // 1. Sidebar Setup
    NSViewController *sidebarVC = [[NSViewController alloc] init];
    // 1. Sidebar (Identity + List + Footer)
    NSVisualEffectView *sidebarEffectView = [[NSVisualEffectView alloc] init];
    sidebarEffectView.material = NSVisualEffectMaterialSidebar;
    sidebarEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebarEffectView.state = NSVisualEffectStateActive;
    sidebarVC.view = sidebarEffectView;
    
    // 1a. Identity Header
    NSView *identityHeader = [[NSView alloc] init];
    identityHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebarEffectView addSubview:identityHeader];
    
    self.avatarView = [[NSView alloc] init];
    self.avatarView.wantsLayer = YES;
    self.avatarView.layer.cornerRadius = 16;
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [identityHeader addSubview:self.avatarView];
    
    self.identityLabel = [NSTextField labelWithString:@"Your Identity (You)"];
    self.identityLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.identityLabel.textColor = [NSColor secondaryLabelColor];
    self.identityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.identityLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [identityHeader addSubview:self.identityLabel];

    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebarEffectView addSubview:scrollView];
    
    // 1b. Sidebar Footer (Join Room)
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebarEffectView addSubview:separator];
    
    NSView *footer = [[NSView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebarEffectView addSubview:footer];
    
    NSButton *joinButton = [NSButton buttonWithTitle:@"Join Room..." target:self action:@selector(joinRoomAction:)];
    joinButton.bezelStyle = NSBezelStyleRounded;
    joinButton.controlSize = NSControlSizeRegular;
    joinButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:joinButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [identityHeader.topAnchor constraintEqualToAnchor:sidebarEffectView.topAnchor constant:40],
        [identityHeader.leadingAnchor constraintEqualToAnchor:sidebarEffectView.leadingAnchor],
        [identityHeader.trailingAnchor constraintEqualToAnchor:sidebarEffectView.trailingAnchor],
        [identityHeader.heightAnchor constraintEqualToConstant:60],
        
        [self.avatarView.leadingAnchor constraintEqualToAnchor:identityHeader.leadingAnchor constant:20],
        [self.avatarView.centerYAnchor constraintEqualToAnchor:identityHeader.centerYAnchor],
        [self.avatarView.widthAnchor constraintEqualToConstant:32],
        [self.avatarView.heightAnchor constraintEqualToConstant:32],
        
        [self.identityLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:10],
        [self.identityLabel.trailingAnchor constraintEqualToAnchor:identityHeader.trailingAnchor constant:-20],
        [self.identityLabel.centerYAnchor constraintEqualToAnchor:identityHeader.centerYAnchor],

        [scrollView.topAnchor constraintEqualToAnchor:identityHeader.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:sidebarEffectView.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:sidebarEffectView.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:separator.topAnchor],
        
        [separator.leadingAnchor constraintEqualToAnchor:sidebarEffectView.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:sidebarEffectView.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
        
        [footer.leadingAnchor constraintEqualToAnchor:sidebarEffectView.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:sidebarEffectView.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:sidebarEffectView.bottomAnchor],
        [footer.heightAnchor constraintEqualToConstant:50],
        
        [joinButton.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [joinButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.headerView = nil;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.rowHeight = 44;
    self.tableView.intercellSpacing = NSMakeSize(0, 0);
    self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"PeerColumn"];
    column.title = @"Peers";
    [self.tableView addTableColumn:column];
    self.tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    column.resizingMask = NSTableColumnAutoresizingMask;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    scrollView.documentView = self.tableView;
    
    // 2. Detail View Setup
    NSViewController *detailVC = [[NSViewController alloc] init];
    self.detailView = [[NSView alloc] init];
    self.detailView.wantsLayer = YES;
    self.detailView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    detailVC.view = self.detailView;

    // Detail Header Area
    NSView *detailHeader = [[NSView alloc] init];
    detailHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:detailHeader];

    self.detailTitleLabel = [[NSTextField alloc] init];
    self.detailTitleLabel.editable = NO;
    self.detailTitleLabel.bezeled = NO;
    self.detailTitleLabel.drawsBackground = NO;
    self.detailTitleLabel.stringValue = @"Welcome to ScuttleRoom";
    self.detailTitleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    self.detailTitleLabel.textColor = [NSColor labelColor];
    self.detailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.detailTitleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [detailHeader addSubview:self.detailTitleLabel];

    self.detailStatusLabel = [[NSTextField alloc] init];
    self.detailStatusLabel.editable = NO;
    self.detailStatusLabel.bezeled = NO;
    self.detailStatusLabel.drawsBackground = NO;
    self.detailStatusLabel.stringValue = @"Select a peer to view details";
    self.detailStatusLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.detailStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.detailStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [detailHeader addSubview:self.detailStatusLabel];

    // Connection status dot
    self.statusDot = [[NSView alloc] init];
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 5;
    self.statusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [detailHeader addSubview:self.statusDot];

    // Connection status label
    self.connectionStatusLabel = [[NSTextField alloc] init];
    self.connectionStatusLabel.editable = NO;
    self.connectionStatusLabel.bezeled = NO;
    self.connectionStatusLabel.drawsBackground = NO;
    self.connectionStatusLabel.stringValue = @"Disconnected";
    self.connectionStatusLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.connectionStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [detailHeader addSubview:self.connectionStatusLabel];

    // Disconnect / Reconnect buttons
    self.disconnectButton = [NSButton buttonWithTitle:@"Disconnect" target:self action:@selector(disconnectAction:)];
    self.disconnectButton.bezelStyle = NSBezelStyleRounded;
    self.disconnectButton.controlSize = NSControlSizeSmall;
    self.disconnectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.disconnectButton.enabled = NO;
    [detailHeader addSubview:self.disconnectButton];

    self.reconnectButton = [NSButton buttonWithTitle:@"Connect" target:self action:@selector(reconnectAction:)];
    self.reconnectButton.bezelStyle = NSBezelStyleRounded;
    self.reconnectButton.controlSize = NSControlSizeSmall;
    self.reconnectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.reconnectButton.enabled = NO;
    [detailHeader addSubview:self.reconnectButton];

    self.removeRoomButton = [NSButton buttonWithTitle:@"Remove Room" target:self action:@selector(removeRoomAction:)];
    self.removeRoomButton.bezelStyle = NSBezelStyleRounded;
    self.removeRoomButton.controlSize = NSControlSizeSmall;
    self.removeRoomButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.removeRoomButton.contentTintColor = [NSColor systemRedColor];
    self.removeRoomButton.hidden = YES;
    [detailHeader addSubview:self.removeRoomButton];

    [NSLayoutConstraint activateConstraints:@[
        [detailHeader.topAnchor constraintEqualToAnchor:self.detailView.topAnchor],
        [detailHeader.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor],
        [detailHeader.trailingAnchor constraintEqualToAnchor:self.detailView.trailingAnchor],
        [detailHeader.heightAnchor constraintEqualToConstant:90],
        
        [self.detailTitleLabel.topAnchor constraintEqualToAnchor:detailHeader.topAnchor constant:20],
        [self.detailTitleLabel.leadingAnchor constraintEqualToAnchor:detailHeader.leadingAnchor constant:20],
        [self.detailTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.removeRoomButton.leadingAnchor constant:-12],
        
        [self.statusDot.leadingAnchor constraintEqualToAnchor:detailHeader.leadingAnchor constant:20],
        [self.statusDot.topAnchor constraintEqualToAnchor:self.detailTitleLabel.bottomAnchor constant:6],
        [self.statusDot.widthAnchor constraintEqualToConstant:10],
        [self.statusDot.heightAnchor constraintEqualToConstant:10],
        
        [self.detailStatusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:6],
        [self.detailStatusLabel.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        
        [self.connectionStatusLabel.leadingAnchor constraintEqualToAnchor:self.detailStatusLabel.trailingAnchor constant:12],
        [self.connectionStatusLabel.centerYAnchor constraintEqualToAnchor:self.statusDot.centerYAnchor],
        
        [self.removeRoomButton.trailingAnchor constraintEqualToAnchor:detailHeader.trailingAnchor constant:-20],
        [self.removeRoomButton.topAnchor constraintEqualToAnchor:detailHeader.topAnchor constant:20],
        
        [self.reconnectButton.trailingAnchor constraintEqualToAnchor:self.removeRoomButton.leadingAnchor constant:-8],
        [self.reconnectButton.topAnchor constraintEqualToAnchor:detailHeader.topAnchor constant:20],
        
        [self.disconnectButton.trailingAnchor constraintEqualToAnchor:self.reconnectButton.leadingAnchor constant:-8],
        [self.disconnectButton.topAnchor constraintEqualToAnchor:detailHeader.topAnchor constant:20],
    ]];

    // Log View
    NSScrollView *logScrollView = [[NSScrollView alloc] init];
    logScrollView.hasVerticalScroller = YES;
    logScrollView.borderType = NSNoBorder;
    logScrollView.drawsBackground = NO;
    logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:logScrollView];

    self.logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.backgroundColor = [NSColor clearColor];
    self.logTextView.textColor = [[NSColor labelColor] colorWithAlphaComponent:0.6];
    self.logTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    logScrollView.documentView = self.logTextView;

    self.metaStackFrame = [[NSStackView alloc] init];
    self.metaStackFrame.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.metaStackFrame.spacing = 16;
    self.metaStackFrame.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:self.metaStackFrame];

    self.latencyCard = [[MetaCardView alloc] initWithFrame:NSZeroRect];
    self.latencyCard.titleLabel.stringValue = @"LATENCY";
    self.latencyCard.valueLabel.stringValue = @"-- ms";
    [self.metaStackFrame addView:self.latencyCard inGravity:NSStackViewGravityLeading];

    self.protocolCard = [[MetaCardView alloc] initWithFrame:NSZeroRect];
    self.protocolCard.titleLabel.stringValue = @"PROTOCOL";
    self.protocolCard.valueLabel.stringValue = @"MuxRPC / JSON";
    [self.metaStackFrame addView:self.protocolCard inGravity:NSStackViewGravityLeading];
    self.metaStackFrame.hidden = YES;

    // View Selector (Timeline / My Feed / Compose)
    self.viewSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Timeline", @"My Feed", @"Peers"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(viewSelectorChanged:)];
    self.viewSelector.selectedSegment = 0;
    self.viewSelector.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:self.viewSelector];

    // Compose Area
    NSBox *composeSeparator = [[NSBox alloc] init];
    composeSeparator.boxType = NSBoxSeparator;
    composeSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:composeSeparator];

    NSView *composeContainer = [[NSView alloc] init];
    composeContainer.wantsLayer = YES;
    composeContainer.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    composeContainer.layer.cornerRadius = 8;
    composeContainer.layer.borderWidth = 1;
    composeContainer.layer.borderColor = [NSColor separatorColor].CGColor;
    composeContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailView addSubview:composeContainer];

    NSScrollView *composeScrollView = [[NSScrollView alloc] init];
    composeScrollView.hasVerticalScroller = YES;
    composeScrollView.borderType = NSNoBorder;
    composeScrollView.drawsBackground = NO;
    composeScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [composeContainer addSubview:composeScrollView];

    self.composeTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
    self.composeTextView.editable = YES;
    self.composeTextView.selectable = YES;
    self.composeTextView.richText = NO;
    self.composeTextView.backgroundColor = [NSColor clearColor];
    self.composeTextView.font = [NSFont systemFontOfSize:13];
    self.composeTextView.textColor = [NSColor labelColor];
    self.composeTextView.textContainerInset = NSMakeSize(8, 8);
    composeScrollView.documentView = self.composeTextView;

    self.publishButton = [NSButton buttonWithTitle:@"Publish" target:self action:@selector(publishAction:)];
    self.publishButton.bezelStyle = NSBezelStyleRounded;
    self.publishButton.translatesAutoresizingMaskIntoConstraints = NO;
    [composeContainer addSubview:self.publishButton];

    self.feedCountLabel = [NSTextField labelWithString:@"0 messages stored"];
    self.feedCountLabel.font = [NSFont systemFontOfSize:10];
    self.feedCountLabel.textColor = [NSColor tertiaryLabelColor];
    self.feedCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [composeContainer addSubview:self.feedCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [composeContainer.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor constant:20],
        [composeContainer.trailingAnchor constraintEqualToAnchor:self.detailView.trailingAnchor constant:-20],
        [composeContainer.topAnchor constraintEqualToAnchor:self.metaStackFrame.bottomAnchor constant:12],
        [composeContainer.heightAnchor constraintEqualToConstant:100],
        
        [composeScrollView.topAnchor constraintEqualToAnchor:composeContainer.topAnchor],
        [composeScrollView.leadingAnchor constraintEqualToAnchor:composeContainer.leadingAnchor],
        [composeScrollView.trailingAnchor constraintEqualToAnchor:composeContainer.trailingAnchor],
        [composeScrollView.bottomAnchor constraintEqualToAnchor:self.publishButton.topAnchor constant:-4],
        
        [self.publishButton.trailingAnchor constraintEqualToAnchor:composeContainer.trailingAnchor constant:-8],
        [self.publishButton.bottomAnchor constraintEqualToAnchor:composeContainer.bottomAnchor constant:-6],
        
        [self.feedCountLabel.leadingAnchor constraintEqualToAnchor:composeContainer.leadingAnchor constant:12],
        [self.feedCountLabel.centerYAnchor constraintEqualToAnchor:self.publishButton.centerYAnchor],
        
        [composeSeparator.topAnchor constraintEqualToAnchor:composeContainer.bottomAnchor constant:8],
        [composeSeparator.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor constant:20],
        [composeSeparator.trailingAnchor constraintEqualToAnchor:self.detailView.trailingAnchor constant:-20],
        
        [self.viewSelector.topAnchor constraintEqualToAnchor:composeSeparator.bottomAnchor constant:8],
        [self.viewSelector.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor constant:20],
    ]];

    // Feed Preview
    self.feedScrollView = [[NSScrollView alloc] init];
    self.feedScrollView.hasVerticalScroller = YES;
    self.feedScrollView.drawsBackground = NO;
    self.feedScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.feedScrollView.hidden = YES;
    [self.detailView addSubview:self.feedScrollView];

    self.feedStackView = [[NSStackView alloc] init];
    self.feedStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.feedStackView.spacing = 8;
    self.feedStackView.edgeInsets = NSEdgeInsetsMake(10, 20, 10, 20);
    self.feedStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.feedStackView setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.feedScrollView.documentView = self.feedStackView;

    [NSLayoutConstraint activateConstraints:@[
        [self.metaStackFrame.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor constant:20],
        [self.metaStackFrame.topAnchor constraintEqualToAnchor:detailHeader.bottomAnchor constant:12],
        [self.metaStackFrame.trailingAnchor constraintLessThanOrEqualToAnchor:self.detailView.trailingAnchor constant:-20],
        
        [self.feedScrollView.topAnchor constraintEqualToAnchor:self.viewSelector.bottomAnchor constant:8],
        [self.feedScrollView.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor],
        [self.feedScrollView.trailingAnchor constraintEqualToAnchor:self.detailView.trailingAnchor],
        [self.feedScrollView.bottomAnchor constraintEqualToAnchor:logScrollView.topAnchor constant:-8],
        
        [self.feedStackView.leadingAnchor constraintEqualToAnchor:self.feedScrollView.contentView.leadingAnchor],
        [self.feedStackView.trailingAnchor constraintEqualToAnchor:self.feedScrollView.contentView.trailingAnchor],
        [self.feedStackView.topAnchor constraintEqualToAnchor:self.feedScrollView.contentView.topAnchor],
        [self.feedStackView.widthAnchor constraintEqualToAnchor:self.feedScrollView.contentView.widthAnchor],
        
        [logScrollView.leadingAnchor constraintEqualToAnchor:self.detailView.leadingAnchor constant:20],
        [logScrollView.trailingAnchor constraintEqualToAnchor:self.detailView.trailingAnchor constant:-20],
        [logScrollView.bottomAnchor constraintEqualToAnchor:self.detailView.bottomAnchor constant:-16],
        [logScrollView.heightAnchor constraintEqualToConstant:140]
    ]];
    
    // 3. Split View Integration
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
    sidebarItem.minimumThickness = 200;
    sidebarItem.maximumThickness = 350;
    sidebarItem.canCollapse = NO;
    [splitVC addSplitViewItem:sidebarItem];
    
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailVC];
    detailItem.minimumThickness = 500;
    [splitVC addSplitViewItem:detailItem];
    
    splitVC.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    
    self.window.contentViewController = splitVC;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    
    // Load persisted rooms
    self.rooms = [RoomStorage listRooms];
    [self.tableView reloadData];
    
    NSLog(@"[App] setupUI END. Window Visible: %d", self.window.isVisible);
    
    // Auto-connect to all saved rooms
    for (RoomConfig *config in self.rooms) {
        [self connectToRoom:config];
    }
    
    if (self.rooms.count == 0) {
        // Fallback to default local room (initial setup)
        NSData *serverPubKey = [[NSData alloc] initWithBase64EncodedString:@"M7ZZ64w2VjK92RlKZkdUldyq3f0o/4bGHaQWoW71Yoc=" options:0];
        RoomConfig *defaultRoom = [[RoomConfig alloc] initWithHost:@"127.0.0.1" port:8008 pubKey:serverPubKey];
        [RoomStorage saveRoom:defaultRoom];
        self.rooms = [RoomStorage listRooms];
        [self connectToRoom:defaultRoom];
    }
}


#pragma mark - Actions

- (void)joinRoomAction:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Join SSB Room";
    alert.informativeText = @"Enter an SSB Room invite code (ssb:room-invite:...) or an HTTPS join link.";
    [alert addButtonWithTitle:@"Join"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
    input.placeholderString = @"https://example.com/join?invite=...";
    input.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    input.cell.usesSingleLineMode = YES;
    alert.accessoryView = input;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *invite = input.stringValue;
        
        NSLog(@"[DEBUG] Invite input: '%@'", invite);
        
        if ([invite hasPrefix:@"http"]) {
            [self appendLog:[NSString stringWithFormat:@"Processing HTTP invite: %@", invite]];
            // Asynchronous resolution
            self.detailTitleLabel.stringValue = @"Resolving Link...";
            self.detailStatusLabel.stringValue = invite;
            
            // Use the stable identity for invite claiming
            NSData *savedIdentity = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
            NSString *myId;
            if (savedIdentity && savedIdentity.length >= 64) {
                NSData *pkData = [savedIdentity subdataWithRange:NSMakeRange(32, 32)];
                myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
            } else {
                unsigned char pk[32];
                unsigned char sk[64];
                crypto_sign_keypair(pk, sk);
                NSData *newIdentity = [NSData dataWithBytes:sk length:64];
                [[NSUserDefaults standardUserDefaults] setObject:newIdentity forKey:@"SSBLocalIdentity"];
                myId = [NSString stringWithFormat:@"@%@.ed25519", [[NSData dataWithBytes:pk length:32] base64EncodedStringWithOptions:0]];
            }
            
            [RoomInviteHandler resolveHTTPSInvite:invite localId:myId completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
                if (config) {
                    [self appendLog:[NSString stringWithFormat:@"Invite resolved to host %@", config.host]];
                    [self handleJoinWithConfig:config];
                } else {
                    [self appendLog:[NSString stringWithFormat:@"Invite resolution FAILED: %@", error.localizedDescription]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.detailTitleLabel.stringValue = @"Resolution Failed";
                        self.detailStatusLabel.stringValue = error.localizedDescription;
                        NSAlert *err = [[NSAlert alloc] init];
                        err.messageText = @"Resolution Failed";
                        err.informativeText = error.localizedDescription ?: @"Could not resolve room metadata from link.";
                        [err runModal];
                    });
                }
            }];
            return;
        }
        
        RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
        if (config) {
            [self appendLog:[NSString stringWithFormat:@"Parsed direct invite code for %@", config.host]];
            [self handleJoinWithConfig:config];
        } else if ([invite containsString:@"~shs:"]) {
            [self appendLog:@"Parsing manual multiserver address..."];
            NSArray *parts = [invite componentsSeparatedByString:@"~"];
            if (parts.count == 2) {
                NSString *netPart = parts[0];
                NSString *shsPart = parts[1];
                NSArray *netComponents = [netPart componentsSeparatedByString:@":"];
                if (netComponents.count >= 3) {
                    NSString *host = netComponents[1];
                    NSInteger port = [netComponents[2] integerValue];
                    NSString *pubKeyStr = [shsPart stringByReplacingOccurrencesOfString:@"shs:" withString:@""];
                    NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
                    if (pubKeyData && host && port > 0) {
                        config = [[RoomConfig alloc] initWithHost:host port:port pubKey:pubKeyData];
                        [self appendLog:[NSString stringWithFormat:@"Parsed multiserver address for %@", host]];
                        [self handleJoinWithConfig:config];
                        return;
                    }
                }
            }
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Invalid Address";
            err.informativeText = @"Could not parse multiserver address format.";
            [err runModal];
        } else {
            NSAlert *err = [[NSAlert alloc] init];
            err.messageText = @"Invalid Invite Code";
            err.informativeText = @"The invite code format was not recognized.";
            [err runModal];
        }
    }
}

- (void)handleJoinWithConfig:(RoomConfig *)config {
    // 1. Persist the room
    [RoomStorage saveRoom:config];
    
    // 2. Refresh UI state
    dispatch_async(dispatch_get_main_queue(), ^{
        [self appendLog:[NSString stringWithFormat:@"Config saved for %@", config.host]];
        self.rooms = [RoomStorage listRooms];
        [self.tableView reloadData];
        
        self.detailTitleLabel.stringValue = @"Joining Room...";
        self.detailStatusLabel.stringValue = config.host;
    });
    
    [self connectToRoom:config];
}

- (void)connectToRoom:(RoomConfig *)config {
    if (self.clients[config.host]) {
        [self appendLog:[NSString stringWithFormat:@"Already connected/connecting to %@", config.host]];
        return;
    }
    
    [self appendLog:[NSString stringWithFormat:@"Connecting to %@:%ld...", config.host, (long)config.port]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.connectedRoomHosts containsObject:config.host]) {
            [self.connectedRoomHosts addObject:config.host];
        }
        self.roomEndpoints[config.host] = @[];
        [self.tableView reloadData];
        self.metaStackFrame.hidden = YES;
    });

    SSBRoomClient *newClient = [[SSBRoomClient alloc] initWithConfig:config localIdentity:nil];
    newClient.delegate = self;
    self.clients[config.host] = newClient;
    
    // Update Identity UI immediately from the client's (potentially just loaded) secret
    NSData *localSecret = newClient.localIdentitySecret;
    if (localSecret.length >= 64) {
        // PubKey is the first 32 bytes of the secret key in TweetNaCl
        NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
        NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.identityLabel.stringValue = [NSString stringWithFormat:@"%@ (You)", myId];
            NSUInteger hash = [myId hash];
            self.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
            self.avatarView.layer.cornerRadius = 16;
        });
    }

    [newClient connect];
}

- (void)appendLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:entry attributes:@{NSForegroundColorAttributeName: [[NSColor labelColor] colorWithAlphaComponent:0.7]}];
        [self.logTextView.textStorage appendAttributedString:attrStr];
        [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.string.length, 0)];
    });
}

- (void)disconnectAction:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    BOOL isHeader = NO;
    NSString *roomHost = nil;
    id item = [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:&roomHost];
    
    if (item && [item isKindOfClass:[RoomConfig class]]) {
        RoomConfig *config = (RoomConfig *)item;
        SSBRoomClient *client = self.clients[config.host];
        [client disconnect];
        [self appendLog:[NSString stringWithFormat:@"Disconnected from %@", config.host]];
    } else if (!isHeader && [item isKindOfClass:[NSString class]] && roomHost) {
        // Disconnect room for selected peer
        SSBRoomClient *client = self.clients[roomHost];
        [client disconnect];
        [self appendLog:[NSString stringWithFormat:@"Disconnected from %@ (via peer selection)", roomHost]];
    } else {
        // Global disconnect
        for (NSString *host in self.clients.allKeys) {
            SSBRoomClient *client = self.clients[host];
            [client disconnect];
            [self appendLog:[NSString stringWithFormat:@"Disconnected from %@", host]];
        }
    }
    [self updateConnectionStatus:NO host:nil];
}

- (void)reconnectAction:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    BOOL isHeader = NO;
    NSString *roomHost = nil;
    id item = [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:&roomHost];
    
    if (item && [item isKindOfClass:[RoomConfig class]]) {
        RoomConfig *config = (RoomConfig *)item;
        [self connectToRoom:config];
    } else {
        // Legacy: Reconnect to all saved rooms if nothing specific selected
        if (self.rooms.count > 0) {
            for (RoomConfig *config in self.rooms) {
                [self connectToRoom:config];
            }
        }
    }
    self.reconnectButton.enabled = NO;
}

- (void)removeRoomAction:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    BOOL isHeader = NO;
    NSString *roomHost = nil;
    id item = [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:&roomHost];
    
    if (item && [item isKindOfClass:[RoomConfig class]]) {
        RoomConfig *config = (RoomConfig *)item;
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = @"Remove Room";
        confirm.informativeText = [NSString stringWithFormat:@"Are you sure you want to remove %@ from your known servers?", config.host];
        [confirm addButtonWithTitle:@"Remove"];
        [confirm addButtonWithTitle:@"Cancel"];
        
        if ([confirm runModal] == NSAlertFirstButtonReturn) {
            [RoomStorage removeRoom:config];
            SSBRoomClient *client = self.clients[config.host];
            if (client) {
                [client disconnect];
                [self.clients removeObjectForKey:config.host];
            }
            [self.connectedRoomHosts removeObject:config.host];
            [self.roomEndpoints removeObjectForKey:config.host];
            self.rooms = [RoomStorage listRooms];
            [self.tableView reloadData];
            [self appendLog:[NSString stringWithFormat:@"Removed room %@", config.host]];
        }
    }
}

- (void)updateConnectionStatus:(BOOL)connected host:(NSString *)host {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (connected) {
            self.statusDot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
            self.connectionStatusLabel.stringValue = [NSString stringWithFormat:@"Connected to %@", host ?: @"room"];
            self.connectionStatusLabel.textColor = [NSColor systemGreenColor];
            self.disconnectButton.enabled = YES;
            self.reconnectButton.enabled = NO;
        } else {
            self.statusDot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
            self.connectionStatusLabel.stringValue = @"Disconnected";
            self.connectionStatusLabel.textColor = [NSColor secondaryLabelColor];
            self.disconnectButton.enabled = NO;
            self.reconnectButton.enabled = YES;
        }
    });
}

- (void)publishAction:(id)sender {
    NSString *text = self.composeTextView.string;
    if (text.length == 0) return;
    
    // Find any connected client to publish through
    SSBRoomClient *client = self.clients.allValues.firstObject;
    if (!client) {
        [self appendLog:@"No connected client for publishing"];
        return;
    }
    
    NSError *error = nil;
    SSBMessage *msg = [client publishPostWithText:text error:&error];
    if (msg) {
        [self appendLog:[NSString stringWithFormat:@"Published post: %@", msg.key]];
        self.composeTextView.string = @"";
        [self refreshTimeline];
    } else {
        [self appendLog:[NSString stringWithFormat:@"Publish failed: %@", error.localizedDescription]];
    }
}

- (void)viewSelectorChanged:(NSSegmentedControl *)sender {
    switch (sender.selectedSegment) {
        case 0: // Timeline
            [self refreshTimeline];
            break;
        case 1: // My Feed
            [self refreshMyFeed];
            break;
        case 2: // Peers (existing behavior)
            break;
    }
}

- (void)refreshTimeline {
    for (NSView *view in self.feedStackView.views.copy) {
        [self.feedStackView removeView:view];
    }
    
    SSBFeedStore *store = [SSBFeedStore sharedStore];
    NSArray<SSBMessage *> *messages = [store timelineWithLimit:50];
    
    for (SSBMessage *msg in messages) {
        NSMutableDictionary *envelope = [NSMutableDictionary dictionary];
        envelope[@"key"] = msg.key;
        
        NSMutableDictionary *value = [NSMutableDictionary dictionary];
        value[@"content"] = msg.content ?: @{@"type": msg.contentType ?: @"unknown"};
        value[@"author"] = msg.author;
        value[@"sequence"] = @(msg.sequence);
        value[@"timestamp"] = @(msg.claimedTimestamp);
        envelope[@"value"] = value;
        
        FeedItemView *itemView = [[FeedItemView alloc] initWithMessage:envelope];
        [self.feedStackView addView:itemView inGravity:NSStackViewGravityTop];
    }
    
    self.feedCountLabel.stringValue = [NSString stringWithFormat:@"%ld messages stored", (long)[store totalMessageCount]];
    self.feedScrollView.hidden = NO;
}

- (void)refreshMyFeed {
    for (NSView *view in self.feedStackView.views.copy) {
        [self.feedStackView removeView:view];
    }
    
    SSBRoomClient *client = self.clients.allValues.firstObject;
    if (!client) return;
    
    SSBFeedStore *store = [SSBFeedStore sharedStore];
    NSData *pkData = [client.localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
    NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
    
    NSArray<SSBMessage *> *messages = [store feedForAuthor:myId limit:50];
    
    for (SSBMessage *msg in messages) {
        NSMutableDictionary *envelope = [NSMutableDictionary dictionary];
        envelope[@"key"] = msg.key;
        
        NSMutableDictionary *value = [NSMutableDictionary dictionary];
        value[@"content"] = msg.content ?: @{@"type": msg.contentType ?: @"unknown"};
        value[@"author"] = msg.author;
        value[@"sequence"] = @(msg.sequence);
        value[@"timestamp"] = @(msg.claimedTimestamp);
        envelope[@"value"] = value;
        
        FeedItemView *itemView = [[FeedItemView alloc] initWithMessage:envelope];
        [self.feedStackView addView:itemView inGravity:NSStackViewGravityTop];
    }
    
    self.feedCountLabel.stringValue = [NSString stringWithFormat:@"%ld messages stored", (long)[store totalMessageCount]];
    self.feedScrollView.hidden = NO;
}

#pragma mark - SSBRoomClientDelegate
- (void)roomClientDidConnect:(SSBRoomClient *)client {
    os_log_info(ssb_app_log, "Room client connected");
    [self appendLog:@"Connected to room successfully."];
    [self updateConnectionStatus:YES host:client.host];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.detailTitleLabel.stringValue = client.host;
        self.detailStatusLabel.stringValue = @"CONNECTED / REDEEMING...";
    });
    
    if (client.inviteToken) {
        [self appendLog:@"Redeeming invite token..."];
                [client redeemInvite:client.inviteToken completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
                    if (!error) {
                        [self appendLog:@"Invite redeemed successfully!"];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.detailStatusLabel.stringValue = @"JOINED / ONLINE";
                        });
                        
                        // Save room to persistence (without token, as it's used)
                        RoomConfig *saved = [[RoomConfig alloc] initWithHost:client.host port:client.port pubKey:client.serverPubKey];
                        [RoomStorage saveRoom:saved];
                        self.rooms = [RoomStorage listRooms];
                        [self.tableView reloadData];
                    } else {
                        NSString *errDesc = error.localizedDescription;
                        if ([errDesc containsString:@"already"] || [errDesc containsString:@"Member"]) {
                            [self appendLog:@"Already a member of this room."];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                self.detailStatusLabel.stringValue = @"JOINED / ONLINE";
                            });
                        } else {
                            [self appendLog:[NSString stringWithFormat:@"Invite redemption failed: %@", errDesc]];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSAlert *alert = [[NSAlert alloc] init];
                                alert.messageText = @"Invite Redemption Failed";
                                alert.informativeText = [NSString stringWithFormat:@"The server rejected the invite token: %@", errDesc];
                                [alert runModal];
                            });
                        }
                    }
                }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.detailStatusLabel.stringValue = @"CONNECTED / ONLINE";
        });
    }
    
    // Always attempt active discovery regardless of invite status/hang
    [client announce];
    [client subscribeToEndpoints];
    
    // Auto-refresh the timeline after connection
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshTimeline];
    });
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    os_log_error(ssb_app_log, "Room client error: %{public}@", error.localizedDescription);
    [self appendLog:[NSString stringWithFormat:@"ERROR: %@", error.localizedDescription]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.detailTitleLabel.stringValue = @"Connection Failed";
        self.detailStatusLabel.stringValue = error.localizedDescription;
        self.statusDot.layer.backgroundColor = [NSColor systemRedColor].CGColor;
        self.connectionStatusLabel.stringValue = @"Error";
        self.connectionStatusLabel.textColor = [NSColor systemRedColor];
        self.disconnectButton.enabled = NO;
        self.reconnectButton.enabled = YES;
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Connection Error";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    if (client.host) {
        NSArray *oldEndpoints = self.roomEndpoints[client.host];
        self.roomEndpoints[client.host] = endpoints;
        
        // Replicate from newly discovered peers
        for (NSString *peerID in endpoints) {
            if (![oldEndpoints containsObject:peerID]) {
                [client replicateFromPeer:peerID viaRoom:client.host];
            }
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)roomClient:(id)client didLogMessage:(NSString *)message {
    [self appendLog:message];
}

- (void)roomClient:(SSBRoomClient *)client didReplicateMessagesFromPeer:(NSString *)peerId count:(NSInteger)count {
    [self appendLog:[NSString stringWithFormat:@"Replicated %ld messages from %@", (long)count, peerId]];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.viewSelector.selectedSegment == 0) {
            [self refreshTimeline];
        }
    });
}

#pragma mark - TableView
#pragma mark - TableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    NSInteger count = 0;
    
    // Section: ROOMS
    count += 1; // Header "ROOMS"
    count += self.rooms.count;
    
    // Section: PEERS
    count += 1; // Header "PEERS"
    for (NSString *host in self.connectedRoomHosts) {
        count += 1; // Sub-header (Room Host)
        count += self.roomEndpoints[host].count;
    }
    return count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    BOOL isHeader = NO;
    [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:NULL];
    return isHeader;
}

- (id)dataItemAtRow:(NSInteger)row outIsHeader:(BOOL *)outIsHeader outRoomHost:(NSString **)outRoomHost {
    NSInteger currentRow = 0;
    
    // Section: ROOMS
    if (row == currentRow) {
        if (outIsHeader) *outIsHeader = YES;
        return @"ROOMS";
    }
    currentRow++;
    
    if (row < currentRow + self.rooms.count) {
        if (outIsHeader) *outIsHeader = NO;
        return self.rooms[row - currentRow];
    }
    currentRow += self.rooms.count;
    
    // Section: PEERS
    if (row == currentRow) {
        if (outIsHeader) *outIsHeader = YES;
        return @"PEERS";
    }
    currentRow++;
    
    for (NSString *host in self.connectedRoomHosts) {
        // Sub-Header (Room Host)
        if (currentRow == row) {
            if (outIsHeader) *outIsHeader = YES;
            if (outRoomHost) *outRoomHost = host;
            return host;
        }
        currentRow++;
        
        NSArray *peers = self.roomEndpoints[host];
        if (row < currentRow + peers.count) {
            if (outIsHeader) *outIsHeader = NO;
            if (outRoomHost) *outRoomHost = host;
            return peers[row - currentRow];
        }
        currentRow += peers.count;
    }
    return nil;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    BOOL isHeader = NO;
    NSString *roomHost = nil;
    id item = [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:&roomHost];
    
    if (isHeader) {
        NSTableCellView *headerCell = [tableView makeViewWithIdentifier:@"HeaderCell" owner:self];
        if (!headerCell) {
            headerCell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 24)];
            headerCell.identifier = @"HeaderCell";
            
            NSView *dot = [[NSView alloc] init];
            dot.wantsLayer = YES;
            dot.layer.cornerRadius = 4;
            dot.translatesAutoresizingMaskIntoConstraints = NO;
            dot.identifier = @"StatusDot";
            [headerCell addSubview:dot];
            
            NSTextField *label = [NSTextField labelWithString:@""];
            label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
            label.textColor = [NSColor secondaryLabelColor];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.identifier = @"HeaderLabel";
            [headerCell addSubview:label];
            
            [NSLayoutConstraint activateConstraints:@[
                [dot.leadingAnchor constraintEqualToAnchor:headerCell.leadingAnchor constant:12],
                [dot.centerYAnchor constraintEqualToAnchor:headerCell.centerYAnchor],
                [dot.widthAnchor constraintEqualToConstant:8],
                [dot.heightAnchor constraintEqualToConstant:8],
                [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
                [label.trailingAnchor constraintEqualToAnchor:headerCell.trailingAnchor constant:-12],
                [label.centerYAnchor constraintEqualToAnchor:headerCell.centerYAnchor]
            ]];
        }
        
        NSView *dot;
        NSTextField *label;
        for (NSView *subview in headerCell.subviews) {
            if ([subview.identifier isEqualToString:@"StatusDot"]) {
                dot = subview;
            } else if ([subview.identifier isEqualToString:@"HeaderLabel"]) {
                label = (NSTextField *)subview;
            }
        }
        
        if ([item isKindOfClass:[NSString class]]) {
            NSString *title = (NSString *)item;
            label.stringValue = [title uppercaseString];
            
            if ([title isEqualToString:@"ROOMS"] || [title isEqualToString:@"PEERS"]) {
                dot.hidden = YES;
            } else {
                dot.hidden = NO;
                SSBRoomClient *client = self.clients[roomHost];
                if (client.isConnected) {
                    dot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
                } else {
                    dot.layer.backgroundColor = [NSColor systemGrayColor].CGColor;
                }
            }
        }
        
        return headerCell;
    }
    
    PeerCellView *cell = [tableView makeViewWithIdentifier:@"PeerCell" owner:self];
    if (!cell) {
        cell = [[PeerCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 44)];
        cell.identifier = @"PeerCell";
    }
    
    if ([item isKindOfClass:[RoomConfig class]]) {
        RoomConfig *config = (RoomConfig *)item;
        cell.pubKeyLabel.stringValue = config.host;
        cell.avatarView.layer.backgroundColor = [NSColor systemPurpleColor].CGColor;
        
        SSBRoomClient *client = self.clients[config.host];
        if (client.isConnected) {
            cell.pubKeyLabel.textColor = [NSColor labelColor];
        } else {
            cell.pubKeyLabel.textColor = [NSColor secondaryLabelColor];
        }
    } else {
        NSString *peerID = (NSString *)item;
        cell.pubKeyLabel.stringValue = peerID;
        cell.pubKeyLabel.textColor = [NSColor labelColor];
        NSUInteger hash = [peerID hash];
        cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    BOOL isHeader = NO;
    NSString *roomHost = nil;
    id item = [self dataItemAtRow:row outIsHeader:&isHeader outRoomHost:&roomHost];
    
    self.removeRoomButton.hidden = YES;
    
    if (isHeader) {
        self.detailTitleLabel.stringValue = @"ScuttleRoom";
        self.detailStatusLabel.stringValue = @"Select a room or peer to view details";
        self.metaStackFrame.hidden = YES;
        self.feedScrollView.hidden = YES;
        return;
    }
    
    if ([item isKindOfClass:[RoomConfig class]]) {
        RoomConfig *config = (RoomConfig *)item;
        self.detailTitleLabel.stringValue = config.host;
        self.detailStatusLabel.stringValue = @"ROOM CONFIGURATION";
        self.metaStackFrame.hidden = YES;
        self.feedScrollView.hidden = YES;
        self.removeRoomButton.hidden = NO;
        
        SSBRoomClient *client = self.clients[config.host];
        if (client.isConnected) {
            [self updateConnectionStatus:YES host:config.host];
        } else {
            [self updateConnectionStatus:NO host:nil];
        }
    } else if ([item isKindOfClass:[NSString class]]) {
        NSString *peerID = (NSString *)item;
        self.detailTitleLabel.stringValue = peerID;
        self.detailStatusLabel.stringValue = [NSString stringWithFormat:@"ONLINE / DISCOVERED VIA %@", roomHost];
        self.metaStackFrame.hidden = NO;
        self.feedScrollView.hidden = NO;
        
        // Clear old feed
        for (NSView *view in self.feedStackView.views.copy) {
            [self.feedStackView removeView:view];
        }
        
        // Use a consistent latency for each peer
        NSUInteger hash = [peerID hash];
        int latency = 10 + (int)(hash % 40);
        self.latencyCard.valueLabel.stringValue = [NSString stringWithFormat:@"%d ms", latency];
        
        // Protocol info
        self.protocolCard.valueLabel.stringValue = @"MuxRPC / JSON";
        
        // Start fetches
        SSBRoomClient *client = self.clients[roomHost];
        if (client) {
            [client fetchProfileForPeer:peerID completion:^(id _Nullable response, BOOL isEnd, NSError * _Nullable error) {
                if (!error && response && [response isKindOfClass:[NSDictionary class]]) {
                    NSString *name = response[@"name"];
                    if (name) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.detailTitleLabel.stringValue = name;
                            self.detailStatusLabel.stringValue = [NSString stringWithFormat:@"%@ VIA %@", peerID, roomHost];
                        });
                    }
                }
            }];
            
            [client fetchFeedForPeer:peerID limit:5 completion:^(id _Nullable response, BOOL isEnd, NSError * _Nullable error) {
                if (!error && response && [response isKindOfClass:[NSDictionary class]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        FeedItemView *itemView = [[FeedItemView alloc] initWithMessage:response];
                        [self.feedStackView addView:itemView inGravity:NSStackViewGravityTop];
                    });
                }
            }];
        }
    } else {
        self.detailTitleLabel.stringValue = @"ScuttleRoom";
        self.detailStatusLabel.stringValue = @"Select a peer to view details";
        self.metaStackFrame.hidden = YES;
        self.feedScrollView.hidden = YES;
    }
}

@end
