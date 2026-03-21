#import <XCTest/XCTest.h>
#import "SRErrorBannerView.h"

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

@end
