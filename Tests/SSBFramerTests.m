#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBMuxRPCFramer.h>

@interface SSBFramerTests : XCTestCase
@end

@implementation SSBFramerTests

- (void)testFramerDefinitionCreation {
    // Just verify it doesn't crash and returns a valid definition pointer
    nw_protocol_definition_t definition = [SSBMuxRPCFramer createDefinition];
    XCTAssertNotNil(definition);
}

@end
