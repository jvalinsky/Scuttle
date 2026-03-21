#import <XCTest/XCTest.h>
#import "../Sources/SSBURLSessionCompat.h"

@interface SSBURLSessionShimTests : XCTestCase
@end

@implementation SSBURLSessionShimTests

#ifndef __APPLE__

// These tests validate the SSBURLSessionShim which is only compiled on non-Apple
// platforms (e.g., Linux/GNUstep where Foundation lacks NSURLSession).

- (void)testSharedSessionExists {
    NSURLSession *session = [NSURLSession sharedSession];
    XCTAssertNotNil(session);
    XCTAssertEqual(session, [NSURLSession sharedSession]);
}

- (void)testDataTaskCreationAndResume {
    NSURLSession *session = [NSURLSession sharedSession];
    XCTestExpectation *expect = [self expectationWithDescription:@"Shim completion"];
    
    NSURL *url = [NSURL URLWithString:@"http://localhost"];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, @"SSBURLSessionShim");
        [expect fulfill];
    }];
    
    XCTAssertNotNil(task);
    [task resume];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testDataTaskCancelDoesNotCrash {
    NSURLSession *session = [NSURLSession sharedSession];
    NSURL *url = [NSURL URLWithString:@"http://localhost"];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {}];
    
    // Just verify it responds and doesn't crash, as per the shim stub
    [task cancel];
    XCTAssert(YES);
}

#else

- (void)testShimIsOmittedOnApplePlatforms {
    // On macOS/iOS, Foundation provides NSURLSession natively. 
    // Testing the shim here would conflict with the OS implementation.
    XCTAssert(YES, @"Shim safely bypassed on Apple platforms.");
}

#endif

@end
