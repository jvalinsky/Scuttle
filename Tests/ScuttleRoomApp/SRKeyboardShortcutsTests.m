#import <XCTest/XCTest.h>
#import "SRKeyboardShortcuts.h"

@interface SRKeyboardShortcutsTests : XCTestCase
@end

@implementation SRKeyboardShortcutsTests

- (void)testAllShortcuts_returnsNonEmptyArray {
    NSArray *shortcuts = [SRKeyboardShortcuts allShortcuts];
    XCTAssertNotNil(shortcuts);
    XCTAssertGreaterThan(shortcuts.count, 0u);
}

- (void)testAllShortcuts_eachHasRequiredFields {
    for (SRKeyboardShortcutInfo *info in [SRKeyboardShortcuts allShortcuts]) {
        XCTAssertNotNil(info.key,       @"key must not be nil");
        XCTAssertNotNil(info.modifiers, @"modifiers must not be nil");
        XCTAssertNotNil(info.title,     @"title must not be nil");
        XCTAssertGreaterThan(info.title.length, 0u, @"title must be non-empty");
    }
}

- (void)testFeedShortcuts_jkrlDefined {
    XCTAssertEqual(SRFeedShortcutNextItem, (unichar)'j');
    XCTAssertEqual(SRFeedShortcutPrevItem, (unichar)'k');
    XCTAssertEqual(SRFeedShortcutLike,    (unichar)'l');
    XCTAssertEqual(SRFeedShortcutReply,   (unichar)'r');
    XCTAssertEqual(SRFeedShortcutOpen,    (unichar)'\r');
}

- (void)testAllShortcuts_containsJKLREntries {
    NSArray *shortcuts = [SRKeyboardShortcuts allShortcuts];
    NSArray<NSString *> *keys = [shortcuts valueForKey:@"key"];
    XCTAssertTrue([keys containsObject:@"J"], @"Should define J shortcut");
    XCTAssertTrue([keys containsObject:@"K"], @"Should define K shortcut");
    XCTAssertTrue([keys containsObject:@"L"], @"Should define L shortcut");
    XCTAssertTrue([keys containsObject:@"R"], @"Should define R shortcut");
}

- (void)testAllShortcuts_cachedAcrossCalls {
    NSArray *first = [SRKeyboardShortcuts allShortcuts];
    NSArray *second = [SRKeyboardShortcuts allShortcuts];
    XCTAssertEqual(first, second, @"allShortcuts should return same cached instance");
}

@end
