#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBMuxRPC.h>
#import <SSBNetwork/SSBMuxRPCFramer.h>

@interface SSBFramerTests : XCTestCase
@end

@implementation SSBFramerTests

- (void)testFramerDefinitionCreation {
    nw_protocol_definition_t definition = [SSBMuxRPCFramer createDefinition];
    XCTAssertNotNil(definition);
}

- (void)testMuxHeaderParseRoundTripWithBody {
    NSData *body = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    SSBMuxRPCMessage *message = [[SSBMuxRPCMessage alloc] initWithFlags:(SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream)
                                                          requestNumber:42
                                                                   body:body];
    NSData *serialized = [message serialize];
    XCTAssertEqual(serialized.length, (NSUInteger)(9 + body.length));

    NSData *header = [serialized subdataWithRange:NSMakeRange(0, 9)];
    SSBMuxRPCFlags parsedFlags = 0;
    int32_t parsedRequest = 0;
    uint32_t parsedBodyLength = [SSBMuxRPCMessage parseHeader:header outFlags:&parsedFlags outRequestNumber:&parsedRequest];

    XCTAssertEqual(parsedBodyLength, (uint32_t)body.length);
    XCTAssertEqual(parsedFlags, (SSBMuxRPCFlagTypeJSON | SSBMuxRPCFlagStream));
    XCTAssertEqual(parsedRequest, 42);
}

- (void)testMuxHeaderParseRoundTripWithZeroLengthBody {
    SSBMuxRPCMessage *message = [[SSBMuxRPCMessage alloc] initWithFlags:SSBMuxRPCFlagEndErr
                                                          requestNumber:88
                                                                   body:[NSData data]];
    NSData *serialized = [message serialize];
    XCTAssertEqual(serialized.length, (NSUInteger)9);

    NSData *header = [serialized subdataWithRange:NSMakeRange(0, 9)];
    SSBMuxRPCFlags parsedFlags = 0;
    int32_t parsedRequest = 0;
    uint32_t parsedBodyLength = [SSBMuxRPCMessage parseHeader:header outFlags:&parsedFlags outRequestNumber:&parsedRequest];

    XCTAssertEqual(parsedBodyLength, (uint32_t)0);
    XCTAssertEqual(parsedFlags, SSBMuxRPCFlagEndErr);
    XCTAssertEqual(parsedRequest, 88);
}

@end
