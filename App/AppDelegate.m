#import "AppDelegate.h"
#import "Logic/SRRoomManager.h"
#import "Logic/SRNotificationNames.h"
#import "UI/SRMainSplitViewController.h"
#import <os/log.h>
#import <UserNotifications/UserNotifications.h>

static os_log_t ssb_app_log;

@interface AppDelegate ()
@property (nonatomic, strong) SRMainSplitViewController *mainVC;
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation AppDelegate

+ (void)initialize {
    if (self == [AppDelegate class]) {
        ssb_app_log = os_log_create("com.scuttlebutt.app", "AppDelegate");
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    os_log_info(ssb_app_log, "Application did finish launching");
    [self setupStatusItem];
    
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (granted) {
            os_log_info(ssb_app_log, "Notifications granted");
        }
    }];
    
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self setupMenu];
    
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.window.title = @"ScuttleRoom";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.identifier = @"ScuttleRoomMainWindow";
    self.window.restorationClass = [AppDelegate class];
    
    self.mainVC = [[SRMainSplitViewController alloc] init];
    self.window.contentViewController = self.mainVC;
    
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    toolbar.delegate = self.mainVC;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    self.window.toolbar = toolbar;
    
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    
    // Initialize Room Manager
    os_log_info(ssb_app_log, "Initializing RoomManager");
    [SRRoomManager sharedManager];
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
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:@"ScuttleKit"];
    
    [self updateStatusMenu];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatusMenu) name:SRRoomManagerDidUpdateRoomsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessageNotification:) name:SRNewMessageNotification object:nil];
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
    
    UNMutableNotificationContent *notifContent = [[UNMutableNotificationContent alloc] init];
    notifContent.title = [NSString stringWithFormat:@"Message from %@", author];
    notifContent.body = text;
    notifContent.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:notifContent trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (void)updateStatusMenu {
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
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    }
    [self.window makeKeyAndOrderFront:nil];
}

@end