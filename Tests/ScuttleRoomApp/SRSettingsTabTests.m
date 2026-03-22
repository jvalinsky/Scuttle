#import <XCTest/XCTest.h>
#import "SRSettingsGeneralViewController.h"
#import "SRSettingsIdentityViewController.h"
#import "SRSettingsStorageViewController.h"
#import "SRSettingsAdvancedViewController.h"

/// Collect all NSButton subviews recursively from a view hierarchy.
static NSArray<NSButton *> *allButtons(NSView *view) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSView *sub in view.subviews) {
        if ([sub isKindOfClass:[NSButton class]]) {
            [result addObject:(NSButton *)sub];
        }
        [result addObjectsFromArray:allButtons(sub)];
    }
    return result;
}

@interface SRSettingsTabTests : XCTestCase
@end

@implementation SRSettingsTabTests

- (void)testGeneralVCLoads {
    SRSettingsGeneralViewController *vc = [[SRSettingsGeneralViewController alloc] init];
    [vc loadView];
    XCTAssertNotNil(vc.view);
}

- (void)testIdentityVCLoads {
    SRSettingsIdentityViewController *vc = [[SRSettingsIdentityViewController alloc] init];
    [vc loadView];
    XCTAssertNotNil(vc.view);
}

- (void)testStorageVCLoads {
    SRSettingsStorageViewController *vc = [[SRSettingsStorageViewController alloc] init];
    [vc loadView];
    XCTAssertNotNil(vc.view);
}

- (void)testAdvancedVCLoads {
    SRSettingsAdvancedViewController *vc = [[SRSettingsAdvancedViewController alloc] init];
    [vc loadView];
    XCTAssertNotNil(vc.view);
}

- (void)testGeneralVC_saveButtonHasAction {
    SRSettingsGeneralViewController *vc = [[SRSettingsGeneralViewController alloc] init];
    [vc loadView];
    NSArray<NSButton *> *buttons = allButtons(vc.view);
    NSButton *saveButton = nil;
    for (NSButton *b in buttons) {
        if ([b.title isEqualToString:@"Save"]) { saveButton = b; break; }
    }
    XCTAssertNotNil(saveButton, @"Save button should exist");
    XCTAssertNotNil(saveButton.target, @"Save button target should not be nil");
    XCTAssertNotEqual(saveButton.action, NULL, @"Save button action should not be NULL");
}

- (void)testIdentityVC_allButtonsHaveActions {
    SRSettingsIdentityViewController *vc = [[SRSettingsIdentityViewController alloc] init];
    [vc loadView];
    NSArray<NSButton *> *buttons = allButtons(vc.view);
    XCTAssertEqual(buttons.count, 4u, @"Identity VC should have 4 buttons");
    for (NSButton *b in buttons) {
        XCTAssertNotNil(b.target, @"Button '%@' target should not be nil", b.title);
        XCTAssertNotEqual(b.action, NULL, @"Button '%@' action should not be NULL", b.title);
    }
}

- (void)testStorageVC_wipeDatabaseButtonHasAction {
    SRSettingsStorageViewController *vc = [[SRSettingsStorageViewController alloc] init];
    [vc loadView];
    NSArray<NSButton *> *buttons = allButtons(vc.view);
    XCTAssertEqual(buttons.count, 1u, @"Storage VC should have 1 button");
    NSButton *wipe = buttons.firstObject;
    XCTAssertNotNil(wipe.target, @"Wipe button target should not be nil");
    XCTAssertNotEqual(wipe.action, NULL, @"Wipe button action should not be NULL");
}

- (void)testAdvancedVC_devPanelButtonHasAction {
    SRSettingsAdvancedViewController *vc = [[SRSettingsAdvancedViewController alloc] init];
    [vc loadView];
    NSArray<NSButton *> *buttons = allButtons(vc.view);
    // Dev Panel button (target:self) and Reset Identity (target:nil — responder chain)
    XCTAssertEqual(buttons.count, 2u, @"Advanced VC should have 2 buttons");

    NSButton *devPanel = nil;
    NSButton *resetIdentity = nil;
    for (NSButton *b in buttons) {
        if (b.target != nil) devPanel = b;
        else resetIdentity = b;
    }
    XCTAssertNotNil(devPanel, @"Dev Panel button should have a target");
    XCTAssertNotEqual(devPanel.action, NULL, @"Dev Panel button should have an action");
    // Reset Identity intentionally uses target:nil for responder chain routing
    XCTAssertNotNil(resetIdentity, @"Reset Identity button should exist");
    XCTAssertNotEqual(resetIdentity.action, NULL, @"Reset Identity should have an action (resetIdentity:)");
}

@end
