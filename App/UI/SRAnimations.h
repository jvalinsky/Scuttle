#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SRSlideDirection) {
    SRSlideDirectionLeft,
    SRSlideDirectionRight,
    SRSlideDirectionUp,
    SRSlideDirectionDown
};

NS_ASSUME_NONNULL_BEGIN

@interface SRAnimations : NSObject

+ (void)fadeInView:(NSView *)view duration:(NSTimeInterval)duration;
+ (void)fadeOutView:(NSView *)view duration:(NSTimeInterval)duration completion:(nullable void(^)(void))completion;
+ (void)crossfadeFromView:(NSView *)fromView toView:(NSView *)toView duration:(NSTimeInterval)duration completion:(nullable void(^)(void))completion;
+ (void)slideInView:(NSView *)view fromDirection:(SRSlideDirection)direction duration:(NSTimeInterval)duration;
+ (void)animateLayoutChanges:(void(^)(void))changes inView:(NSView *)view duration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
