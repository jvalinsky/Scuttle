#import <XCTest/XCTest.h>

// Forward declaration or import generated header
// In XcodeGen, the module header name is typically <ModuleName>-Swift.h
// or we can load it dynamically if needed, but standard bridge works:
#import "VirtualizationTests-Swift.h"

/// Returns YES if the Linux kernel and initfs are available (either via env vars or default paths).
/// These files are required to boot a VM. Build them by running:
///   make -C ~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/containerization/kernel
/// then set LINUX_KERNEL=/path/to/vmlinux and LINUX_INITFS=/path/to/init.block
static BOOL SRLinuxVMPrerequisitesAvailable(void) {
    NSString *kernelPath = NSProcessInfo.processInfo.environment[@"LINUX_KERNEL"] ?: @"/usr/local/bin/vmlinux";
    NSString *initfsPath = NSProcessInfo.processInfo.environment[@"LINUX_INITFS"] ?: @"/usr/local/bin/init.block";
    NSFileManager *fm = NSFileManager.defaultManager;
    return [fm fileExistsAtPath:kernelPath] && [fm fileExistsAtPath:initfsPath];
}

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

/// Validates the Swift-ObjC bridge compiles and SRLinuxTestRunner can be instantiated.
/// This test does NOT require a kernel/initfs and always runs.
- (void)testSwiftBridgeInstantiation {
    XCTAssertNotNil(self.runner, @"SRLinuxTestRunner Swift-ObjC bridge should be instantiable");
    XCTAssert([self.runner isKindOfClass:[SRLinuxTestRunner class]]);
}

- (void)testLinuxNixCheck {
    if (!SRLinuxVMPrerequisitesAvailable()) {
        XCTSkip(@"Skipping: Linux kernel/initfs not available. "
                @"Set LINUX_KERNEL and LINUX_INITFS env vars or place files at "
                @"/usr/local/bin/vmlinux and /usr/local/bin/init.block. "
                @"Build the kernel: make -C <containerization-checkout>/kernel");
    }

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run Nix Check in Container"];

    [self.runner runCommand:@"nix flake check"
                      image:@"nixos/nix"
                 completion:^(BOOL success, NSString * _Nullable message) {
        XCTAssertTrue(success, @"Container execution failed: %@", message);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:300.0 handler:nil];
}

- (void)testLinuxBuild {
    if (!SRLinuxVMPrerequisitesAvailable()) {
        XCTSkip(@"Skipping: Linux kernel/initfs not available. "
                @"Set LINUX_KERNEL and LINUX_INITFS env vars or place files at "
                @"/usr/local/bin/vmlinux and /usr/local/bin/init.block.");
    }

    XCTestExpectation *expectation = [self expectationWithDescription:@"Run GNUstep build in Container"];

    [self.runner runCommand:@"make"
                      image:@"nixos/nix"
                 completion:^(BOOL success, NSString * _Nullable message) {
        XCTAssertTrue(success, @"Container build failed: %@", message);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:300.0 handler:nil];
}

@end
