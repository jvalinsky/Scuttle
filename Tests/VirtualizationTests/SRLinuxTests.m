#import <XCTest/XCTest.h>

// Forward declaration or import generated header
// In XcodeGen, the module header name is typically <ModuleName>-Swift.h
// or we can load it dynamically if needed, but standard bridge works:
#import "VirtualizationTests-Swift.h" 

@interface SRLinuxTests : XCTestCase
@property (nonatomic, strong) SRLinuxTestRunner *runner;
@end

@implementation SRLinuxTests

- (void)setUp {
    [super setUp];
    self.runner = [[SRLinuxTestRunner alloc] init];
}

- (void)tearDown {
    self.runner = nil;
    [super tearDown];
}

- (void)testLinuxNixCheck {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Run Nix Check in Container"];
    
    // We can run `nix flake check` directly inside the container
    [self.runner runCommand:@"nix flake check"
                      image:@"nixos/nix"
                 completion:^(BOOL success, NSString * _Nullable message) {
        XCTAssertTrue(success, @"Container execution failed: %@", message);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:60.0 handler:nil];
}

- (void)testLinuxBuild {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Run Mix Build in Container"];
    
    [self.runner runCommand:@"make"
                      image:@"nixos/nix" // or explicit GNUstep image
                 completion:^(BOOL success, NSString * _Nullable message) {
        XCTAssertTrue(success, @"Container build failed: %@", message);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:120.0 handler:nil];
}

@end
