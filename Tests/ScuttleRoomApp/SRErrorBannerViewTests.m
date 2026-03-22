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

#import "TEA/SRModel.h"
#import "TEA/SRMsg.h"
#import "TEA/SRUpdate.h"
#import "RoomInviteHandler.h"

@interface SRStateTransitionTests : XCTestCase
@end

@implementation SRStateTransitionTests

- (void)testInitialModel {
    SRModel *model = [SRModel initialModel];
    XCTAssertEqual(model.workspaceContext, SRWorkspaceContextFeeds);
    XCTAssertNil(model.selectedRoom);
}

- (void)testSetWorkspaceContext {
    SRModel *model = [SRModel initialModel];
    SRMsg *msg = [SRMsg setWorkspaceContext:SRWorkspaceContextGit];
    
    SRUpdateResult *result = [SRUpdate updateWithModel:model msg:msg];
    
    XCTAssertEqual(result.model.workspaceContext, SRWorkspaceContextGit);
    XCTAssertNil(result.model.selectedRoom);
}

- (void)testSelectRoom {
    SRModel *model = [SRModel initialModel];
    
    unsigned char dummyBytes[] = {0x01, 0x02, 0x03};
    NSData *pubKeyData = [NSData dataWithBytes:dummyBytes length:sizeof(dummyBytes)];
    RoomConfig *room = [[RoomConfig alloc] initWithHost:@"test.room" port:8008 pubKey:pubKeyData];
    
    SRMsg *msg = [SRMsg selectRoom:room];
    SRUpdateResult *result = [SRUpdate updateWithModel:model msg:msg];
    
    XCTAssertEqual(result.model.workspaceContext, SRWorkspaceContextFeeds); 
    XCTAssertEqual(result.model.selectedRoom, room);
}

@end
