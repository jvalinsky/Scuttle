#import "SRAnimations.h"
#import <QuartzCore/QuartzCore.h>

@implementation SRAnimations

+ (void)fadeInView:(NSView *)view duration:(NSTimeInterval)duration {
    view.alphaValue = 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        view.animator.alphaValue = 1.0;
    }];
}

+ (void)fadeOutView:(NSView *)view duration:(NSTimeInterval)duration completion:(nullable void(^)(void))completion {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        view.animator.alphaValue = 0.0;
    } completionHandler:^{
        if (completion) {
            completion();
        }
    }];
}

+ (void)crossfadeFromView:(NSView *)fromView toView:(NSView *)toView duration:(NSTimeInterval)duration completion:(nullable void(^)(void))completion {
    toView.alphaValue = 0.0;
    toView.hidden = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        fromView.animator.alphaValue = 0.0;
        toView.animator.alphaValue = 1.0;
    } completionHandler:^{
        fromView.hidden = YES;
        if (completion) {
            completion();
        }
    }];
}

+ (void)slideInView:(NSView *)view fromDirection:(SRSlideDirection)direction duration:(NSTimeInterval)duration {
    NSRect originalFrame = view.frame;
    NSRect offscreenFrame = originalFrame;

    switch (direction) {
        case SRSlideDirectionLeft:
            offscreenFrame.origin.x -= NSWidth(originalFrame);
            break;
        case SRSlideDirectionRight:
            offscreenFrame.origin.x += NSWidth(originalFrame);
            break;
        case SRSlideDirectionUp:
            offscreenFrame.origin.y += NSHeight(originalFrame);
            break;
        case SRSlideDirectionDown:
            offscreenFrame.origin.y -= NSHeight(originalFrame);
            break;
    }

    view.frame = offscreenFrame;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        view.animator.frame = originalFrame;
    }];
}

+ (void)animateLayoutChanges:(void(^)(void))changes inView:(NSView *)view duration:(NSTimeInterval)duration {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        if (changes) {
            changes();
        }
        [view layoutSubtreeIfNeeded];
    }];
}

@end
