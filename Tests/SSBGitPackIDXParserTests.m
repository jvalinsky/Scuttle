#import <XCTest/XCTest.h>
#import "SSBGitPackIDXParser.h"

@interface SSBGitPackIDXParserTests : XCTestCase
@end

@implementation SSBGitPackIDXParserTests

- (void)testInitializationWithInvalidData {
    NSData *shortData = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:shortData];
    XCTAssertNil(parser, @"Should fail to initialize with short data");
}

- (void)testInitializationWithInvalidMagic {
    NSMutableData *badMagic = [NSMutableData dataWithLength:1032 + 40];
    uint32_t *bytes = (uint32_t *)badMagic.mutableBytes;
    bytes[0] = NSSwapHostIntToBig(0x12345678);
    bytes[1] = NSSwapHostIntToBig(2);
    
    SSBGitPackIDXParser *parser = [[SSBGitPackIDXParser alloc] initWithData:badMagic];
    XCTAssertNil(parser, @"Should fail to initialize with bad magic");
}

@end
