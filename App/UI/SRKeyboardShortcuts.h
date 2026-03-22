#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// App-wide keyboard shortcut constants for ScuttleRoom.
///
/// Feed navigation (when feed or thread view has focus):
///   J  — next post
///   K  — previous post
///   L  — like focused post
///   R  — reply to focused post / open thread
///   ↩  — open thread for focused post
///
/// Global:
///   ⌘,  — open Settings (system-provided via menu)
///   ⌘R  — refresh feed (toolbar item)
///   ⌘N  — compose (toolbar item, key equivalent set in nib/menu)

typedef NS_ENUM(unichar, SRFeedShortcut) {
    SRFeedShortcutNextItem  = 'j',
    SRFeedShortcutPrevItem  = 'k',
    SRFeedShortcutLike      = 'l',
    SRFeedShortcutReply     = 'r',
    SRFeedShortcutOpen      = '\r',   // Return
};

/// Describes a single keyboard shortcut for display in help UI.
@interface SRKeyboardShortcutInfo : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *modifiers; // e.g. @"" or @"⌘"
@property (nonatomic, copy) NSString *title;
@end

@interface SRKeyboardShortcuts : NSObject

/// All registered shortcut descriptors, for display in help/settings.
+ (NSArray<SRKeyboardShortcutInfo *> *)allShortcuts;

@end

NS_ASSUME_NONNULL_END
