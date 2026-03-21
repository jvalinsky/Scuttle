#import <XCTest/XCTest.h>
#import "SSBPlatformUI.h"

/// Fake that records the last alert presented.
@interface FakePlatformUI : NSObject <SSBPlatformUIProtocol>
@property (nonatomic, strong) NSAlert *lastAlert;
@property (nonatomic, assign) NSModalResponse stubbedResponse;
@end

@implementation FakePlatformUI
- (NSModalResponse)runModalAlert:(NSAlert *)alert {
    self.lastAlert = alert;
    return self.stubbedResponse;
}
@end

@interface SSBPlatformUITests : XCTestCase
@property (nonatomic, strong) id<SSBPlatformUIProtocol> savedShared;
@end

@implementation SSBPlatformUITests

- (void)setUp {
    [super setUp];
    self.savedShared = [SSBPlatformUI shared];
}

- (void)tearDown {
    [SSBPlatformUI setShared:self.savedShared];
    [super tearDown];
}

- (void)testShared_isNotNilByDefault {
    XCTAssertNotNil([SSBPlatformUI shared]);
}

- (void)testShared_isSSBPlatformUIByDefault {
    XCTAssertTrue([[SSBPlatformUI shared] isKindOfClass:[SSBPlatformUI class]]);
}

- (void)testSetShared_replacesImplementation {
    FakePlatformUI *fake = [[FakePlatformUI alloc] init];
    [SSBPlatformUI setShared:fake];
    XCTAssertEqual([SSBPlatformUI shared], fake);
}

- (void)testSetShared_nil_restoresDefault {
    [SSBPlatformUI setShared:nil];
    id<SSBPlatformUIProtocol> restored = [SSBPlatformUI shared];
    XCTAssertNotNil(restored);
    XCTAssertTrue([restored isKindOfClass:[SSBPlatformUI class]]);
}

- (void)testFakeUI_capturesAlert {
    FakePlatformUI *fake = [[FakePlatformUI alloc] init];
    fake.stubbedResponse = NSAlertFirstButtonReturn;
    [SSBPlatformUI setShared:fake];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Test";
    NSModalResponse resp = [[SSBPlatformUI shared] runModalAlert:alert];

    XCTAssertEqual(fake.lastAlert, alert);
    XCTAssertEqual(resp, NSAlertFirstButtonReturn);
}

@end
