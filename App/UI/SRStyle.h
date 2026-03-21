#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRStyle : NSObject

// MARK: - Typography
+ (NSFont *)headlineLargeFont;   // Bold 16pt - view titles
+ (NSFont *)headlineFont;        // Bold 13pt - card author names, section headers
+ (NSFont *)bodyFont;            // Regular 13pt - message text, general body
+ (NSFont *)captionFont;         // Regular 11pt - timestamps, secondary info
+ (NSFont *)caption2Font;        // Regular 10pt - sync status, tiny labels
+ (NSFont *)monoSmallFont;       // Monospaced 9pt - feed IDs
+ (NSFont *)monoMediumFont;      // Monospaced 11pt - peer IDs

// MARK: - Spacing
+ (CGFloat)spacingXS;            // 4pt
+ (CGFloat)spacingSM;            // 8pt
+ (CGFloat)spacingMD;            // 12pt
+ (CGFloat)spacingLG;            // 16pt
+ (CGFloat)spacingXL;            // 20pt
+ (CGFloat)spacingXXL;           // 32pt

// MARK: - Corner Radii
+ (CGFloat)cornerRadiusSmall;    // 4pt - badges, small elements
+ (CGFloat)cornerRadiusMedium;   // 8pt - cards, compose box
+ (CGFloat)cornerRadiusLarge;    // 12pt - overlays, sheets
+ (CGFloat)cornerRadiusRound;    // 16pt - avatars

// MARK: - Avatar Sizes
+ (CGFloat)avatarSizeSmall;      // 28pt - peer list
+ (CGFloat)avatarSizeMedium;     // 32pt - feed items, headers
+ (CGFloat)avatarSizeLarge;      // 48pt - profile view

// MARK: - Colors (semantic, dark-mode-aware)
+ (NSColor *)cardBackgroundColor;
+ (NSColor *)cardBorderColor;
+ (NSColor *)surfaceColor;
+ (NSColor *)accentColor;        // Respects system accent color
+ (NSColor *)dangerColor;
+ (NSColor *)warningColor;
+ (NSColor *)successColor;

// MARK: - Shadows
+ (NSShadow *)cardShadow;
+ (NSShadow *)elevatedShadow;

// MARK: - Convenience
+ (void)styleCardView:(NSView *)view;
+ (void)styleAvatarView:(NSView *)view size:(CGFloat)size hash:(NSUInteger)hash;
+ (NSView *)createAvatarViewWithSize:(CGFloat)size hash:(NSUInteger)hash;

@end

NS_ASSUME_NONNULL_END
