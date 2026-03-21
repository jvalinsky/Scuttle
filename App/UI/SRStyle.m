#import "SRStyle.h"

@implementation SRStyle

#pragma mark - Typography

+ (NSFont *)headlineLargeFont {
    return [NSFont boldSystemFontOfSize:16.0];
}

+ (NSFont *)headlineFont {
    return [NSFont boldSystemFontOfSize:13.0];
}

+ (NSFont *)bodyFont {
    return [NSFont systemFontOfSize:13.0];
}

+ (NSFont *)captionFont {
    return [NSFont systemFontOfSize:11.0];
}

+ (NSFont *)caption2Font {
    return [NSFont systemFontOfSize:10.0];
}

+ (NSFont *)monoSmallFont {
    return [NSFont monospacedSystemFontOfSize:9.0 weight:NSFontWeightRegular];
}

+ (NSFont *)monoMediumFont {
    return [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
}

#pragma mark - Spacing

+ (CGFloat)spacingXS {
    return 4.0;
}

+ (CGFloat)spacingSM {
    return 8.0;
}

+ (CGFloat)spacingMD {
    return 12.0;
}

+ (CGFloat)spacingLG {
    return 16.0;
}

+ (CGFloat)spacingXL {
    return 20.0;
}

+ (CGFloat)spacingXXL {
    return 32.0;
}

#pragma mark - Corner Radii

+ (CGFloat)cornerRadiusSmall {
    return 4.0;
}

+ (CGFloat)cornerRadiusMedium {
    return 8.0;
}

+ (CGFloat)cornerRadiusLarge {
    return 12.0;
}

+ (CGFloat)cornerRadiusRound {
    return 16.0;
}

#pragma mark - Avatar Sizes

+ (CGFloat)avatarSizeSmall {
    return 28.0;
}

+ (CGFloat)avatarSizeMedium {
    return 32.0;
}

+ (CGFloat)avatarSizeLarge {
    return 48.0;
}

#pragma mark - Colors

+ (NSColor *)cardBackgroundColor {
    return NSColor.controlBackgroundColor;
}

+ (NSColor *)cardBorderColor {
    return NSColor.separatorColor;
}

+ (NSColor *)surfaceColor {
    return NSColor.windowBackgroundColor;
}

+ (NSColor *)accentColor {
    return NSColor.controlAccentColor;
}

+ (NSColor *)dangerColor {
    return NSColor.systemRedColor;
}

+ (NSColor *)warningColor {
    return NSColor.systemOrangeColor;
}

+ (NSColor *)successColor {
    return NSColor.systemGreenColor;
}

#pragma mark - Shadows

+ (NSShadow *)cardShadow {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor.shadowColor colorWithAlphaComponent:0.12];
    shadow.shadowOffset = NSMakeSize(0, -1);
    shadow.shadowBlurRadius = 4.0;
    return shadow;
}

+ (NSShadow *)elevatedShadow {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor.shadowColor colorWithAlphaComponent:0.20];
    shadow.shadowOffset = NSMakeSize(0, -2);
    shadow.shadowBlurRadius = 8.0;
    return shadow;
}

#pragma mark - Convenience

+ (void)styleCardView:(NSView *)view {
    view.wantsLayer = YES;
    view.layer.cornerRadius = [self cornerRadiusMedium];
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [self cardBorderColor].CGColor;
    view.layer.backgroundColor = [self cardBackgroundColor].CGColor;
    view.shadow = [self cardShadow];
}

+ (void)styleAvatarView:(NSView *)view size:(CGFloat)size hash:(NSUInteger)hash {
    view.wantsLayer = YES;
    view.layer.cornerRadius = size / 2.0;
    CGFloat hue = (hash % 360) / 360.0;
    NSColor *color = [NSColor colorWithCalibratedHue:hue saturation:0.5 brightness:0.7 alpha:1.0];
    view.layer.backgroundColor = color.CGColor;
}

+ (NSView *)createAvatarViewWithSize:(CGFloat)size hash:(NSUInteger)hash {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size, size)];
    [self styleAvatarView:view size:size hash:hash];
    return view;
}

@end
