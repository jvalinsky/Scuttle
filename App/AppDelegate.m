#import "AppDelegate.h"
#import "../Sources/tweetnacl.h"

@implementation PeerCellView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _avatarView = [[NSView alloc] initWithFrame:NSMakeRect(6, 6, 28, 28)];
        _avatarView.wantsLayer = YES;
        _avatarView.layer.cornerRadius = 14;
        _avatarView.layer.backgroundColor = [NSColor systemPurpleColor].CGColor;
        [self addSubview:_avatarView];
        
        _pubKeyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 6, frame.size.width - 46, 28)];
        _pubKeyLabel.editable = NO;
        _pubKeyLabel.bezeled = NO;
        _pubKeyLabel.drawsBackground = NO;
        _pubKeyLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _pubKeyLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_pubKeyLabel];
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

- (instancetype)init {
    self = [super init];
    if (self) {
        _endpoints = @[];
    }
    return self;
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu setSubmenu:appMenu forItem:appMenuItem];
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
    NSRect frame = NSMakeRect(0, 0, 1000, 600);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame 
                                            styleMask:styleMask 
                                              backing:NSBackingStoreBuffered 
                                                defer:NO];
    self.window.title = @"ScuttleRoom";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.minSize = NSMakeSize(800, 500);
    self.window.restorable = NO;
    
    NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];
    
    // 1. Sidebar Setup
    NSViewController *sidebarVC = [[NSViewController alloc] init];
    NSVisualEffectView *sidebarEffectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 260, 600)];
    sidebarEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebarEffectView.material = NSVisualEffectMaterialSidebar;
    sidebarEffectView.state = NSVisualEffectStateActive;
    sidebarVC.view = sidebarEffectView;
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:sidebarEffectView.bounds];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = NO;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebarEffectView addSubview:scrollView];
    
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:sidebarEffectView.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:sidebarEffectView.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:sidebarEffectView.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:sidebarEffectView.bottomAnchor]
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
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    scrollView.documentView = self.tableView;
    
    // 2. Detail View Setup
    NSViewController *detailVC = [[NSViewController alloc] init];
    self.detailView = [[NSView alloc] init];
    self.detailView.wantsLayer = YES;
    self.detailView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    detailVC.view = self.detailView;
    
    self.detailTitleLabel = [[NSTextField alloc] init];
    self.detailTitleLabel.editable = NO;
    self.detailTitleLabel.bezeled = NO;
    self.detailTitleLabel.drawsBackground = NO;
    self.detailTitleLabel.stringValue = @"Welcome to ScuttleRoom";
    self.detailTitleLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    self.detailTitleLabel.textColor = [NSColor labelColor];
    self.detailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailTitleLabel.alignment = NSTextAlignmentCenter;
    [self.detailView addSubview:self.detailTitleLabel];
    
    self.detailStatusLabel = [[NSTextField alloc] init];
    self.detailStatusLabel.editable = NO;
    self.detailStatusLabel.bezeled = NO;
    self.detailStatusLabel.drawsBackground = NO;
    self.detailStatusLabel.stringValue = @"Select a peer to view details";
    self.detailStatusLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    self.detailStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.detailStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailStatusLabel.alignment = NSTextAlignmentCenter;
    [self.detailView addSubview:self.detailStatusLabel];
    
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
    
    [NSLayoutConstraint activateConstraints:@[
        [self.detailTitleLabel.centerXAnchor constraintEqualToAnchor:self.detailView.centerXAnchor],
        [self.detailTitleLabel.centerYAnchor constraintEqualToAnchor:self.detailView.centerYAnchor constant:-40],
        [self.detailStatusLabel.centerXAnchor constraintEqualToAnchor:self.detailView.centerXAnchor],
        [self.detailStatusLabel.topAnchor constraintEqualToAnchor:self.detailTitleLabel.bottomAnchor constant:8],
        [self.metaStackFrame.centerXAnchor constraintEqualToAnchor:self.detailView.centerXAnchor],
        [self.metaStackFrame.topAnchor constraintEqualToAnchor:self.detailStatusLabel.bottomAnchor constant:40]
    ]];
    
    // 3. Split View Integration
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
    sidebarItem.minimumThickness = 260;
    sidebarItem.maximumThickness = 450;
    sidebarItem.canCollapse = NO;
    [splitVC addSplitViewItem:sidebarItem];
    
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailVC];
    [splitVC addSplitViewItem:detailItem];
    
    splitVC.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    
    self.window.contentViewController = splitVC;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    
    // 4. Room Client Connection
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned char pk[32];
        unsigned char sk[64];
        crypto_sign_keypair(pk, sk);
        NSData *localId = [NSData dataWithBytes:sk length:64];
        NSData *serverPubKey = [[NSData alloc] initWithBase64EncodedString:@"M7ZZ64w2VjK92RlKZkdUldyq3f0o/4bGHaQWoW71Yoc=" options:0];
        self.client = [[SSBRoomClient alloc] initWithHost:@"127.0.0.1" port:8008 serverPubKey:serverPubKey localIdentity:localId];
        self.client.delegate = self;
        [self.client connect];
    });
}

#pragma mark - SSBRoomClientDelegate
- (void)roomClientDidConnect:(SSBRoomClient *)client {
    [client announce];
    [client subscribeToEndpoints];
}
- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    self.endpoints = endpoints;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - TableView
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.endpoints.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    PeerCellView *cell = [tableView makeViewWithIdentifier:@"PeerCell" owner:self];
    if (!cell) {
        cell = [[PeerCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 44)];
        cell.identifier = @"PeerCell";
    }
    cell.pubKeyLabel.stringValue = self.endpoints[row];
    NSUInteger hash = [self.endpoints[row] hash];
    cell.avatarView.layer.backgroundColor = [NSColor colorWithHue:(hash % 255) / 255.0 saturation:0.6 brightness:0.9 alpha:1.0].CGColor;
    return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && row < self.endpoints.count) {
        self.detailTitleLabel.stringValue = self.endpoints[row];
        self.detailStatusLabel.stringValue = @"ONLINE / DISCOVERED VIA ROOM";
        self.metaStackFrame.hidden = NO;
        self.latencyCard.valueLabel.stringValue = [NSString stringWithFormat:@"%d ms", 15 + (arc4random() % 20)];
    } else {
        self.detailTitleLabel.stringValue = @"Welcome to ScuttleRoom";
        self.detailStatusLabel.stringValue = @"Select a peer to view details";
        self.metaStackFrame.hidden = YES;
    }
}

@end
