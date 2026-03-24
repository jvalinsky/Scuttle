#import <XCTest/XCTest.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

/// Returns YES if go-ssb-room is reachable on 127.0.0.1:8008.
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

/// Derive the project root from this source file path (__FILE__ is absolute at compile time).
static NSString *ProjectRoot(void) {
    NSString *thisFile = @(__FILE__);
    // Tests/ScuttleRoomAppUITests/ScuttleRoomAppDockerUITests.m → go up 2 dirs
    return [[thisFile stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
               .stringByDeletingLastPathComponent;
}

/// Read the room's `@pubkey.ed25519` ID from ssb-room-data/server-id.txt and
/// return a colon-separated invite code: `localhost:8008:<base64key>:open`
static NSString *InviteCodeFromServerID(void) {
    NSString *idFile = [ProjectRoot() stringByAppendingPathComponent:@"ssb-room-data/server-id.txt"];
    NSString *serverID = [[NSString stringWithContentsOfFile:idFile
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil] stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (serverID.length == 0) return nil;

    // serverID is "@<base64>.ed25519". Extract just the base64+suffix.
    NSString *key = serverID;
    if ([key hasPrefix:@"@"]) {
        key = [key substringFromIndex:1];
    }
    return [NSString stringWithFormat:@"localhost:8008:%@:open", key];
}

// ---------------------------------------------------------------------------

@interface ScuttleRoomAppDockerUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation ScuttleRoomAppDockerUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;

    self.app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.scuttlebutt.ScuttleRoomApp"];
    // Isolate test state: skip auto-loading saved rooms
    self.app.launchArguments = @[@"-SSBUITestMode"];
    [self.app launch];
}

- (void)tearDown {
    [self.app terminate];
    [super tearDown];
}

// ---------------------------------------------------------------------------
#pragma mark - Helpers

/// Open Window → Manage Rooms and return the room management window.
- (XCUIElement *)openManageRoomsWindow {
    XCUIElement *windowMenu = self.app.menuBars.menuBarItems[@"Window"];
    [windowMenu click];
    [windowMenu.menuItems[@"Manage Rooms"] click];

    XCUIElement *roomWindow = self.app.windows[@"Manage Rooms"];
    XCTAssertTrue([roomWindow waitForExistenceWithTimeout:5.0], @"Manage Rooms window should appear");
    return roomWindow;
}

// ---------------------------------------------------------------------------
#pragma mark - Tests

/// Smoke test: the Manage Rooms window opens and shows the invite field.
/// Does not require Docker.
- (void)testManageRoomsWindowOpensAndShowsInviteField {
    XCUIElement *roomWindow = [self openManageRoomsWindow];

    XCUIElement *inviteField = roomWindow.textFields[@"room-invite-field"];
    XCTAssertTrue([inviteField waitForExistenceWithTimeout:3.0],
                  @"Invite field should be visible in Manage Rooms window");
    XCTAssertTrue(inviteField.isEnabled, @"Invite field should be enabled");

    XCUIElement *joinButton = roomWindow.buttons[@"room-join-button"];
    XCTAssertTrue(joinButton.exists, @"Join Room button should be visible");
}

/// Type an invite code, click Join, and wait until the status cell shows Connected.
/// Requires Docker room on localhost:8008.
- (void)testJoinDockerRoomViaInviteCodeUI {
    if (!DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008 — start with `docker compose up -d`");
    }

    NSString *invite = InviteCodeFromServerID();
    if (!invite) {
        XCTSkip(@"ssb-room-data/server-id.txt not found — run tools/generate-room-keypair.sh first");
    }

    XCUIElement *roomWindow = [self openManageRoomsWindow];
    XCUIElement *inviteField = roomWindow.textFields[@"room-invite-field"];
    XCTAssertTrue([inviteField waitForExistenceWithTimeout:3.0]);

    [inviteField click];
    [inviteField typeText:invite];

    XCUIElement *joinButton = roomWindow.buttons[@"room-join-button"];
    [joinButton click];

    // Wait for the table to show at least one row with "Connected" status.
    NSPredicate *connected = [NSPredicate predicateWithFormat:
        @"value CONTAINS '🟢 Connected'"];
    XCUIElement *statusCell = [roomWindow.tables[@"rooms-table"]
        .staticTexts elementMatchingPredicate:connected];
    XCTAssertTrue([statusCell waitForExistenceWithTimeout:30.0],
                  @"Room status should show 🟢 Connected within 30s of joining");
}

/// Launch the app with -SSBAutoJoinRoom <invite> and verify it connects automatically.
/// Requires Docker room on localhost:8008.
- (void)testAutoJoinDockerRoomViaLaunchArg {
    if (!DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008 — start with `docker compose up -d`");
    }

    NSString *invite = InviteCodeFromServerID();
    if (!invite) {
        XCTSkip(@"ssb-room-data/server-id.txt not found — run tools/generate-room-keypair.sh first");
    }

    // Relaunch with auto-join arg
    [self.app terminate];
    self.app.launchArguments = @[@"-SSBUITestMode", @"-SSBAutoJoinRoom", invite];
    [self.app launch];

    XCUIElement *roomWindow = [self openManageRoomsWindow];

    NSPredicate *connected = [NSPredicate predicateWithFormat:
        @"value CONTAINS '🟢 Connected'"];
    XCUIElement *statusCell = [roomWindow.tables[@"rooms-table"]
        .staticTexts elementMatchingPredicate:connected];
    XCTAssertTrue([statusCell waitForExistenceWithTimeout:30.0],
                  @"Auto-join should result in 🟢 Connected row within 30s");
}

/// After joining, the table should show the room host name and a Leave button.
/// Requires Docker room on localhost:8008.
- (void)testRoomTableReflectsLiveConnectionStatus {
    if (!DockerRoomReachable()) {
        XCTSkip(@"go-ssb-room not reachable on localhost:8008 — start with `docker compose up -d`");
    }

    NSString *invite = InviteCodeFromServerID();
    if (!invite) {
        XCTSkip(@"ssb-room-data/server-id.txt not found — run tools/generate-room-keypair.sh first");
    }

    XCUIElement *roomWindow = [self openManageRoomsWindow];
    XCUIElement *inviteField = roomWindow.textFields[@"room-invite-field"];
    XCTAssertTrue([inviteField waitForExistenceWithTimeout:3.0]);
    [inviteField click];
    [inviteField typeText:invite];
    [roomWindow.buttons[@"room-join-button"] click];

    XCUIElement *table = roomWindow.tables[@"rooms-table"];
    XCTAssertTrue([table waitForExistenceWithTimeout:5.0]);

    // Wait for Connected
    NSPredicate *connected = [NSPredicate predicateWithFormat:
        @"value CONTAINS '🟢 Connected'"];
    XCUIElement *statusCell = [table.staticTexts elementMatchingPredicate:connected];
    XCTAssertTrue([statusCell waitForExistenceWithTimeout:30.0]);

    // Host name cell should contain "localhost"
    XCUIElement *nameCell = table.staticTexts[@"room-name-0"];
    XCTAssertTrue([nameCell waitForExistenceWithTimeout:3.0]);
    XCTAssertTrue([nameCell.value containsString:@"localhost"],
                  @"Name cell should show the room host (localhost), got: %@", nameCell.value);

    // Leave button should exist
    XCUIElement *leaveButton = table.buttons[@"room-leave-0"];
    XCTAssertTrue(leaveButton.exists, @"Leave button should be present in the first row");
}

@end
