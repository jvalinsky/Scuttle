#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBFeedStore.h>
#import "SSBLogger.h"

@interface SSBFeedStoreTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *store;
@end

@implementation SSBFeedStoreTests

- (void)setUp {
    self.store = [SSBFeedStore sharedStore];
}

- (void)tearDown {
    
}

#pragma mark - Following Tests

- (void)testIsFollowingDefault {
    NSString *testAuthor = @"testAuthor123";
    
    BOOL isFollowing = [self.store isFollowing:testAuthor];
    XCTAssertFalse(isFollowing, "New author should not be following");
}

- (void)testSetAndIsFollowing {
    NSString *testAuthor = @"testAuthorFollow";
    
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:1];
    
    XCTAssertTrue([self.store isFollowing:testAuthor], "Author should be marked as following");
    
    [self.store setFollowing:NO forAuthor:testAuthor atSequence:2];
    
    XCTAssertFalse([self.store isFollowing:testAuthor], "Author should not be marked as following");
}

- (void)testFollowingSequenceUpdate {
    NSString *testAuthor = @"testAuthorSeq";
    
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:5];
    
    SSBFeedState *state = [self.store feedStateForAuthor:testAuthor];
    XCTAssertNotNil(state, "Feed state should exist after setting following");
}

#pragma mark - Blocking Tests

- (void)testIsBlockedDefault {
    NSString *testAuthor = @"testAuthorBlocked";
    
    BOOL isBlocked = [self.store isBlocked:testAuthor];
    XCTAssertFalse(isBlocked, "New author should not be blocked");
}

- (void)testSetAndIsBlocked {
    NSString *testAuthor = @"testAuthorBlock";
    
    [self.store setBlocked:YES forAuthor:testAuthor atSequence:1];
    
    XCTAssertTrue([self.store isBlocked:testAuthor], "Author should be marked as blocked");
    
    [self.store setBlocked:NO forAuthor:testAuthor atSequence:2];
    
    XCTAssertFalse([self.store isBlocked:testAuthor], "Author should not be blocked");
}

- (void)testBlockAndFollowIndependence {
    NSString *testAuthor = @"testAuthorBoth";
    
    [self.store setBlocked:YES forAuthor:testAuthor atSequence:1];
    [self.store setFollowing:YES forAuthor:testAuthor atSequence:2];
    
    XCTAssertTrue([self.store isBlocked:testAuthor], "Author should be blocked");
    XCTAssertTrue([self.store isFollowing:testAuthor], "Author should also be following (can follow someone before blocking)");
}

#pragma mark - Display Name Tests

- (void)testSetDisplayName {
    NSString *testAuthor = @"testAuthorName";
    NSString *testName = @"Test Display Name";
    
    [self.store setDisplayName:testName image:nil forAuthor:testAuthor];
    
    SSBFeedState *state = [self.store feedStateForAuthor:testAuthor];
    XCTAssertNotNil(state, "Feed state should exist");
}

#pragma mark - Feed State Tests

- (void)testFeedStateForUnknownAuthor {
    NSString *unknownAuthor = @"unknownAuthor123456";
    
    SSBFeedState *state = [self.store feedStateForAuthor:unknownAuthor];
    
    XCTAssertNil(state, "Unknown author should have no feed state");
}

- (void)testLocalClock {
    NSDictionary *clock = [self.store localClock];
    
    XCTAssertNotNil(clock, "Local clock should not be nil");
    XCTAssert([clock isKindOfClass:[NSDictionary class]], "Local clock should be a dictionary");
}

@end
