#import "SRKeyboardShortcuts.h"

@implementation SRKeyboardShortcutInfo
@end

@implementation SRKeyboardShortcuts

+ (NSArray<SRKeyboardShortcutInfo *> *)allShortcuts {
    static NSArray *shortcuts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shortcuts = [self buildShortcuts];
    });
    return shortcuts;
}

+ (NSArray<SRKeyboardShortcutInfo *> *)buildShortcuts {
    NSArray *defs = @[
        @[@"J",  @"",  @"Next post"],
        @[@"K",  @"",  @"Previous post"],
        @[@"L",  @"",  @"Like focused post"],
        @[@"R",  @"",  @"Reply to focused post"],
        @[@"↩",  @"",  @"Open thread for focused post"],
        @[@",",  @"⌘", @"Open Settings"],
        @[@"R",  @"⌘", @"Refresh feed"],
    ];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:defs.count];
    for (NSArray *def in defs) {
        SRKeyboardShortcutInfo *info = [[SRKeyboardShortcutInfo alloc] init];
        info.key = def[0];
        info.modifiers = def[1];
        info.title = def[2];
        [result addObject:info];
    }
    return [result copy];
}

@end
