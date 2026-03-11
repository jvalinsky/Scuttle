#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRProfileHeaderView : NSView

- (void)updateWithIdentity:(NSString *)feedId name:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
