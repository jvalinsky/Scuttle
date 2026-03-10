#import "SRPreferencesWindowController.h"
#import "SRPreferencesViewController.h"

@implementation SRPreferencesWindowController

+ (instancetype)sharedPreferencesWindowController {
    static SRPreferencesWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Preferences";
        shared = [[SRPreferencesWindowController alloc] initWithWindow:window];
        window.contentViewController = [[SRPreferencesViewController alloc] init];
    });
    return shared;
}

@end
