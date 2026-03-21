#import <XCTest/XCTest.h>
#import "SRQRUtils.h"

@interface SRQRUtilsTests : XCTestCase
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

@end
