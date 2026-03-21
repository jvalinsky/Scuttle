#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPCFramer.h"

@interface SSBMuxRPCFramerTests : XCTestCase
@end

@implementation SSBMuxRPCFramerTests

- (void)testCreateDefinitionReturnsNonnull {
    nw_protocol_definition_t def = [SSBMuxRPCFramer createDefinition];
    XCTAssertNotNil(def);
}

- (void)testCreateOptionsReturnsNonnull {
    nw_protocol_options_t options = [SSBMuxRPCFramer createOptions];
    XCTAssertNotNil(options);
}

@end
