#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRPlatformNotifications : NSObject
+ (instancetype)sharedNotifications;
- (void)configure;
- (void)postMessageFromAuthor:(NSString *)author text:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
