#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

@interface ScuttleDemoApp : NSApplication <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTextField *label;
@end

@implementation ScuttleDemoApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Create a basic window
    NSRect frame = NSMakeRect(100, 100, 400, 200);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [self.window setTitle:@"Scuttle GNUstep Demo"];
    
    // Create a label to show GCD is working
    self.label = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 80, 300, 40)];
    [self.label setStringValue:@"Initializing GCD..."];
    [self.label setBezeled:NO];
    [self.label setDrawsBackground:NO];
    [self.label setEditable:NO];
    [self.label setSelectable:NO];
    [self.label setAlignment:NSTextAlignmentCenter];
    [self.label setFont:[NSFont systemFontOfSize:18]];
    
    [[self.window contentView] addSubview:self.label];
    [self.window makeKeyAndOrderFront:nil];
    
    // Test libdispatch (GCD) integration
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.label setStringValue:@"GCD & GNUstep: Ready for Linux!"];
        NSLog(@"GCD Task Executed on Main Queue");
    });
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ScuttleDemoApp *app = [ScuttleDemoApp sharedApplication];
        [app setDelegate:app];
        return NSApplicationMain(argc, argv);
    }
}
