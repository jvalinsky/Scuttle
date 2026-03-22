#import "SRRoomWindowController.h"
#import "SRRoomManagementViewController.h"

@implementation SRRoomWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 450)
                                                    styleMask:NSWindowStyleMaskTitled | 
                                                              NSWindowStyleMaskClosable | 
                                                              NSWindowStyleMaskMiniaturizable | 
                                                              NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    
    window.title = @"Manage Rooms";
    window.releasedWhenClosed = NO;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titlebarAppearsTransparent = YES;
    window.contentMinSize = NSMakeSize(500, 350);
    
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        window.contentViewController = [[SRRoomManagementViewController alloc] init];
    }
    return self;
}

@end
