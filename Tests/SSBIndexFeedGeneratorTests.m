#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBIndexFeedGenerator.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBMessage.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBFeedCodecRegistry.h>
#import <SSBNetwork/SSBIndexFeed.h>

@interface MockIdxCodec : NSObject <SSBFeedCodec>
@property (nonatomic, assign) SSBBFEFeedFormat feedFormat;
@end
@implementation MockIdxCodec
- (BOOL)verifyMessageData:(NSData *)d error:(NSError **)e { return YES; }
- (nullable NSData *)computeMessageKeyFromData:(NSData *)d error:(NSError **)e {
    return [@"%mock.sha256" dataUsingEncoding:NSUTF8StringEncoding];
}
- (SSBBFEMessageFormat)messageFormat { return SSBBFEMessageFormatClassic; }
@end

static void insertIdxMsg(SSBFeedStore *store, NSString *key, NSString *author,
                         NSInteger seq, NSString *prev, NSString *type) {
    SSBMessage *m = [[SSBMessage alloc] init];
    m.key = key;
    m.author = author;
    m.sequence = seq;
    m.previousKey = prev;
    m.claimedTimestamp = (int64_t)(seq * 1000);
    m.valueJSON = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    m.content = @{@"type": type};
    m.contentType = type;
    m.feedFormat = SSBBFEFeedFormatClassic;
    [store appendMessage:m error:nil];
}

@interface SSBIndexFeedGeneratorTests : XCTestCase
@property (nonatomic, strong) SSBFeedStore *feedStore;
@property (nonatomic, copy) NSString *dbPath;
@property (nonatomic, strong) SSBIndexFeedGenerator *generator;
@end

@implementation SSBIndexFeedGeneratorTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"idxgen_%@.db", [[NSUUID UUID] UUIDString]]];
    self.feedStore = [[SSBFeedStore alloc] initWithPath:self.dbPath];
    [self.feedStore wipeDatabase];

    MockIdxCodec *codec = [[MockIdxCodec alloc] init];
    codec.feedFormat = SSBBFEFeedFormatClassic;
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:codec];

    self.generator = [[SSBIndexFeedGenerator alloc] initWithFeedStore:self.feedStore];
}

- (void)tearDown {
    [self.feedStore wipeDatabase];
    self.feedStore = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - generateIndexForContentType

- (void)testGenerateIndexForContentType_emptyDB_returnsEmpty {
    NSArray *result = [self.generator generateIndexForContentType:@"post" limit:100];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testGenerateIndexForContentType_returnsDicts {
    insertIdxMsg(self.feedStore, @"%p1.sha256", @"@alice.ed25519", 1, nil, @"post");
    insertIdxMsg(self.feedStore, @"%p2.sha256", @"@alice.ed25519", 2, @"%p1.sha256", @"post");

    NSArray<NSDictionary *> *result = [self.generator generateIndexForContentType:@"post" limit:10];
    XCTAssertEqual(result.count, 2U);
    // createIndexMessageWithKey:sequence: returns {type, indexed: {key, sequence}}.
    for (NSDictionary *d in result) {
        XCTAssertNotNil(d[@"type"], @"Index dict must contain a type field");
        NSDictionary *indexed = d[@"indexed"];
        XCTAssertNotNil(indexed, @"Index dict must contain an 'indexed' sub-dict");
        XCTAssertNotNil(indexed[@"key"], @"indexed sub-dict must contain a key field");
    }
}

- (void)testGenerateIndexForContentType_limit_respected {
    for (int i = 1; i <= 5; i++) {
        NSString *key = [NSString stringWithFormat:@"%%p%d.sha256", i];
        NSString *prev = i > 1 ? [NSString stringWithFormat:@"%%p%d.sha256", i-1] : nil;
        insertIdxMsg(self.feedStore, key, @"@alice.ed25519", i, prev, @"post");
    }
    NSArray *result = [self.generator generateIndexForContentType:@"post" limit:3];
    XCTAssertLessThanOrEqual(result.count, 3U);
}

- (void)testGenerateIndexForContentType_wrongType_returnsEmpty {
    insertIdxMsg(self.feedStore, @"%p1.sha256", @"@alice.ed25519", 1, nil, @"contact");
    NSArray *result = [self.generator generateIndexForContentType:@"post" limit:10];
    XCTAssertEqualObjects(result, @[]);
}

#pragma mark - generateIndexForAuthor

- (void)testGenerateIndexForAuthor_emptyDB_returnsEmpty {
    NSArray *result = [self.generator generateIndexForAuthor:@"@alice.ed25519" limit:100];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testGenerateIndexForAuthor_returnsDicts {
    insertIdxMsg(self.feedStore, @"%p1.sha256", @"@alice.ed25519", 1, nil, @"post");
    insertIdxMsg(self.feedStore, @"%p2.sha256", @"@alice.ed25519", 2, @"%p1.sha256", @"post");

    NSArray<NSDictionary *> *result = [self.generator generateIndexForAuthor:@"@alice.ed25519" limit:10];
    XCTAssertEqual(result.count, 2U);
    for (NSDictionary *d in result) {
        XCTAssertNotNil(d[@"indexed"][@"key"], @"indexed sub-dict must contain a key field");
    }
}

- (void)testGenerateIndexForAuthor_excludesOtherAuthors {
    insertIdxMsg(self.feedStore, @"%p1.sha256", @"@bob.ed25519", 1, nil, @"post");
    NSArray *result = [self.generator generateIndexForAuthor:@"@alice.ed25519" limit:10];
    XCTAssertEqualObjects(result, @[]);
}

- (void)testGenerateIndexForAuthor_limit_respected {
    for (int i = 1; i <= 5; i++) {
        NSString *key = [NSString stringWithFormat:@"%%a%d.sha256", i];
        NSString *prev = i > 1 ? [NSString stringWithFormat:@"%%a%d.sha256", i-1] : nil;
        insertIdxMsg(self.feedStore, key, @"@alice.ed25519", i, prev, @"post");
    }
    NSArray *result = [self.generator generateIndexForAuthor:@"@alice.ed25519" limit:2];
    XCTAssertLessThanOrEqual(result.count, 2U);
}

@end
