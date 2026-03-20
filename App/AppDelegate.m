#import "AppDelegate.h"
#import "Logic/SRRoomManager.h"
#import "Logic/SRNotificationNames.h"
#import "Logic/SRGitRemoteHelperServer.h"
#import "UI/SRMainSplitViewController.h"
#import "SRPlatformNotifications.h"
#import "../Sources/SSBLogCompat.h"

static os_log_t ssb_app_log;

static void SRAppendStartupLog(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = @"/tmp/scuttleroomapp-startup.log";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

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
        SRAppendStartupLog(@"AppDelegate class initialize");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        SRAppendStartupLog(@"AppDelegate init");
    }
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    SRAppendStartupLog(@"applicationWillFinishLaunching");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    SRAppendStartupLog(@"applicationDidFinishLaunching");
    os_log_info(ssb_app_log, "Application did finish launching");
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    SRAppendStartupLog(@"activation policy set");
    [self setupMenu];
    SRAppendStartupLog(@"main menu installed");
    
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    SRAppendStartupLog(@"window allocated");
    self.window.title = @"ScuttleRoom";
    self.window.releasedWhenClosed = NO;
    self.window.contentViewController = [[NSViewController alloc] init];
    SRAppendStartupLog(@"placeholder content controller installed");
    
    @try {
        [self.window center];
        SRAppendStartupLog(@"window centered");
        [self.window makeKeyAndOrderFront:nil];
        SRAppendStartupLog(@"window made key and ordered front");
        [self.window orderFrontRegardless];
        SRAppendStartupLog(@"window orderFrontRegardless complete");
        [self bringToFront:nil];
        SRAppendStartupLog([NSString stringWithFormat:@"window ordered front visible=%d windows=%lu",
                            self.window.isVisible,
                            (unsigned long)NSApp.windows.count]);
    } @catch (NSException *exception) {
        SRAppendStartupLog([NSString stringWithFormat:@"window bootstrap exception: %@ %@", exception.name, exception.reason]);
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
        SRAppendStartupLog([NSString stringWithFormat:@"main UI installed visible=%d windows=%lu",
                            self.window.isVisible,
                            (unsigned long)NSApp.windows.count]);
    });

    [self setupStatusItem];
    SRAppendStartupLog(@"status item installed");
    
    [[SRPlatformNotifications sharedNotifications] configure];
    SRAppendStartupLog(@"notification authorization requested");
    
    // Initialize Room Manager
    os_log_info(ssb_app_log, "Initializing RoomManager");
    [SRRoomManager sharedManager];
    SRAppendStartupLog(@"room manager initialized");
    
    // Start Git Helper Server
    [[SRGitRemoteHelperServer sharedServer] start];
    SRAppendStartupLog(@"git helper server started");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    SRAppendStartupLog(@"applicationWillTerminate");
    [[SRGitRemoteHelperServer sharedServer] stop];
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Preferences..." action:@selector(showPreferences:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Reset Identity..." action:@selector(resetIdentity:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu setSubmenu:appMenu forItem:appMenuItem];
    
    NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [mainMenu setSubmenu:editMenu forItem:editMenuItem];
    
    [NSApp setMainMenu:mainMenu];
}

- (void)showPreferences:(id)sender {
    [self.mainVC showPreferences];
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
