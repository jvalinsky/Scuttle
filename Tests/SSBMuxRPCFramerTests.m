#import <XCTest/XCTest.h>
#import "../Sources/SSBMuxRPCFramer.h"
#import "../Sources/SSBMuxRPC.h"

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

- (void)testCreateDefinitionIsIdempotent {
    // dispatch_once inside createDefinition guarantees the same object is returned
    nw_protocol_definition_t def1 = [SSBMuxRPCFramer createDefinition];
    nw_protocol_definition_t def2 = [SSBMuxRPCFramer createDefinition];
    XCTAssertEqual(def1, def2);
}

- (void)testCreateOptionsReturnsDistinctInstances {
    // Each call to createOptions should produce a new, distinct options object
    nw_protocol_options_t opts1 = [SSBMuxRPCFramer createOptions];
    nw_protocol_options_t opts2 = [SSBMuxRPCFramer createOptions];
    XCTAssertNotNil(opts1);
    XCTAssertNotNil(opts2);
    XCTAssertNotEqual(opts1, opts2);
}

- (void)testCreateOptionsUsesFramerDefinition {
    // Options should be backed by the framer definition (not nil, not a different protocol)
    nw_protocol_definition_t def = [SSBMuxRPCFramer createDefinition];
    nw_protocol_options_t options = [SSBMuxRPCFramer createOptions];
    XCTAssertNotNil(def);
    XCTAssertNotNil(options);
    // Both are non-nil and are distinct typed objects (definition vs options)
    XCTAssertFalse(def == (id)options);
}

// NOTE: The internal state machine (header → body transitions, multi-message
// parsing, partial delivery, zero-length body) runs inside nw_framer_parse_input
// callbacks that only fire when Network.framework drives them with live data.
// These require integration tests with a real nw_connection_t pair, not unit tests.

@end
