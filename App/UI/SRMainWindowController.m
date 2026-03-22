#import "SRMainWindowController.h"
#import "SRWorkspaceViewController.h"

@interface SRMainWindowController ()
@property (nonatomic, strong) SRWorkspaceViewController *mainVC;
@end

@implementation SRMainWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                                    styleMask:NSWindowStyleMaskTitled | 
                                                              NSWindowStyleMaskClosable | 
                                                              NSWindowStyleMaskMiniaturizable | 
                                                              NSWindowStyleMaskResizable | 
                                                              NSWindowStyleMaskFullSizeContentView
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    
    window.title = @"ScuttleRoom";
    window.releasedWhenClosed = NO;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titlebarAppearsTransparent = YES;
    window.contentMinSize = NSMakeSize(900, 600);
    window.tabbingMode = NSWindowTabbingModeAutomatic;
    
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _mainVC = [[SRWorkspaceViewController alloc] init];
        window.contentViewController = _mainVC;

        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        window.toolbar = toolbar;
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
}

@end
