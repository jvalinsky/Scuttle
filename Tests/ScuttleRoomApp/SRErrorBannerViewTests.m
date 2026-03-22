#import <XCTest/XCTest.h>
#import "SRErrorBannerView.h"
#import "SRNotificationBannerView.h"

@interface SRErrorBannerViewTests : XCTestCase
@property (nonatomic, strong) SRErrorBannerView *banner;
@end

@implementation SRErrorBannerViewTests

- (void)setUp {
    [super setUp];
    self.banner = [[SRErrorBannerView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
}

- (void)testInit_viewIsHidden {
    XCTAssertTrue(self.banner.hidden);
}

- (void)testInit_hasMessageLabel {
    XCTAssertNotNil(self.banner.messageLabel);
}

- (void)testInit_hasCloseButton {
    XCTAssertNotNil(self.banner.closeButton);
}

- (void)testShowMessage_setsLabelText {
    [self.banner showMessage:@"Connection error"];
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"Connection error");
}

- (void)testShowMessage_unhidesView {
    [self.banner showMessage:@"Error occurred"];
    XCTAssertFalse(self.banner.hidden);
}

- (void)testShowMessage_emptyString_unhidesView {
    [self.banner showMessage:@""];
    XCTAssertFalse(self.banner.hidden);
}

- (void)testHide_hidesView {
    [self.banner showMessage:@"Visible"];
    [self.banner hide];
    XCTAssertTrue(self.banner.hidden);
}

- (void)testHide_thenShowMessage_unhidesAgain {
    [self.banner showMessage:@"First"];
    [self.banner hide];
    [self.banner showMessage:@"Second"];
    XCTAssertFalse(self.banner.hidden);
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"Second");
}

// ── showMessage:type: ────────────────────────────────────────────────────────

- (void)testShowMessageType_error_setsLabel {
    [self.banner showMessage:@"disk full" type:SRNotificationTypeError];
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"disk full");
    XCTAssertFalse(self.banner.hidden);
}

- (void)testShowMessageType_warning_setsLabel {
    [self.banner showMessage:@"low memory" type:SRNotificationTypeWarning];
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"low memory");
    XCTAssertFalse(self.banner.hidden);
}

- (void)testShowMessageType_success_setsLabel {
    [self.banner showMessage:@"saved!" type:SRNotificationTypeSuccess];
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"saved!");
    XCTAssertFalse(self.banner.hidden);
}

- (void)testShowMessageType_info_setsLabel {
    [self.banner showMessage:@"sync started" type:SRNotificationTypeInfo];
    XCTAssertEqualObjects(self.banner.messageLabel.stringValue, @"sync started");
    XCTAssertFalse(self.banner.hidden);
}

- (void)testShowMessageWithoutType_defaultsToErrorBehavior {
    // showMessage: without type should behave same as showMessage:type:SRNotificationTypeError
    [self.banner showMessage:@"oops"];
    NSString *v1 = self.banner.messageLabel.stringValue;
    [self.banner hide];
    [self.banner showMessage:@"oops" type:SRNotificationTypeError];
    NSString *v2 = self.banner.messageLabel.stringValue;
    XCTAssertEqualObjects(v1, v2);
}

@end
