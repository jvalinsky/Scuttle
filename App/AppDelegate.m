#import "AppDelegate.h"
#import "Logic/SRRoomManager.h"
#import "UI/SRMainSplitViewController.h"
#import <os/log.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate ()
@property (nonatomic, strong) SRMainSplitViewController *mainVC;
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"[AppDelegate] Application did finish launching");
    [self setupStatusItem];
    
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = (id<UNUserNotificationCenterDelegate>)self;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (granted) {
            NSLog(@"[AppDelegate] Notifications granted");
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
    
    self.mainVC = [[SRMainSplitViewController alloc] init];
    self.window.contentViewController = self.mainVC;
    
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    toolbar.delegate = (id<NSToolbarDelegate>)self.mainVC;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    self.window.toolbar = toolbar;
    
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    
    // Initialize Room Manager
    NSLog(@"[AppDelegate] Initializing RoomManager");
    [SRRoomManager sharedManager];
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Preferences..." action:@selector(showPreferences:) keyEquivalent:@","];
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
    if ([self.mainVC respondsToSelector:@selector(showPreferences)]) {
        [self.mainVC performSelector:@selector(showPreferences)];
    }
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:@"ScuttleKit"];
    
    [self updateStatusMenu];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatusMenu) name:SRRoomManagerDidUpdateRoomsNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessageNotification:) name:@"SRNewMessageNotification" object:nil];
}

- (void)handleNewMessageNotification:(NSNotification *)notification {
    NSDictionary *msgDict = notification.object;
    if (![msgDict isKindOfClass:[NSDictionary class]]) return;
    
    NSDictionary *content = msgDict[@"content"];
    if (![content isKindOfClass:[NSDictionary class]]) return;
    
    NSString *text = content[@"text"] ?: @"New message";
    NSString *author = msgDict[@"author"] ?: @"Someone";
    
    UNMutableNotificationContent *notifContent = [[UNMutableNotificationContent alloc] init];
    notifContent.title = [NSString stringWithFormat:@"Message from %@", author];
    notifContent.body = text;
    notifContent.sound = [UNNotificationSound defaultSound];
    
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:notifContent trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
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
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SRRoomSelectedNotification" object:room];
}

- (void)bringToFront:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

@end