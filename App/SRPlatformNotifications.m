#import "SRPlatformNotifications.h"
#import "SRPlatformUI.h"

#ifdef __APPLE__
#import <UserNotifications/UserNotifications.h>
#endif

@implementation SRPlatformNotifications

+ (instancetype)sharedNotifications {
    static SRPlatformNotifications *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRPlatformNotifications alloc] init];
    });
    return shared;
}

- (void)configure {
#ifdef __APPLE__
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                          completionHandler:^(__unused BOOL granted, __unused NSError * _Nullable error) {
                          }];
#endif
}

- (void)postMessageFromAuthor:(NSString *)author text:(NSString *)text {
#ifdef __APPLE__
    UNMutableNotificationContent *notifContent = [[UNMutableNotificationContent alloc] init];
    notifContent.title = [NSString stringWithFormat:@"Message from %@", author];
    notifContent.body = text.length > 0 ? text : @"New message";
    notifContent.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                          content:notifContent
                                                                          trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
#else
    NSLog(@"[Notifications] %@: %@", author, text);
#endif
}

@end
