#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPC.h"

@interface SSBMuxRPCTests : XCTestCase
@end

@implementation SSBMuxRPCTests

- (void)testMessageCreationProperties {
    NSData *body = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeString | SSBMuxRPCFlagStream
                                                      requestNumber:123
                                                               body:body];
    XCTAssertEqual(msg.flags, SSBMuxRPCFlagTypeString | SSBMuxRPCFlagStream);
    XCTAssertEqual(msg.requestNumber, 123);
    XCTAssertEqualObjects(msg.body, body);
}

- (void)testSerializeExactByteLayout {
    NSData *body = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    // Flags: JSON(2) | Stream(8) = 10 (0x0A)
    // Body len: 5 (0x00 0x00 0x00 0x05)
    // Req num: 42 (0x00 0x00 0x00 0x2A)
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream
                                                      requestNumber:42
                                                               body:body];
    NSData *serialized = [msg serialize];
    XCTAssertEqual(serialized.length, 9 + 5);
    
    const uint8_t *bytes = serialized.bytes;
    XCTAssertEqual(bytes[0], 0x0A);
    // Body length big-endian
    XCTAssertEqual(bytes[1], 0x00);
    XCTAssertEqual(bytes[2], 0x00);
    XCTAssertEqual(bytes[3], 0x00);
    XCTAssertEqual(bytes[4], 0x05);
    // Request number big-endian
    XCTAssertEqual(bytes[5], 0x00);
    XCTAssertEqual(bytes[6], 0x00);
    XCTAssertEqual(bytes[7], 0x00);
    XCTAssertEqual(bytes[8], 0x2A);
    
    // Body bytes
    NSData *outBody = [serialized subdataWithRange:NSMakeRange(9, 5)];
    XCTAssertEqualObjects(outBody, body);
}

- (void)testSerializeNegativeRequestNumber {
    // Req num: -1 (0xFF FF FF FF)
    SSBMuxRPCMessage *msg = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagTypeJSON
                                                      requestNumber:-1
                                                               body:[NSData data]];
    NSData *serialized = [msg serialize];
    const uint8_t *bytes = serialized.bytes;
    
    XCTAssertEqual(bytes[5], 0xFF);
    XCTAssertEqual(bytes[6], 0xFF);
    XCTAssertEqual(bytes[7], 0xFF);
    XCTAssertEqual(bytes[8], 0xFF);
}

- (void)testParseHeaderExactLengths {
    uint8_t headerBytes[9] = {
        0x01, // String
        0x00, 0x00, 0x00, 0x00, // length 0
        0x00, 0x00, 0x00, 0x01  // req 1
    };
    NSData *headerData = [NSData dataWithBytes:headerBytes length:9];
    
    SSBMuxRPCFlags parsedFlags = 0;
    int32_t parsedReq = 0;
    uint32_t parsedLen = [SSBMuxRPCMessage parseHeader:headerData outFlags:&parsedFlags outRequestNumber:&parsedReq];
    
    XCTAssertEqual(parsedLen, 0);
    XCTAssertEqual(parsedFlags, SSBMuxRPCFlagTypeString);
    XCTAssertEqual(parsedReq, 1);
}

- (void)testParseHeaderWithExtraTrailingBytes {
    uint8_t headerBytes[12] = {
        0x0A, // JSON | Stream = 10
        0x00, 0x00, 0x00, 0x0A, // length 10
        0xFF, 0xFF, 0xFF, 0xFD, // req -3
        // Extra trailing bytes that shouldn't matter for parseHeader
        0xAA, 0xBB, 0xCC
    };
    NSData *headerData = [NSData dataWithBytes:headerBytes length:12];
    
    SSBMuxRPCFlags parsedFlags = 0;
    int32_t parsedReq = 0;
    uint32_t parsedLen = [SSBMuxRPCMessage parseHeader:headerData outFlags:&parsedFlags outRequestNumber:&parsedReq];
    
    XCTAssertEqual(parsedLen, 10);
    XCTAssertEqual(parsedFlags, SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream);
    XCTAssertEqual(parsedReq, -3);
}

- (void)testParseTruncatedHeaderIgnoresAndReturnsZero {
    uint8_t headerBytes[8] = { 0 };
    NSData *headerData = [NSData dataWithBytes:headerBytes length:8];
    
    SSBMuxRPCFlags parsedFlags = 0xFF; // prepopulate with garbage to verify it doesn't get touched
    int32_t parsedReq = 99;
    uint32_t parsedLen = [SSBMuxRPCMessage parseHeader:headerData outFlags:&parsedFlags outRequestNumber:&parsedReq];
    
    XCTAssertEqual(parsedLen, 0);
    XCTAssertEqual(parsedFlags, 0xFF); // Unmodified
    XCTAssertEqual(parsedReq, 99);     // Unmodified
}

- (void)testParseHeaderWithNilOutputPointers {
    uint8_t headerBytes[9] = {
        0x01,
        0x00, 0x00, 0x00, 0x20, // length 32
        0x00, 0x00, 0x00, 0x01
    };
    NSData *headerData = [NSData dataWithBytes:headerBytes length:9];
    
    // Should not crash
    uint32_t parsedLen = [SSBMuxRPCMessage parseHeader:headerData outFlags:nil outRequestNumber:nil];
    XCTAssertEqual(parsedLen, 32);
}

- (void)testIndependentFlagBitManipulation {
    // Test that all flag combinations parse cleanly
    for (uint8_t i = 0; i < 16; i++) {
        uint8_t headerBytes[9] = { i, 0,0,0,0, 0,0,0,0 };
        NSData *headerData = [NSData dataWithBytes:headerBytes length:9];
        SSBMuxRPCFlags parsedFlags = 0;
        [SSBMuxRPCMessage parseHeader:headerData outFlags:&parsedFlags outRequestNumber:nil];
        XCTAssertEqual(parsedFlags, i);
    }
}

@end
