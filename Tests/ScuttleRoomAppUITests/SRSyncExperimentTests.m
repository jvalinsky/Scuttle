//
// SRSyncExperimentTests.m
//
// XCTest UI automation experiment harness for investigating GUI sync behaviour.
//
// Each testExp* method corresponds to one hypothesis. Tests skip gracefully when
// Docker is unavailable so they never block CI.
//
// Deciduous workflow (run by hand before/after each experiment):
//   deciduous add goal "Exp N: <hypothesis>" -c <pct> --prompt-stdin
//   deciduous link <root_id> <exp_id>
//   ... run the test ...
//   deciduous add outcome "Exp N result: <summary>" --commit HEAD
//   deciduous link <exp_id> <outcome_id>
//   deciduous doc attach <outcome_id> docs/research/scratchpads/exp_N_*.md
//
// Root investigation node: 414 ("Investigate GUI sync: UI bug or protocol failure?")
//

#import <XCTest/XCTest.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

// ---------------------------------------------------------------------------
#pragma mark - Utilities

static BOOL DockerRoomReachable(void) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8008);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    int result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    close(sock);
    return result == 0;
}

static NSString *ProjectRoot(void) {
    NSString *thisFile = @(__FILE__);
    return [[thisFile stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent]
                      .stringByDeletingLastPathComponent;
}

static NSString *InviteCodeFromServerID(void) {
    NSString *techpriestFile = [ProjectRoot() stringByAppendingPathComponent:@"ssb-room-data/techpriest-invite.txt"];
    NSString *techpriestInvite = [[NSString stringWithContentsOfFile:techpriestFile
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (techpriestInvite.length > 0) return techpriestInvite;

    NSString *idFile = [ProjectRoot() stringByAppendingPathComponent:@"ssb-room-data/server-id.txt"];
    NSString *serverID = [[NSString stringWithContentsOfFile:idFile
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (serverID.length == 0) return nil;
    NSString *key = [serverID hasPrefix:@"@"] ? [serverID substringFromIndex:1] : serverID;
    return [NSString stringWithFormat:@"localhost:8008:%@:open", key];
}

static NSString *HostFromInvite(NSString *invite) {
    if ([invite hasPrefix:@"ssb:room-invite:"]) {
        invite = [invite substringFromIndex:16];
    }
    NSArray *parts = [invite componentsSeparatedByString:@":"];
    if (parts.count > 0) return parts[0];
    return @"";
}

// ---------------------------------------------------------------------------
#pragma mark - Base Test Class

@interface SRSyncExperimentTests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@property (nonatomic, copy) NSString *experimentLogPath;
@end

@implementation SRSyncExperimentTests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
    self.app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.scuttlebutt.ScuttleRoomApp"];

    // Unique log file per test run
    NSString *tmpDir = NSTemporaryDirectory();
    self.experimentLogPath = [tmpDir stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"scuttle_exp_%@.jsonl",
                               [NSUUID UUID].UUIDString]];
}

- (void)tearDown {
    [self.app terminate];
    // Leave log file on disk for inspection; print path for debugging
    NSLog(@"[SRSyncExperiment] Log file: %@", self.experimentLogPath);
    [super tearDown];
}

// ---------------------------------------------------------------------------
#pragma mark - Shared Helpers

/// Launch the app in UITest isolation mode, joining the given invite code.
- (void)launchWithInvite:(NSString *)invite {
    self.app.launchArguments = @[
        @"-SSBUITestMode",
        @"-SSBAutoJoinRoom", invite,
        @"-SSBExperimentLogPath", self.experimentLogPath
    ];
    [self.app launch];
}

/// Click the Network strip button, select the Room item, then click the Peers sidebar item.
/// Returns the peer list table element.
- (XCUIElement *)navigateToPeerListWithRoomHost:(NSString *)roomHost {
    // 1. Click Network strip button (identifier set by SRStripViewController)
    XCUIElement *networkBtn = self.app.buttons[@"strip-btn-network"];
    XCTAssertTrue([networkBtn waitForExistenceWithTimeout:5.0],
                  @"Network strip button should exist");
    [networkBtn click];

    XCUIElement *mainWindow = self.app.windows.firstMatch;

    // 1.5 Click Room item first to set the local context, avoiding the empty roomHost bug
    if (roomHost.length > 0) {
        XCUIElement *roomText = mainWindow.staticTexts[roomHost].firstMatch;
        XCTAssertTrue([roomText waitForExistenceWithTimeout:5.0],
                      @"Room item should appear in sidebar");
        [roomText click];
        [NSThread sleepForTimeInterval:0.5]; // Wait for TEA update
    }

    // 2. Click Peers sidebar item.
    XCUIElement *peersText = mainWindow.staticTexts[@"Peers"];
    XCTAssertTrue([peersText waitForExistenceWithTimeout:5.0],
                  @"'Peers' sidebar item should appear after clicking Network");
    [peersText click];

    // 3. Return the peer list table
    XCUIElement *table = self.app.tables[@"peer-list-table"];
    XCTAssertTrue([table waitForExistenceWithTimeout:5.0],
                  @"peer-list-table should be visible after clicking Peers");
    return table;
}

/// Parse the experiment JSONL log and return all events as an array of dictionaries.
- (NSArray<NSDictionary *> *)readLog {
    NSString *contents = [NSString stringWithContentsOfFile:self.experimentLogPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (contents.length == 0) return @[];
    NSMutableArray *events = [NSMutableArray array];
    for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data
                                                            options:0 error:nil];
        if (obj) [events addObject:obj];
    }
    return [events copy];
}

/// Filter log events by event type name.
- (NSArray<NSDictionary *> *)logEventsOfType:(NSString *)type {
    return [[self readLog] filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"event == %@", type]];
}

/// Poll the peer list table every 5 seconds for the given duration.
/// Calls the sampling block with (rowCount, array of peer-status-N label values).
- (void)pollFor:(NSTimeInterval)duration
       sampling:(void (^)(NSInteger peerCount, NSArray<NSString *> *statusValues))block {
    XCUIElement *table = self.app.tables[@"peer-list-table"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:duration];
    while ([NSDate date].timeIntervalSince1970 < deadline.timeIntervalSince1970) {
        NSInteger rowCount = table.tableRows.count;
        NSMutableArray *statuses = [NSMutableArray array];
        for (NSInteger i = 0; i < rowCount; i++) {
            NSString *identifier = [NSString stringWithFormat:@"peer-status-%ld", (long)i];
            XCUIElement *label = self.app.staticTexts[identifier];
            [statuses addObject:label.exists ? (label.value ?: @"") : @""];
        }
        block(rowCount, [statuses copy]);
        [NSThread sleepForTimeInterval:5.0];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Experiment 1: Peer Discovery

/// Hypothesis: After joining the room, no peers ever appear in the peer list table,
/// meaning endpoints notifications never fire or the peer list never updates.
- (void)testExp1_PeerDiscovery {
    NSString *invite = InviteCodeFromServerID();
    if (!invite) { XCTSkip(@"No invite code found"); }
    BOOL isLocal = [invite containsString:@"localhost"];
    if (isLocal && !DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008");
    }

    [self launchWithInvite:invite];
    XCUIElement *table = [self navigateToPeerListWithRoomHost:HostFromInvite(invite)];

    // Poll the experiment log for endpoints events with count > 0 to test peer discovery
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60.0];
    BOOL foundEndpoints = NO;
    while ([NSDate date].timeIntervalSince1970 < deadline.timeIntervalSince1970) {
        NSArray *ep = [self logEventsOfType:@"endpoints"];
        for (NSDictionary *ev in ep) {
            if ([ev[@"count"] integerValue] > 0) {
                foundEndpoints = YES;
                break;
            }
        }
        if (foundEndpoints) break;
        [NSThread sleepForTimeInterval:2.0];
    }

    NSArray *epEvents = [self logEventsOfType:@"endpoints"];
    NSLog(@"[Exp1] Table rows: %ld, endpoints events: %lu",
          (long)table.tableRows.count, (unsigned long)epEvents.count);
    for (NSDictionary *ev in epEvents) {
        NSLog(@"[Exp1] endpoints event: %@", ev);
    }

    XCTAssertTrue(foundEndpoints,
                   @"Exp1 FAILED: No peers appeared after 60s (endpoints with count > 0 not found). "
                   @"endpoints events in log: %lu. Check scratchpad exp_1_peer_discovery.md",
                   (unsigned long)epEvents.count);

    NSInteger nonEmptyPeerLists = 0;
    for (NSDictionary *ev in epEvents) {
        if ([ev[@"count"] integerValue] > 0) nonEmptyPeerLists++;
    }
    XCTAssertGreaterThan(nonEmptyPeerLists, 0,
                         @"Exp1 FAILED: endpoints events fired but all had empty peer lists");
}

// ---------------------------------------------------------------------------
#pragma mark - Experiment 2: Sync Status Changes

/// Hypothesis: Peers appear in the list (Exp1 passes) but every peer-status label
/// stays empty — meaning EBT clock exchange never starts.
- (void)testExp2_SyncStatusChanges {
    NSString *invite = InviteCodeFromServerID();
    if (!invite) { XCTSkip(@"No invite code found"); }
    BOOL isLocal = [invite containsString:@"localhost"];
    if (isLocal && !DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008");
    }

    [self launchWithInvite:invite];
    XCUIElement *table = [self navigateToPeerListWithRoomHost:HostFromInvite(invite)];

    // Wait for endpoints to arrive in the log
    XCTAssertTrue([self waitForEndpointsWithCountGreaterThanZero],
                  @"Exp2 FAILED: endpoints with > 0 peers not found in log");

    // Wait for at least one peer to appear in the table
    NSPredicate *hasPeers = [NSPredicate predicateWithFormat:@"tableRows.count > 0"];
    [self expectationForPredicate:hasPeers evaluatedWithObject:table handler:nil];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    // Now poll for 90s collecting all unique status strings seen
    NSMutableSet *seenStatuses = [NSMutableSet set];
    [self pollFor:90.0 sampling:^(NSInteger peerCount, NSArray<NSString *> *statusValues) {
        for (NSString *s in statusValues) {
            if (s.length > 0) [seenStatuses addObject:s];
        }
        NSLog(@"[Exp2] peerCount=%ld statuses=%@", (long)peerCount, statusValues);
    }];

    NSArray *syncEvents = [self logEventsOfType:@"sync_status"];
    NSLog(@"[Exp2] Seen UI statuses: %@", seenStatuses);
    NSLog(@"[Exp2] sync_status log events: %lu", (unsigned long)syncEvents.count);

    // At least one non-empty status should have appeared
    NSSet *meaningfulStatuses = [NSSet setWithObjects:@"Ready", nil];
    BOOL sawMeaningful = NO;
    for (NSString *s in seenStatuses) {
        if ([s containsString:@"Receiving"] || [s containsString:@"Sending"] ||
            [s containsString:@"Ready"]) {
            sawMeaningful = YES;
        }
    }
    XCTAssertTrue(sawMeaningful || syncEvents.count > 0,
                  @"Exp2 FAILED: No sync status changes observed after 90s. "
                  @"UI statuses: %@. Log events: %lu. See exp_2_sync_status.md",
                  seenStatuses, (unsigned long)syncEvents.count);
    (void)meaningfulStatuses;
}

// ---------------------------------------------------------------------------
#pragma mark - Experiment 3: Sync Progress Advances

/// Hypothesis: Sync shows "Receiving X%" but stalls at a fixed value, suggesting
/// messages arrive but cannot be appended (verification failure or pipeline deadlock).
- (void)testExp3_SyncProgressAdvances {
    NSString *invite = InviteCodeFromServerID();
    if (!invite) { XCTSkip(@"No invite code found"); }
    BOOL isLocal = [invite containsString:@"localhost"];
    if (isLocal && !DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008");
    }

    [self launchWithInvite:invite];
    [self navigateToPeerListWithRoomHost:HostFromInvite(invite)];

    XCTAssertTrue([self waitForEndpointsWithCountGreaterThanZero],
                  @"Exp3 FAILED: endpoints with > 0 peers not found in log");

    // Wait until sync starts in the log (or UI, but log is more reliable given Exp2 UI bug)
    __block BOOL syncStarted = NO;
    for (int i = 0; i < 90; i++) {
        NSArray *syncEvents = [self logEventsOfType:@"sync_status"];
        for (NSDictionary *ev in syncEvents) {
            NSString *stat = ev[@"status"];
            if ([stat containsString:@"Receiving"] || [stat containsString:@"Sending"]) {
                syncStarted = YES;
                break;
            }
        }
        if (syncStarted) break;
        [NSThread sleepForTimeInterval:1.0];
    }
    
    if (!syncStarted) {
        NSLog(@"[Exp3] Sync never started (no Receiving/Sending in log)");
        XCTSkip(@"Exp3 requires synchronization to start — never saw Receiving/Sending in log");
    }

    // Record progress values from log over 120s
    NSMutableArray<NSNumber *> *progressSamples = [NSMutableArray array];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while ([NSDate date].timeIntervalSince1970 < deadline.timeIntervalSince1970) {
        NSArray *syncEvents = [self logEventsOfType:@"sync_status"];
        float latestProgress = 0;
        for (NSDictionary *ev in syncEvents) {
            float p = [ev[@"progress"] floatValue];
            if (p > latestProgress) latestProgress = p;
        }
        [progressSamples addObject:@(latestProgress)];
        NSLog(@"[Exp3] progress sample: %.3f", latestProgress);
        [NSThread sleepForTimeInterval:10.0];
    }

    NSArray *replicatedEvents = [self logEventsOfType:@"replicated"];
    NSInteger totalReplicated = 0;
    for (NSDictionary *ev in replicatedEvents) {
        totalReplicated += [ev[@"count"] integerValue];
    }
    NSLog(@"[Exp3] Progress samples: %@", progressSamples);
    NSLog(@"[Exp3] Total replicated messages: %ld", (long)totalReplicated);

    // Check that progress increased at least twice across samples
    NSInteger increases = 0;
    for (NSUInteger i = 1; i < progressSamples.count; i++) {
        if ([progressSamples[i] floatValue] > [progressSamples[i-1] floatValue]) {
            increases++;
        }
    }
    XCTAssertGreaterThan(increases, 1,
                         @"Exp3 FAILED: Progress stalled. samples=%@ increases=%ld replicated=%ld. "
                         @"See exp_3_progress.md",
                         progressSamples, (long)increases, (long)totalReplicated);
}

// ---------------------------------------------------------------------------
#pragma mark - Experiment 4: UI vs Reality

/// Hypothesis: Messages ARE being stored (didReplicateMessagesFromPeer fires) but the
/// UI sync status never updates, revealing a notification routing bug, not a protocol bug.
- (void)testExp4_UIvsReality {
    NSString *invite = InviteCodeFromServerID();
    if (!invite) { XCTSkip(@"No invite code found"); }
    BOOL isLocal = [invite containsString:@"localhost"];
    if (isLocal && !DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008");
    }

    [self launchWithInvite:invite];
    [self navigateToPeerListWithRoomHost:HostFromInvite(invite)];

    XCTAssertTrue([self waitForEndpointsWithCountGreaterThanZero],
                  @"Exp4 FAILED: endpoints with > 0 peers not found in log");

    // Observe for 90s then compare replicated vs sync_status events
    [NSThread sleepForTimeInterval:90.0];

    NSArray *replicatedEvents = [self logEventsOfType:@"replicated"];
    NSArray *syncStatusEvents = [self logEventsOfType:@"sync_status"];

    NSInteger totalReplicated = 0;
    for (NSDictionary *ev in replicatedEvents) {
        totalReplicated += [ev[@"count"] integerValue];
    }

    NSLog(@"[Exp4] replicated events: %lu total messages: %ld",
          (unsigned long)replicatedEvents.count, (long)totalReplicated);
    NSLog(@"[Exp4] sync_status events: %lu", (unsigned long)syncStatusEvents.count);

    // Collect what the UI actually showed
    NSMutableSet *uiStatuses = [NSMutableSet set];
    for (NSInteger i = 0; i < 5; i++) {
        XCUIElement *label = self.app.staticTexts[
            [NSString stringWithFormat:@"peer-status-%ld", (long)i]];
        if (label.exists && [(NSString *)label.value length] > 0) {
            [uiStatuses addObject:label.value];
        }
    }
    NSLog(@"[Exp4] Final UI statuses: %@", uiStatuses);

    // Key discriminator:
    if (totalReplicated > 0 && syncStatusEvents.count == 0) {
        XCTFail(@"Exp4 CONFIRMED UI BUG: %ld messages replicated but zero sync_status "
                @"notifications posted. SRRoomManager delegate→notification path is broken. "
                @"See exp_4_ui_vs_reality.md",
                (long)totalReplicated);
    } else if (totalReplicated == 0 && syncStatusEvents.count == 0) {
        XCTFail(@"Exp4: Nothing happened — no replication AND no status updates. "
                @"Protocol failure upstream. Check Exp1 and Exp2 first. "
                @"See exp_4_ui_vs_reality.md");
    } else {
        // Either both fired (working) or only sync_status without replication (partial)
        NSLog(@"[Exp4] PASS: replicated=%ld sync_status_events=%lu ui_statuses=%@",
              (long)totalReplicated, (unsigned long)syncStatusEvents.count, uiStatuses);
    }
}

- (BOOL)waitForEndpointsWithCountGreaterThanZero {
    for (int i = 0; i < 60; i++) {
        NSArray *events = [self logEventsOfType:@"endpoints"];
        for (NSDictionary *ev in events) {
            if ([ev[@"count"] integerValue] > 0) {
                return YES;
            }
        }
        [NSThread sleepForTimeInterval:1.0];
    }
    return NO;
}

@end

