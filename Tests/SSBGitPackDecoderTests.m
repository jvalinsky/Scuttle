#import <XCTest/XCTest.h>
#import "SSBGitPackDecoder.h"

@interface SSBGitPackDecoderTests : XCTestCase
@end

@implementation SSBGitPackDecoderTests

- (void)testInitializationWithInvalidData {
    NSData *shortData = [@"PACK" dataUsingEncoding:NSUTF8StringEncoding];
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:shortData];
    XCTAssertNil(decoder, @"Should fail to initialize with short data");
}

- (void)testInitializationWithInvalidMagic {
    NSMutableData *badMagic = [NSMutableData dataWithLength:32];
    uint32_t *bytes = (uint32_t *)badMagic.mutableBytes;
    bytes[0] = NSSwapHostIntToBig(0x12345678);
    bytes[1] = NSSwapHostIntToBig(2);
    
    SSBGitPackDecoder *decoder = [[SSBGitPackDecoder alloc] initWithData:badMagic];
    XCTAssertNil(decoder, @"Should fail to initialize with bad magic");
}

@end
