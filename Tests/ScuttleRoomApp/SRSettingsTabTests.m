#import <XCTest/XCTest.h>
#import "SRSettingsGeneralViewController.h"
#import "SRSettingsIdentityViewController.h"
#import "SRSettingsStorageViewController.h"
#import "SRSettingsAdvancedViewController.h"

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

@end
