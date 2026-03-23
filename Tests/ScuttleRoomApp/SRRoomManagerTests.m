#import <XCTest/XCTest.h>
#import "SRRoomManager.h"

#import "../../App/Logic/SRRoomManager.h"
#import "../../App/Logic/SRNotificationNames.h"
#import "../../App/UI/SRSidebarViewController.h"
#import "../../App/UI/SRContentContainerViewController.h"
#import "../../App/UI/SRHomeViewController.h"
#import "../../App/UI/SRChannelBrowserViewController.h"
#import "../../App/UI/SRPeerListViewController.h"
#import "../../App/UI/SRFeedViewController.h"
#import "../../App/UI/SRComposeViewController.h"
#import "../../App/UI/SRProfileViewController.h"
#import "../../App/UI/SRProfileHeaderView.h"

@interface SRRoomManager (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBRoomClient *> *internalClients;
@end

@interface SRRoomMockClient : SSBRoomClient
@property (nonatomic, copy) NSString *mockHost;
@property (nonatomic, assign) BOOL connectCalled;
@property (nonatomic, assign) BOOL disconnectCalled;
@end

@implementation SRRoomMockClient
- (NSString *)host { return self.mockHost; }
- (void)connect { self.connectCalled = YES; }
- (void)disconnect { self.disconnectCalled = YES; }
- (void)replicateFromPeer:(NSString *)peerID viaRoom:(NSString *)host {}
@end

@interface SRRoomManagerTests : XCTestCase
@property (nonatomic, strong) SRRoomManager *manager;
@end

@implementation SRRoomManagerTests

- (void)setUp {
    [super setUp];
    // Use the shared manager — in the test environment, no rooms are saved so init is benign.
    self.manager = [SRRoomManager sharedManager];
}

#pragma mark - Notification constant names

- (void)testDidUpdateRoomsNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerDidUpdateRoomsNotification.length, 0U);
}

- (void)testDidUpdateEndpointsNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerDidUpdateEndpointsNotification.length, 0U);
}

- (void)testConnectionStatusChangedNotification_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerConnectionStatusChangedNotification.length, 0U);
}

- (void)testEndpointsHostKey_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerEndpointsHostKey.length, 0U);
}

- (void)testEndpointsListKey_isNonEmpty {
    XCTAssertGreaterThan(SRRoomManagerEndpointsListKey.length, 0U);
}

#pragma mark - Singleton

- (void)testSharedManager_returnsSameInstance {
    SRRoomManager *m2 = [SRRoomManager sharedManager];
    XCTAssertEqual(self.manager, m2);
}

#pragma mark - rooms / clients initial state

- (void)testRooms_isArray {
    XCTAssertNotNil(self.manager.rooms);
}

- (void)testClients_isDictionary {
    XCTAssertNotNil(self.manager.clients);
}

- (void)testRoomEndpoints_isDictionary {
    XCTAssertNotNil(self.manager.roomEndpoints);
}

#pragma mark - peerSyncStatesForHost:

- (void)testPeerSyncStatesForHost_unknownHost_returnsEmptyDict {
    NSDictionary *states = [self.manager peerSyncStatesForHost:@"nonexistent.example.com"];
    XCTAssertNotNil(states);
    XCTAssertEqual(states.count, 0U);
}

#pragma mark - peerSyncProgressForHost:

- (void)testPeerSyncProgressForHost_unknownHost_returnsEmptyDict {
    NSDictionary *progress = [self.manager peerSyncProgressForHost:@"nonexistent.example.com"];
    XCTAssertNotNil(progress);
    XCTAssertEqual(progress.count, 0U);
}

#pragma mark - syncStatusForHost:

- (void)testSyncStatusForHost_unknownHost_returnsNil {
    NSString *status = [self.manager syncStatusForHost:@"nonexistent.example.com"];
    XCTAssertNil(status);
}

#pragma mark - syncProgressForHost:

- (void)testSyncProgressForHost_unknownHost_returnsOne {
    float progress = [self.manager syncProgressForHost:@"nonexistent.example.com"];
    XCTAssertEqualWithAccuracy(progress, 1.0f, 0.001f);
}

#pragma mark - clientForHost:

- (void)testClientForHost_unknownHost_returnsNil {
    SSBRoomClient *client = [self.manager clientForHost:@"nonexistent.example.com"];
    XCTAssertNil(client);
}

#pragma mark - anyConnectedClient

