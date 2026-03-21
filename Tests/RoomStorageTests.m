#import <XCTest/XCTest.h>
#import <SSBNetwork/RoomStorage.h>
#import <SSBNetwork/RoomInviteHandler.h>

/// Helpers to build RoomConfig test fixtures.
static RoomConfig *makeRoom(NSString *host, NSUInteger port, NSString *pubKey) {
    RoomConfig *c = [[RoomConfig alloc] init];
    c.host = host;
    c.port = port;
    c.serverPubKey = pubKey;
    return c;
}

@interface RoomStorageTests : XCTestCase
@end

@implementation RoomStorageTests

- (void)setUp {
    [super setUp];
    [RoomStorage clearAll];
}

- (void)tearDown {
    [RoomStorage clearAll];
    [super tearDown];
}

#pragma mark - listRooms

- (void)testListRooms_emptyByDefault {
    XCTAssertEqualObjects([RoomStorage listRooms], @[]);
}

#pragma mark - saveRoom

- (void)testSaveRoom_appearsInList {
    RoomConfig *r = makeRoom(@"room.example.com", 8008, @"abc123");
    [RoomStorage saveRoom:r];

    NSArray<RoomConfig *> *list = [RoomStorage listRooms];
    XCTAssertEqual(list.count, 1U);
    XCTAssertEqualObjects(list.firstObject.host, @"room.example.com");
    XCTAssertEqual(list.firstObject.port, 8008U);
}

- (void)testSaveRoom_multipleRooms {
    [RoomStorage saveRoom:makeRoom(@"alpha.example.com", 8008, @"key1")];
    [RoomStorage saveRoom:makeRoom(@"beta.example.com", 8009, @"key2")];

    NSArray<RoomConfig *> *list = [RoomStorage listRooms];
    XCTAssertEqual(list.count, 2U);
}

- (void)testSaveRoom_duplicateHostAndPort_updatesInPlace {
    RoomConfig *r1 = makeRoom(@"room.example.com", 8008, @"key1");
    RoomConfig *r2 = makeRoom(@"room.example.com", 8008, @"key2");
    [RoomStorage saveRoom:r1];
    [RoomStorage saveRoom:r2];

    NSArray<RoomConfig *> *list = [RoomStorage listRooms];
    XCTAssertEqual(list.count, 1U, @"Duplicate host:port must not create a second entry");
    XCTAssertEqualObjects(list.firstObject.serverPubKey, @"key2", @"Updated key must be reflected");
}

#pragma mark - removeRoom

- (void)testRemoveRoom_removesCorrectEntry {
    RoomConfig *r1 = makeRoom(@"alpha.example.com", 8008, @"key1");
    RoomConfig *r2 = makeRoom(@"beta.example.com", 8009, @"key2");
    [RoomStorage saveRoom:r1];
    [RoomStorage saveRoom:r2];

    [RoomStorage removeRoom:r1];

    NSArray<RoomConfig *> *list = [RoomStorage listRooms];
    XCTAssertEqual(list.count, 1U);
    XCTAssertEqualObjects(list.firstObject.host, @"beta.example.com");
}

- (void)testRemoveRoom_nonExistent_isNoOp {
    RoomConfig *r = makeRoom(@"room.example.com", 8008, @"key");
    [RoomStorage saveRoom:r];
    [RoomStorage removeRoom:makeRoom(@"other.example.com", 9000, @"other")];

    XCTAssertEqual([RoomStorage listRooms].count, 1U);
}

#pragma mark - clearAll

- (void)testClearAll_emptyList {
    [RoomStorage saveRoom:makeRoom(@"room.example.com", 8008, @"key")];
    [RoomStorage clearAll];

    XCTAssertEqualObjects([RoomStorage listRooms], @[]);
}

@end
