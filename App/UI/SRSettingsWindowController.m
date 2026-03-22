#import "SRSettingsWindowController.h"
#import "SRSettingsGeneralViewController.h"
#import "SRSettingsIdentityViewController.h"
#import "SRSettingsStorageViewController.h"
#import "SRSettingsAdvancedViewController.h"

@interface SRSettingsWindowController () <NSWindowDelegate>
@end

@implementation SRSettingsWindowController

+ (instancetype)sharedSettingsWindowController {
    static SRSettingsWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRSettingsWindowController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Settings";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;

        NSTabViewController *tabVC = [[NSTabViewController alloc] init];
        tabVC.tabStyle = NSTabViewControllerTabStyleToolbar;

        struct { NSString *label; NSString *symbol; NSViewController *vc; } tabs[] = {
            { @"General",  @"gearshape",                nil },
            { @"Identity", @"person.crop.circle",       nil },
            { @"Storage",  @"externaldrive",            nil },
            { @"Advanced", @"wrench.and.screwdriver",   nil },
        };
        tabs[0].vc = [[SRSettingsGeneralViewController alloc] init];
        tabs[1].vc = [[SRSettingsIdentityViewController alloc] init];
        tabs[2].vc = [[SRSettingsStorageViewController alloc] init];
        tabs[3].vc = [[SRSettingsAdvancedViewController alloc] init];

        for (int i = 0; i < 4; i++) {
            NSTabViewItem *item = [[NSTabViewItem alloc] init];
            item.label = tabs[i].label;
            item.image = [NSImage imageWithSystemSymbolName:tabs[i].symbol accessibilityDescription:tabs[i].label];
            item.viewController = tabs[i].vc;
            [tabVC addTabViewItem:item];
        }

        window.contentViewController = tabVC;
    }
    return self;
}

- (void)showSettings {
    [self.window makeKeyAndOrderFront:nil];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [sender orderOut:nil];
    return NO;
}

@end