- (void)testAnyConnectedClient_doesNotCrash {
    // Just verify the method runs without crashing. In a test environment the result
    // depends on saved rooms in the Keychain, so we only assert a non-crash here.
    XCTAssertNoThrow([self.manager anyConnectedClient]);
}

#pragma mark - displayNameForAuthor:

- (void)testDisplayNameForAuthor_emptyString_returnsEmpty {
    NSString *name = [self.manager displayNameForAuthor:@""];
    XCTAssertEqualObjects(name, @"");
}

- (void)testDisplayNameForAuthor_unknownAuthor_returnsAuthorOrEmpty {
    NSString *author = @"@notinstore.ed25519";
    NSString *name = [self.manager displayNameForAuthor:author];
    XCTAssertNotNil(name);
    // Either the store has a cached name, or it returns the author ID as fallback
    XCTAssertGreaterThan(name.length, 0U);
}

#pragma mark - joinRoomWithInvite - invalid invite

- (void)testJoinRoomWithInvite_invalidCode_callsCompletionWithError {
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [self.manager joinRoomWithInvite:@"not-a-valid-invite" completion:^(BOOL success, NSError *error) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    [self.manager joinRoomWithInvite:@"not-a-valid-invite" completion:^(BOOL success, NSError *error) {
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#pragma mark - Delegate Callbacks

- (void)testRoomClientDidConnect_postsNotification {
    XCTestExpectation *expectation = [self expectationForNotification:SRRoomManagerConnectionStatusChangedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqualObjects(notification.userInfo[@"host"], @"test-host");
        XCTAssertEqualObjects(notification.userInfo[@"connected"], @YES);
        return YES;
    }];
    
    SRRoomMockClient *client = [[SRRoomMockClient alloc] init];
    client.mockHost = @"test-host";
    
    // Explicitly call delegate method
    [(id<SSBRoomClientDelegate>)self.manager roomClientDidConnect:client];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testRoomClientDidUpdateEndpoints_cachesAndPostsNotification {
    XCTestExpectation *expectation = [self expectationForNotification:SRRoomManagerDidUpdateEndpointsNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        XCTAssertEqualObjects(notification.userInfo[SRRoomManagerEndpointsHostKey], @"test-host");
        return YES;
    }];
    
    SRRoomMockClient *client = [[SRRoomMockClient alloc] init];
    client.mockHost = @"test-host";
    
    NSArray *endpoints = @[@"peer1", @"peer2"];
    [(id<SSBRoomClientDelegate>)self.manager roomClient:client didUpdateEndpoints:endpoints];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // Verify cached in roomEndpoints
    XCTAssertEqualObjects(self.manager.roomEndpoints[@"test-host"], endpoints);
}

- (void)testRoomClientDidEncounterError_postsNotification {
    XCTestExpectation *expectation = [self expectationForNotification:SRRoomManagerConnectionStatusChangedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        if (![notification.userInfo[@"host"] isEqualToString:@"test-host"]) return NO;
        XCTAssertEqualObjects(notification.userInfo[@"connected"], @NO);
        XCTAssertNotNil(notification.userInfo[@"error"]);
        return YES;
    }];
    
    SRRoomMockClient *client = [[SRRoomMockClient alloc] init];
    client.mockHost = @"test-host";
    
    NSError *error = [NSError errorWithDomain:@"Test" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Test error"}];
    [(id<SSBRoomClientDelegate>)self.manager roomClient:client didEncounterError:error];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testRoomClientDidUpdateSyncStatus_cachesAndPostsNotification {
    XCTestExpectation *expectation = [self expectationForNotification:SRRoomSyncStatusChangedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        if (![notification.userInfo[SRRoomSyncStatusHostKey] isEqualToString:@"test-host"]) return NO;
        XCTAssertEqualObjects(notification.userInfo[SRRoomSyncStatusHostKey], @"test-host");
        XCTAssertEqualObjects(notification.userInfo[SRRoomSyncStatusKey], @"Syncing");
        return YES;
    }];
    
    SRRoomMockClient *client = [[SRRoomMockClient alloc] init];
    client.mockHost = @"test-host";
    
    // Explicitly call delegate method
    [(id<SSBRoomClientDelegate>)self.manager roomClient:client didUpdateSyncStatus:@"Syncing" progress:0.5f author:@"@test-author" peerID:nil];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // Verify cached state
    XCTAssertEqualWithAccuracy([self.manager syncProgressForHost:@"test-host"], 0.5f, 0.01f);
    XCTAssertEqualObjects([self.manager syncStatusForHost:@"test-host"], @"Syncing");
}

@end

#pragma mark - SRSidebarViewControllerTests

@interface SRRoomManager (TestAccessRooms)
@property (nonatomic, strong) NSMutableArray<RoomConfig *> *internalRooms;
@end

@interface SRSidebarViewController (TestAccess)
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSArray *gitRepos;
@end

@interface SRSidebarViewControllerTests : XCTestCase
@property (nonatomic, strong) SRSidebarViewController *vc;
@property (nonatomic, strong) NSMutableArray *savedRooms;
@end

@implementation SRSidebarViewControllerTests

- (void)setUp {
    [super setUp];
    self.vc = [[SRSidebarViewController alloc] init];
    
    // Backup singleton state
    SRRoomManager *manager = [SRRoomManager sharedManager];
    self.savedRooms = [manager.internalRooms mutableCopy];
}

- (void)tearDown {
    // Restore singleton state
    SRRoomManager *manager = [SRRoomManager sharedManager];
    manager.internalRooms = self.savedRooms;
    
    self.vc = nil;
    [super tearDown];
}

- (void)testLoadView_setsUpVisualEffectView {
    [self.vc loadView];
    XCTAssertTrue([self.vc.view isKindOfClass:[NSVisualEffectView class]], @"View should be NSVisualEffectView");
}

- (void)testViewDidLoad_addsSubviews {
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    XCTAssertNotNil(self.vc.view);
    XCTAssertGreaterThan(self.vc.view.subviews.count, 0U, @"Should have added subviews");
}

- (void)testNumberOfRows_combinesRoomsAndRepos {
    // Set up rooms BEFORE viewDidLoad so _rebuildSections sees them
    SRRoomManager *manager = [SRRoomManager sharedManager];
    [manager.internalRooms removeAllObjects];
    RoomConfig *room = [[RoomConfig alloc] init];
    room.host = @"test-host";
    [manager.internalRooms addObject:room];

    [self.vc loadView];
    [self.vc viewDidLoad];

    // Sidebar layout with 1 room, 0 repos (gitRepos not seeded here):
    // Row 0: SSB (section header)
    // Rows 1-4: Home, Channels, Repositories, Peers (4 nav items)
    // Row 5: ROOMS (section header)
    // Row 6: test-host (room item)
    // Row 7: CHANNELS (section header)
    // Row 8: REPOSITORIES (section header)
    // Total: 9 rows
    NSInteger rows = [self.vc.outlineView numberOfRows];
    XCTAssertEqual(rows, 9, @"With 1 room and 0 repos: 4 sections + 4 nav items + 1 room = 9 rows");
}

- (void)testTableViewSelectionDidChange_postsNotification {
    // Set up room before viewDidLoad
    SRRoomManager *manager = [SRRoomManager sharedManager];
    [manager.internalRooms removeAllObjects];
    RoomConfig *room = [[RoomConfig alloc] init];
    room.host = @"test-host";
    [manager.internalRooms addObject:room];

    [self.vc loadView];
    [self.vc viewDidLoad];

    NSOutlineView *outlineView = self.vc.outlineView;

    // Row 6 is the room item (see testNumberOfRows_combinesRoomsAndRepos for layout)
    XCTestExpectation *expectation = [self expectationForNotification:SRRoomManagerRoomSelectedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        RoomConfig *selected = notification.userInfo[SRRoomManagerRoomSelectedKey];
        XCTAssertEqualObjects(selected.host, @"test-host");
        return YES;
    }];

    [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:6] byExtendingSelection:NO];
    [self.vc outlineViewSelectionDidChange:[NSNotification notificationWithName:NSOutlineViewSelectionDidChangeNotification object:outlineView]];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testTableView_viewForTableColumn_rendersCells {
    // Set up data before viewDidLoad
    SRRoomManager *manager = [SRRoomManager sharedManager];
    [manager.internalRooms removeAllObjects];
    RoomConfig *room = [[RoomConfig alloc] init];
    room.host = @"test-host";
    [manager.internalRooms addObject:room];

    [self.vc loadView];
    [self.vc viewDidLoad];

    SSBMessage *repoMsg = [[SSBMessage alloc] init];
    repoMsg.content = @{@"name": @"test-repo"};
    self.vc.gitRepos = @[repoMsg];
    // Trigger rebuild now that gitRepos is set (_rebuildSections also expands all sections)
    [self.vc performSelector:@selector(_rebuildSections)];

    // Current layout (1 room, 1 repo, all expanded):
    // Row 0: SSB section header → NSTextField "SSB"
    // Rows 1-4: Home/Channels/Repositories/Peers nav items → NSTableCellView
    // Row 5: ROOMS section header → NSTextField "ROOMS"
    // Row 6: test-host room → NSTableCellView
    // Row 7: CHANNELS section header → NSTextField "CHANNELS"
    // Row 8: REPOSITORIES section header → NSTextField "REPOSITORIES"
    // Row 9: test-repo → NSTableCellView

    // Row 0: SSB section header
    id item0 = [self.vc.outlineView itemAtRow:0];
    NSView *view0 = [self.vc outlineView:self.vc.outlineView viewForTableColumn:nil item:item0];
    XCTAssertTrue([view0 isKindOfClass:[NSTextField class]], @"Row 0 should be section header NSTextField");
    XCTAssertEqualObjects([(NSTextField *)view0 stringValue], @"SSB");

    // Row 5: ROOMS section header
    id item5 = [self.vc.outlineView itemAtRow:5];
    NSView *view5 = [self.vc outlineView:self.vc.outlineView viewForTableColumn:nil item:item5];
    XCTAssertTrue([view5 isKindOfClass:[NSTextField class]], @"Row 5 should be ROOMS section header");
    XCTAssertEqualObjects([(NSTextField *)view5 stringValue], @"ROOMS");

    // Row 6: test-host room cell
    id item6 = [self.vc.outlineView itemAtRow:6];
    NSView *view6 = [self.vc outlineView:self.vc.outlineView viewForTableColumn:nil item:item6];
    XCTAssertTrue([view6 isKindOfClass:[NSTableCellView class]], @"Row 6 should be room cell");
    NSTableCellView *cell6 = (NSTableCellView *)view6;
    XCTAssertEqualObjects(cell6.textField.stringValue, @"test-host");

    // Row 9: test-repo cell
    id item9 = [self.vc.outlineView itemAtRow:9];
    NSView *view9 = [self.vc outlineView:self.vc.outlineView viewForTableColumn:nil item:item9];
    XCTAssertTrue([view9 isKindOfClass:[NSTableCellView class]], @"Row 9 should be repo cell");
    NSTableCellView *cell9 = (NSTableCellView *)view9;
    XCTAssertEqualObjects(cell9.textField.stringValue, @"test-repo");
}

@end

#pragma mark - SRFeedViewControllerTests

@interface SRFeedViewController (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBMessage *> *messagesByKey;
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSCollectionViewDiffableDataSource<NSString *, NSString *> *dataSource;
@end

@interface SRFeedViewControllerTests : XCTestCase
@property (nonatomic, strong) SRFeedViewController *vc;
@end

@implementation SRFeedViewControllerTests

- (void)setUp {
    [super setUp];
    self.vc = [[SRFeedViewController alloc] init];
}

- (void)tearDown {
    self.vc = nil;
    [super tearDown];
}

- (void)testLoadView_setsUpScrollView {
    [self.vc loadView];
    XCTAssertTrue([self.vc.view isKindOfClass:[NSScrollView class]], @"View should be NSScrollView");
}

- (void)testViewDidLoad_setsUpDataSource {
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    XCTAssertNotNil(self.vc.dataSource, @"DataSource should be initialized");
    XCTAssertNotNil(self.vc.collectionView, @"CollectionView should be initialized");
}

- (void)testLoadFeedForChannel_setsFilter {
    [self.vc loadView];
    [self.vc viewDidLoad];

    [self.vc loadFeedForChannel:@"test-channel"];
    
    XCTAssertEqualObjects(self.vc.filterChannel, @"test-channel");
    XCTAssertNil(self.vc.filterAuthor);
}

- (void)testLayoutSizeForItemAtIndexPath_calculatesHeight {
    [self.vc loadView];
    [self.vc viewDidLoad];

    // Create a dummy message with large text
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = @"test-key";
    msg.content = @{@"text": @"This is a very long text sentence to force line wrapping height to exceed the minimum threshold height and be calculated properly by sizeForItemAtIndexPath delegate."};
    
    self.vc.messagesByKey[@"test-key"] = msg;

    // Apply snapshot with the key to back the dataSource
    NSDiffableDataSourceSnapshot<NSString *, NSString *> *snapshot = [NSDiffableDataSourceSnapshot new];
    [snapshot appendSectionsWithIdentifiers:@[@"main"]];
    [snapshot appendItemsWithIdentifiers:@[@"test-key"] intoSectionWithIdentifier:@"main"];
    [self.vc.dataSource applySnapshot:snapshot animatingDifferences:NO];

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:0];
    
    NSSize size = [self.vc collectionView:self.vc.collectionView layout:self.vc.collectionView.collectionViewLayout sizeForItemAtIndexPath:indexPath];
    
    XCTAssertGreaterThan(size.height, 100.0, @"Height should include padding and wrap height");
}

@end

#pragma mark - SRComposeViewControllerTests

@interface SRComposeViewController (TestAccess)
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSTextField *cwField;
@property (nonatomic, strong) NSButton *publishButton;
- (void)publishAction:(id)sender;
- (void)applySyncStatus:(nullable NSString *)status;
- (void)textDidChange:(NSNotification *)notification;
- (void)setReplyToKey:(NSString *)replyToKey;
@end

@interface SRComposeViewControllerTests : XCTestCase
@property (nonatomic, strong) SRComposeViewController *vc;
@end

@implementation SRComposeViewControllerTests

- (void)setUp {
    [super setUp];
    self.vc = [[SRComposeViewController alloc] init];
}

- (void)tearDown {
    self.vc = nil;
    [super tearDown];
}

- (void)testLoadView_setsUpSubviews {
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    XCTAssertNotNil(self.vc.textView, @"TextView should be initialized");
    XCTAssertNotNil(self.vc.publishButton, @"PublishButton should be initialized");
}

- (void)testPublishAction_triggersBlock {
    // Provide a window context to force AppKit layout and text sync
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 400) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.contentViewController = self.vc;
    [self.vc loadView];
    [self.vc viewDidLoad];

    self.vc.textView.string = @"Hello World";
    self.vc.cwField.stringValue = @"CW";
    
    __block BOOL blockCalled = NO;
    __block NSString *publishedText = nil;
    __block NSString *publishedCw = nil;
    
    self.vc.onPublish = ^(NSString *text, NSString * _Nullable cw, NSString * _Nullable replyTo, void (^completion)(BOOL, NSError * _Nullable)) {
        blockCalled = YES;
        publishedText = text;
        publishedCw = cw;
        if (completion) completion(YES, nil);
    };
    
    // Explicitly trigger action
    [self.vc publishAction:nil];
    
    // Run main thread runloop to process async delivery or clearing
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    
    XCTAssertTrue(blockCalled, @"onPublish block should be called");
    XCTAssertEqualObjects(publishedText, @"Hello World");
    XCTAssertEqualObjects(publishedCw, @"CW");
    
    // Verify cleared
    XCTAssertEqualObjects(self.vc.textView.string, @"");
    XCTAssertEqualObjects(self.vc.cwField.stringValue, @"");
}

- (void)testApplySyncStatus_updatesButton {
    [self.vc loadView];
    [self.vc viewDidLoad];

    [self.vc applySyncStatus:@"Syncing"];
    
    // Run main thread runloop to process async delivery if dispatched
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    XCTAssertFalse(self.vc.publishButton.enabled, @"Should be disabled during sync");
    XCTAssertEqualObjects(self.vc.publishButton.title, @"Syncing...");
}

- (void)testCharCountUpdates {
    [self.vc loadView];
    [self.vc viewDidLoad];

    self.vc.textView.string = @"Hello";
    [self.vc textDidChange:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self.vc.textView]];
    
    NSTextField *countLabel = [self.vc valueForKey:@"charCountLabel"];
    XCTAssertNotNil(countLabel);
    XCTAssertEqualObjects(countLabel.stringValue, @"5 / 1000");
}

