#import "AppDelegate.h"
#import "Logic/SRRoomManager.h"
#import "Logic/SRNotificationNames.h"
#import "Logic/SRGitRemoteHelperServer.h"
#import "UI/SRMainSplitViewController.h"
#import "UI/SRSettingsWindowController.h"
#import "SRPlatformNotifications.h"
#import "../Sources/SSBLogCompat.h"

static os_log_t ssb_app_log;

@interface AppDelegate ()
@property (nonatomic, strong) SRMainSplitViewController *mainVC;
#ifdef __APPLE__
@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
#else
@property (nonatomic, strong, nullable) id statusItem;
#endif
@end

@implementation AppDelegate

+ (void)initialize {
    if (self == [AppDelegate class]) {
        ssb_app_log = os_log_create("com.scuttlebutt.app", "AppDelegate");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    os_log_info(ssb_app_log, "Application did finish launching");
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self setupMenu];
    
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.window.title = @"ScuttleRoom";
    self.window.releasedWhenClosed = NO;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
    self.window.titlebarAppearsTransparent = YES;
    self.window.contentMinSize = NSMakeSize(900, 600);
    self.window.tabbingMode = NSWindowTabbingModeAutomatic;
    self.window.contentViewController = [[NSViewController alloc] init];
    
    @try {
        [self.window center];
        [self.window makeKeyAndOrderFront:nil];
        [self.window orderFrontRegardless];
        [self bringToFront:nil];
    } @catch (NSException *exception) {
        @throw exception;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.mainVC = [[SRMainSplitViewController alloc] init];
        self.window.contentViewController = self.mainVC;

        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
        toolbar.delegate = self.mainVC;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        self.window.toolbar = toolbar;

        [self.window makeKeyAndOrderFront:nil];
        [self.window orderFrontRegardless];
        [self bringToFront:nil];
    });

    [self setupStatusItem];
    
    [[SRPlatformNotifications sharedNotifications] configure];
    
    // Initialize Room Manager
    os_log_info(ssb_app_log, "Initializing RoomManager");
    [SRRoomManager sharedManager];
    
    // Start Git Helper Server
    [[SRGitRemoteHelperServer sharedServer] start];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[SRGitRemoteHelperServer sharedServer] stop];
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // App menu
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Settings..." action:@selector(showPreferences:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Reset Identity..." action:@selector(resetIdentity:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu setSubmenu:appMenu forItem:appMenuItem];

    // File menu
    NSMenuItem *fileMenuItem = [mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Post" action:@selector(newPost:) keyEquivalent:@"n"];
    NSMenuItem *closeItem = [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    closeItem.target = NSApp;
    [mainMenu setSubmenu:fileMenu forItem:fileMenuItem];

    // Edit menu
    NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [mainMenu setSubmenu:editMenu forItem:editMenuItem];

    // View menu
    NSMenuItem *viewMenuItem = [mainMenu addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *toggleSidebarItem = [viewMenu addItemWithTitle:@"Toggle Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@"s"];
    toggleSidebarItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *togglePeerItem = [viewMenu addItemWithTitle:@"Toggle Peer List" action:@selector(togglePeerList:) keyEquivalent:@"p"];
    togglePeerItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fullScreenItem = [viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fullScreenItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
    [mainMenu setSubmenu:viewMenu forItem:viewMenuItem];

    // Navigate menu
    NSMenuItem *navigateMenuItem = [mainMenu addItemWithTitle:@"Navigate" action:NULL keyEquivalent:@""];
    NSMenu *navigateMenu = [[NSMenu alloc] initWithTitle:@"Navigate"];
    [navigateMenu addItemWithTitle:@"Back" action:@selector(navigateBack:) keyEquivalent:@"["];
    [navigateMenu addItem:[NSMenuItem separatorItem]];
    [navigateMenu addItemWithTitle:@"Home" action:@selector(navigateHome:) keyEquivalent:@"1"];
    [navigateMenu addItemWithTitle:@"Channels" action:@selector(navigateChannels:) keyEquivalent:@"2"];
    [navigateMenu addItemWithTitle:@"Repositories" action:@selector(navigateRepos:) keyEquivalent:@"3"];
    [mainMenu setSubmenu:navigateMenu forItem:navigateMenuItem];

    // Window menu
    NSMenuItem *windowMenuItem = [mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [mainMenu setSubmenu:windowMenu forItem:windowMenuItem];
    [NSApp setWindowsMenu:windowMenu];

    // Help menu
    NSMenuItem *helpMenuItem = [mainMenu addItemWithTitle:@"Help" action:NULL keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *shortcutsItem = [helpMenu addItemWithTitle:@"Keyboard Shortcuts" action:@selector(showKeyboardShortcuts:) keyEquivalent:@"?"];
    shortcutsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [mainMenu setSubmenu:helpMenu forItem:helpMenuItem];

    [NSApp setMainMenu:mainMenu];
}

- (void)showPreferences:(id)sender {
    [[SRSettingsWindowController sharedSettingsWindowController] showSettings];
}

- (void)newPost:(id)sender {
    // Routed through the responder chain to the active view controller
}

- (void)resetIdentity:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset Identity?";
    alert.informativeText = @"This will permanently delete your SSB identity, all messages, and disconnect from all rooms. This cannot be undone.";
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleCritical;
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[SRRoomManager sharedManager] resetAccount];
    }
}

- (void)setupStatusItem {
#ifdef __APPLE__
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [self.statusItem button].image = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:@"ScuttleKit"];
    [self updateStatusMenu];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatusMenu) name:SRRoomManagerDidUpdateRoomsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessageNotification:) name:SRNewMessageNotification object:nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessageNotification:) name:SRNewMessageNotification object:nil];
#endif
}

- (void)handleNewMessageNotification:(NSNotification *)notification {
    id msgObj = notification.userInfo[SRNewMessageKey];
    NSDictionary *content = nil;
    NSString *author = @"Someone";
    if ([msgObj respondsToSelector:@selector(content)]) {
        content = [msgObj valueForKey:@"content"];
        NSString *msgAuthor = [msgObj valueForKey:@"author"];
        if (msgAuthor.length > 0) author = msgAuthor;
    }
    if (![content isKindOfClass:[NSDictionary class]]) return;

    NSString *text = content[@"text"] ?: @"New message";
    
    [[SRPlatformNotifications sharedNotifications] postMessageFromAuthor:author text:text];
}

- (void)updateStatusMenu {
#ifndef __APPLE__
    return;
#else
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"ScuttleKit" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSArray *rooms = [SRRoomManager sharedManager].rooms;
    for (RoomConfig *room in rooms) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:room.host action:@selector(statusItemRoomAction:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = room;
        SSBRoomClient *client = [[SRRoomManager sharedManager] clientForHost:room.host];
        if (client.isConnected) {
            item.state = NSControlStateValueOn;
        }
        [menu addItem:item];
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Bring to Front" action:@selector(bringToFront:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    
    self.statusItem.menu = menu;
#endif
}

- (void)statusItemRoomAction:(NSMenuItem *)sender {
    RoomConfig *room = sender.representedObject;
    [self.window makeKeyAndOrderFront:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerRoomSelectedNotification
                                                        object:nil
                                                      userInfo:@{SRRoomManagerRoomSelectedKey: room}];
}

+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
    completionHandler(delegate.window, nil);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [self.window makeKeyAndOrderFront:nil];
    }
    return NO;
}

- (void)bringToFront:(id)sender {
#ifdef __APPLE__
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    }
#endif
    [self.window makeKeyAndOrderFront:nil];
}

@end
