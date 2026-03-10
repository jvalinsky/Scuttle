#import "AppDelegate.h"
#import "Logic/SRRoomManager.h"
#import "UI/SRMainSplitViewController.h"
#import <os/log.h>

@interface AppDelegate ()
@property (nonatomic, strong) SRMainSplitViewController *mainVC;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"[AppDelegate] Application did finish launching");
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self setupMenu];
    
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.window.title = @"ScuttleRoom";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    
    NSLog(@"[AppDelegate] Initializing MainSplitViewController");
    self.mainVC = [[SRMainSplitViewController alloc] init];
    self.window.contentViewController = self.mainVC;
    
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

@end