- (void)testFormattingActions {
    [self.vc loadView];
    [self.vc viewDidLoad];

    self.vc.textView.string = @"Sample";
    [self.vc.textView setSelectedRange:NSMakeRange(0, 6)];
    
    [self.vc performSelector:@selector(formatBold:) withObject:nil];
    XCTAssertEqualObjects(self.vc.textView.string, @"**Sample** ");
}

- (void)testReplyBannerVisibility {
    [self.vc loadView];
    [self.vc viewDidLoad];

    NSView *banner = [self.vc valueForKey:@"replyBanner"];
    XCTAssertNotNil(banner);
    XCTAssertTrue(banner.isHidden, @"Banner should be hidden initially");

    [self.vc performSelector:@selector(setReplyToKey:) withObject:@"%msgkey.sha256"];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    XCTAssertFalse(banner.isHidden, @"Banner should be visible on replyToKey set");
}

@end

#pragma mark - SRProfileViewControllerTests

@interface MockProfileRoomClient : SSBRoomClient
@property (nonatomic, assign) BOOL mockIsConnected;
@property (nonatomic, copy) NSString *mockHost;
@property (nonatomic, copy) void (^onPublishContact)(NSString *, BOOL, SSBRPCCallback);
@property (nonatomic, copy) void (^onPublishBlock)(NSString *, BOOL, SSBRPCCallback);
@end

