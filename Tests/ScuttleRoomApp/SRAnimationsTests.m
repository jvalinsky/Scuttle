#import <XCTest/XCTest.h>
#import "SRAnimations.h"

@interface SRAnimationsTests : XCTestCase
@end

@implementation SRAnimationsTests

- (void)testFadeInDoesNotCrash {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [SRAnimations fadeInView:view duration:0.0];
}

- (void)testFadeOutCallsCompletion {
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    view.alphaValue = 1.0;
    [SRAnimations fadeOutView:view duration:0.0 completion:^{
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testCrossfadeDoesNotCrash {
    NSView *fromView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    NSView *toView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [SRAnimations crossfadeFromView:fromView toView:toView duration:0.0 completion:nil];
}

@end
