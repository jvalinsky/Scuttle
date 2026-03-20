#import "SRPlatformUI.h"

#ifdef __APPLE__
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowRestoration>
#else
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowRestoration>
#endif

@property (strong) NSWindow *window;

@end
