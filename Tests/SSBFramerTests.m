#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBFramer.h>

@interface SSBFramerTests : XCTestCase
@end

@implementation SSBFramerTests

- (void)testFramerDefinitionCreation {
    // Just verify it doesn't crash and returns a valid definition pointer
    nw_protocol_definition_t definition = [SSBFramer createFramerDefinition];
    XCTAssertNotNil(definition);
}

@end
