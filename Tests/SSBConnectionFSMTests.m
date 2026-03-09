#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBConnectionFSM.h>

@interface SSBConnectionFSMTests : XCTestCase <SSBConnectionFSMDelegate>
@property (nonatomic, strong) SSBConnectionFSM *fsm;
@property (nonatomic, assign) BOOL didRequestParse;
@property (nonatomic, assign) BOOL didTransitionToBoxStream;
@property (nonatomic, assign) BOOL didEncounterError;
@end

@implementation SSBConnectionFSMTests

- (void)setUp {
    self.fsm = [[SSBConnectionFSM alloc] init];
    self.fsm.delegate = self;
    self.didRequestParse = NO;
    self.didTransitionToBoxStream = NO;
    self.didEncounterError = NO;
}

- (void)testInitialState {
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateInit);
}

- (void)testStateProgression {
    [self.fsm advanceState];
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateSHSHelloSent);
    XCTAssertTrue(self.didRequestParse);
    
    self.didRequestParse = NO;
    [self.fsm advanceState];
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateSHSHelloReceived);
    XCTAssertTrue(self.didRequestParse);
    
    // Fast forward to Box Stream
    [self.fsm advanceState]; // Auth sent
    [self.fsm advanceState]; // Auth Recv
    [self.fsm advanceState]; // Accept Sent
    [self.fsm advanceState]; // Accept Recv
    [self.fsm advanceState]; // Box Stream
    
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateBoxStream);
    XCTAssertTrue(self.didTransitionToBoxStream);
}

- (void)testErrorState {
    NSError *testError = [NSError errorWithDomain:@"Test" code:1 userInfo:nil];
    [self.fsm transitionToError:testError];
    
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateError);
    XCTAssertTrue(self.didEncounterError);
    
    // Ensure we can't advance from error
    [self.fsm advanceState];
    XCTAssertEqual(self.fsm.currentState, SSBConnectionStateError);
}

// MARK: - Delegate

- (void)connectionFSMDidRequestParse:(id)fSM {
    self.didRequestParse = YES;
}

- (void)connectionFSMDidTransitionToBoxStream:(id)fSM {
    self.didTransitionToBoxStream = YES;
}

- (void)connectionFSM:(id)fSM didEncounterError:(NSError *)error {
    self.didEncounterError = YES;
}

@end
