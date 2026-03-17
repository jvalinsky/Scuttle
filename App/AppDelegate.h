#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowRestoration>

@property (strong) NSWindow *window;

@end