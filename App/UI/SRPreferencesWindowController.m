#import "SRPreferencesWindowController.h"
#import "SRPreferencesViewController.h"

@implementation SRPreferencesWindowController

+ (instancetype)sharedPreferencesWindowController {
    static SRPreferencesWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 750)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Settings";
        window.releasedWhenClosed = NO;
        window.acceptsMouseMovedEvents = YES;
        shared = [[SRPreferencesWindowController alloc] initWithWindow:window];
        window.contentViewController = [[SRPreferencesViewController alloc] init];
        window.delegate = shared;
    });
    return shared;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [sender orderOut:nil];
    return NO;
}

@end
