#import <XCTest/XCTest.h>
#import "SSBStateMachine.h"

@interface SSBStateMachineTests : XCTestCase
@property (nonatomic, strong) SSBStateMachine *machine;
@end

@implementation SSBStateMachineTests

- (void)setUp {
    self.machine = [[SSBStateMachine alloc] initWithCategory:SSBLogCategorySync];
}

- (void)testInitialState {
    XCTAssertEqual(self.machine.syncState, SSBSyncStateIdle);
    XCTAssertEqual(self.machine.connectionState, SSBClientConnectionStateDisconnected);
}

- (void)testSyncStateTransitions {
    [self.machine transitionToSyncState:SSBSyncStateConnecting];
    XCTAssertEqual(self.machine.syncState, SSBSyncStateConnecting);
    
    [self.machine transitionToSyncState:SSBSyncStateSyncingLocal];
    XCTAssertEqual(self.machine.syncState, SSBSyncStateSyncingLocal);
    
    [self.machine transitionToSyncState:SSBSyncStateSynced];
    XCTAssertEqual(self.machine.syncState, SSBSyncStateSynced);
}

- (void)testConnectionStateTransitions {
    [self.machine transitionToConnectionState:SSBClientConnectionStateConnecting];
    XCTAssertEqual(self.machine.connectionState, SSBClientConnectionStateConnecting);
    
    [self.machine transitionToConnectionState:SSBClientConnectionStateHandshake];
    XCTAssertEqual(self.machine.connectionState, SSBClientConnectionStateHandshake);
    
    [self.machine transitionToConnectionState:SSBClientConnectionStateConnected];
    XCTAssertEqual(self.machine.connectionState, SSBClientConnectionStateConnected);
}

- (void)testCanPublish {
    XCTAssertFalse(self.machine.canPublish, "Cannot publish when disconnected");
    
    self.machine.connectionState = SSBClientConnectionStateConnected;
    self.machine.syncState = SSBSyncStateIdle;
    XCTAssertTrue(self.machine.canPublish, "Can publish when connected and idle");
    
    self.machine.syncState = SSBSyncStateSynced;
    XCTAssertTrue(self.machine.canPublish, "Can publish when connected and synced");
    
    self.machine.syncState = SSBSyncStateSyncingLocal;
    XCTAssertFalse(self.machine.canPublish, "Cannot publish while syncing local");
    
    self.machine.syncState = SSBSyncStateSyncingRemote;
    XCTAssertFalse(self.machine.canPublish, "Cannot publish while syncing remote");
}

- (void)testIsSyncing {
    XCTAssertFalse(self.machine.isSyncing, "Not syncing when idle");
    
    self.machine.syncState = SSBSyncStateConnecting;
    XCTAssertTrue(self.machine.isSyncing, "Is syncing when connecting");
    
    self.machine.syncState = SSBSyncStateSyncingLocal;
    XCTAssertTrue(self.machine.isSyncing, "Is syncing when syncing local");
    
    self.machine.syncState = SSBSyncStateSyncingRemote;
    XCTAssertTrue(self.machine.isSyncing, "Is syncing when syncing remote");
    
    self.machine.syncState = SSBSyncStateSynced;
    XCTAssertFalse(self.machine.isSyncing, "Not syncing when synced");
}

- (void)testDiagnosticSummary {
    NSString *summary = [self.machine diagnosticSummary];
    XCTAssertNotNil(summary);
    XCTAssert([summary containsString:@"Disconnected"]);
    XCTAssert([summary containsString:@"Idle"]);
}

- (void)testStateToString {
    XCTAssertEqualObjects([self.machine syncStateToString:SSBSyncStateIdle], @"Idle");
    XCTAssertEqualObjects([self.machine syncStateToString:SSBSyncStateSyncingLocal], @"SyncingLocal");
    XCTAssertEqualObjects([self.machine connectionStateToString:SSBClientConnectionStateConnected], @"Connected");
}

@end