@implementation MockProfileRoomClient
- (BOOL)isConnected { return self.mockIsConnected; }
- (NSString *)host { return self.mockHost; }

- (void)publishContact:(NSString *)targetPubKey following:(BOOL)following completion:(nullable SSBRPCCallback)completion {
    if (self.onPublishContact) {
        self.onPublishContact(targetPubKey, following, completion);
    }
}

- (void)publishBlock:(NSString *)targetPubKey blocking:(BOOL)blocking completion:(nullable SSBRPCCallback)completion {
    if (self.onPublishBlock) {
        self.onPublishBlock(targetPubKey, blocking, completion);
    }
}
@end

@interface SRProfileViewController (TestAccess)
@property (nonatomic, strong) SRProfileHeaderView *headerView;
@property (nonatomic, strong) NSButton *followButton;
@property (nonatomic, strong) NSButton *blockButton;
- (void)updateFollowButton;
- (void)followAction:(id)sender;
- (void)blockAction:(id)sender;
@end

@interface SRProfileViewControllerTests : XCTestCase
@property (nonatomic, strong) SRProfileViewController *vc;
@end

@implementation SRProfileViewControllerTests

- (void)setUp {
    [super setUp];
    self.vc = [[SRProfileViewController alloc] initWithPeerID:@"@test-peer-id" client:nil];
}

