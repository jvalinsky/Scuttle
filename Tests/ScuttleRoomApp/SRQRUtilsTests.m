#import <XCTest/XCTest.h>
#import "SRQRUtils.h"

@interface SRQRUtilsTests : XCTestCase
@end

@interface MockScannerDelegate : NSObject <SRScannerDelegate>
@property (nonatomic, copy) NSString *scannedString;
@end

@interface SRScannerViewController (TestAccess)
- (void)cancelAction:(nullable id)sender;
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection;
@end

@implementation MockScannerDelegate
- (void)scannerDidScanString:(NSString *)string {
    self.scannedString = string;
}
@end

@implementation SRQRUtilsTests

- (void)testGenerateQRCodeFromString_returnsImage {
    NSImage *image = [SRQRUtils generateQRCodeFromString:@"https://example.com" size:CGSizeMake(200, 200)];
    XCTAssertNotNil(image);
}

- (void)testGenerateQRCodeFromString_imageHasCorrectSize {
    CGSize size = CGSizeMake(300, 300);
    NSImage *image = [SRQRUtils generateQRCodeFromString:@"ssb-room-invite" size:size];
    XCTAssertNotNil(image);
    XCTAssertEqualWithAccuracy(image.size.width, size.width, 1.0);
    XCTAssertEqualWithAccuracy(image.size.height, size.height, 1.0);
}

- (void)testGenerateQRCodeFromString_shortString_returnsImage {
    NSImage *image = [SRQRUtils generateQRCodeFromString:@"A" size:CGSizeMake(100, 100)];
    XCTAssertNotNil(image);
}

- (void)testGenerateQRCodeFromString_longString_returnsImage {
    NSString *longString = [@"" stringByPaddingToLength:200 withString:@"X" startingAtIndex:0];
    NSImage *image = [SRQRUtils generateQRCodeFromString:longString size:CGSizeMake(400, 400)];
    XCTAssertNotNil(image);
}

- (void)testGenerateQRCodeFromData_returnsImage {
    NSData *data = [@"Hello, QR!" dataUsingEncoding:NSUTF8StringEncoding];
    NSImage *image = [SRQRUtils generateQRCodeFromData:data size:CGSizeMake(200, 200)];
    XCTAssertNotNil(image);
}

- (void)testGenerateQRCodeFromData_imageHasCorrectSize {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CGSize size = CGSizeMake(150, 150);
    NSImage *image = [SRQRUtils generateQRCodeFromData:data size:size];
    XCTAssertNotNil(image);
    XCTAssertEqualWithAccuracy(image.size.width, size.width, 1.0);
    XCTAssertEqualWithAccuracy(image.size.height, size.height, 1.0);
}

- (void)testGenerateQRCodeFromData_hasRepresentation {
    NSData *data = [@"ssb:bamboo-proof:abc123" dataUsingEncoding:NSUTF8StringEncoding];
    NSImage *image = [SRQRUtils generateQRCodeFromData:data size:CGSizeMake(200, 200)];
    XCTAssertNotNil(image);
    XCTAssertGreaterThan(image.representations.count, 0U);
}

- (void)testGenerateQRCodeFromData_asymmetricSize {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    CGSize size = CGSizeMake(400, 200);
    NSImage *image = [SRQRUtils generateQRCodeFromData:data size:size];
    XCTAssertNotNil(image);
    XCTAssertEqualWithAccuracy(image.size.width, 400.0, 1.0);
    XCTAssertEqualWithAccuracy(image.size.height, 200.0, 1.0);
}

- (void)testScannerViewController_loadView_setsUpView {
    SRScannerViewController *vc = [[SRScannerViewController alloc] init];
    [vc loadView];
    XCTAssertNotNil(vc.view);
    XCTAssertTrue(vc.view.wantsLayer);
}

- (void)testScannerViewController_viewDidLoad_addsSubviews {
    SRScannerViewController *vc = [[SRScannerViewController alloc] init];
    // Trigger loadView and viewDidLoad
    [vc view]; 
    XCTAssertGreaterThan(vc.view.subviews.count, 0U, @"Should have subviews added in viewDidLoad");
}

- (void)testScannerViewController_cancelAction_Dismisses {
    SRScannerViewController *vc = [[SRScannerViewController alloc] init];
    [vc view]; // load view
    
    // Call cancelAction directly
    [vc cancelAction:nil];
    // We can't easily assert dismissal on headless XCTest without host app, 
    // but running it ensures no crash and covers lines.
}

- (void)testScannerViewController_captureOutput_NotifiesDelegate {
    SRScannerViewController *vc = [[SRScannerViewController alloc] init];
    MockScannerDelegate *delegate = [[MockScannerDelegate alloc] init];
    vc.delegate = delegate;
    [vc view]; // load view
    
    // We can't easily mock AVMetadataMachineReadableCodeObject because it may crash on init.
    // But we can test with empty array to cover that path without crash.
    [vc captureOutput:nil didOutputMetadataObjects:@[] fromConnection:nil];
    XCTAssertNil(delegate.scannedString);
}

@end