- (void)tearDown {
    self.vc = nil;
    [super tearDown];
}

- (void)testLoadView_setsUpSubviews {
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    XCTAssertNotNil(self.vc.headerView, @"HeaderView should be initialized");
    XCTAssertNotNil(self.vc.followButton, @"FollowButton should be initialized");
    XCTAssertNotNil(self.vc.blockButton, @"BlockButton should be initialized");
}

- (void)testUpdateFollowButton_updatesTitle {
    [self.vc loadView];
    [self.vc viewDidLoad];

    [self.vc updateFollowButton];
    XCTAssertTrue([self.vc.followButton.title isEqualToString:@"Follow"] || [self.vc.followButton.title isEqualToString:@"Unfollow"]);
}

- (void)testFollowAction_triggersPublishContact {
    MockProfileRoomClient *client = [[MockProfileRoomClient alloc] initWithHost:@"dummy" port:8008 serverPubKey:[NSData data] localIdentity:nil];
    client.mockIsConnected = YES;
    client.mockHost = @"test-host";
    
    self.vc = [[SRProfileViewController alloc] initWithPeerID:@"@test-peer-id" client:client];
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    __block BOOL blockCalled = NO;
    client.onPublishContact = ^(NSString *target, BOOL following, SSBRPCCallback completion) {
        blockCalled = YES;
        XCTAssertEqualObjects(target, @"@test-peer-id");
        if (completion) completion(@"success", nil);
    };
    
    [self.vc followAction:nil];
    XCTAssertTrue(blockCalled, @"publishContact should be triggered");
}

- (void)testBlockAction_triggersPublishBlock {
    MockProfileRoomClient *client = [[MockProfileRoomClient alloc] initWithHost:@"dummy" port:8008 serverPubKey:[NSData data] localIdentity:nil];
    client.mockIsConnected = YES;
    client.mockHost = @"test-host";
    
    self.vc = [[SRProfileViewController alloc] initWithPeerID:@"@test-peer-id" client:client];
    [self.vc loadView];
    [self.vc viewDidLoad];
    
    __block BOOL blockCalled = NO;
    client.onPublishBlock = ^(NSString *target, BOOL blocking, SSBRPCCallback completion) {
        blockCalled = YES;
        XCTAssertEqualObjects(target, @"@test-peer-id");
        if (completion) completion(@"success", nil);
    };
    
    [self.vc blockAction:nil];
    XCTAssertTrue(blockCalled, @"publishBlock should be triggered");
}

@end
