#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBFeedCodecRegistry.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBBFE.h>

// Import codecs to ensure their +load methods fire (they self-register).
#import <SSBNetwork/SSBGabbyGrove.h>
#import <SSBNetwork/SSBButtwoo.h>
#import <SSBNetwork/SSBBamboo.h>
#import <SSBNetwork/SSBBendyButt.h>

// Minimal test codec that conforms to SSBFeedCodec for registration tests.
@interface TestCodec : NSObject <SSBFeedCodec>
- (instancetype)initWithFeedFormat:(SSBBFEFeedFormat)feedFormat
                     messageFormat:(SSBBFEMessageFormat)messageFormat;
@end

@implementation TestCodec {
    SSBBFEFeedFormat _feedFormat;
    SSBBFEMessageFormat _messageFormat;
}

- (instancetype)initWithFeedFormat:(SSBBFEFeedFormat)feedFormat
                     messageFormat:(SSBBFEMessageFormat)messageFormat {
    self = [super init];
    if (self) {
        _feedFormat = feedFormat;
        _messageFormat = messageFormat;
    }
    return self;
}

- (SSBBFEFeedFormat)feedFormat { return _feedFormat; }
- (SSBBFEMessageFormat)messageFormat { return _messageFormat; }

- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error {
    return NO;
}

- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error {
    return nil;
}

@end

@interface SSBFeedCodecRegistryTests : XCTestCase
@end

@implementation SSBFeedCodecRegistryTests

#pragma mark - Singleton

- (void)testSharedRegistry_returnsSameInstance {
    SSBFeedCodecRegistry *r1 = [SSBFeedCodecRegistry sharedRegistry];
    SSBFeedCodecRegistry *r2 = [SSBFeedCodecRegistry sharedRegistry];
    XCTAssertEqual(r1, r2);
}

- (void)testSharedRegistry_isNotNil {
    XCTAssertNotNil([SSBFeedCodecRegistry sharedRegistry]);
}

#pragma mark - registerCodec: / codecForFeedFormat:

- (void)testRegisterAndLookup_returnsRegisteredCodec {
    // Use a high format value unlikely to clash with real codecs
    SSBBFEFeedFormat testFormat = (SSBBFEFeedFormat)99;
    TestCodec *codec = [[TestCodec alloc] initWithFeedFormat:testFormat
                                               messageFormat:SSBBFEMessageFormatClassic];
    SSBFeedCodecRegistry *registry = [SSBFeedCodecRegistry sharedRegistry];
    [registry registerCodec:codec];

    id<SSBFeedCodec> retrieved = [registry codecForFeedFormat:testFormat];
    XCTAssertEqual(retrieved, codec);
}

- (void)testLookup_unknownFormat_returnsNil {
    SSBBFEFeedFormat unknownFormat = (SSBBFEFeedFormat)200;
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry] codecForFeedFormat:unknownFormat];
    XCTAssertNil(codec);
}

- (void)testRegister_replacesExistingCodec {
    SSBBFEFeedFormat testFormat = (SSBBFEFeedFormat)98;

    TestCodec *first  = [[TestCodec alloc] initWithFeedFormat:testFormat
                                                messageFormat:SSBBFEMessageFormatClassic];
    TestCodec *second = [[TestCodec alloc] initWithFeedFormat:testFormat
                                                messageFormat:SSBBFEMessageFormatBendybuttV1];

    SSBFeedCodecRegistry *registry = [SSBFeedCodecRegistry sharedRegistry];
    [registry registerCodec:first];
    [registry registerCodec:second];

    id<SSBFeedCodec> retrieved = [registry codecForFeedFormat:testFormat];
    XCTAssertEqual(retrieved, second);
}

- (void)testRegister_differentFormats_storedSeparately {
    SSBBFEFeedFormat formatA = (SSBBFEFeedFormat)96;
    SSBBFEFeedFormat formatB = (SSBBFEFeedFormat)97;

    TestCodec *codecA = [[TestCodec alloc] initWithFeedFormat:formatA
                                                messageFormat:SSBBFEMessageFormatClassic];
    TestCodec *codecB = [[TestCodec alloc] initWithFeedFormat:formatB
                                                messageFormat:SSBBFEMessageFormatBendybuttV1];

    SSBFeedCodecRegistry *registry = [SSBFeedCodecRegistry sharedRegistry];
    [registry registerCodec:codecA];
    [registry registerCodec:codecB];

    XCTAssertEqual([registry codecForFeedFormat:formatA], codecA);
    XCTAssertEqual([registry codecForFeedFormat:formatB], codecB);
}

#pragma mark - Self-Registered Codecs (via +load)

- (void)testGabbyGroveCodec_isRegistered {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatGabbygroveV1];
    XCTAssertNotNil(codec, @"GabbyGrove codec should be registered via +load");
    XCTAssertEqual(codec.feedFormat, SSBBFEFeedFormatGabbygroveV1);
}

- (void)testGabbyGroveCodec_isCorrectClass {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatGabbygroveV1];
    XCTAssertTrue([codec isKindOfClass:[SSBGabbyGrove class]]);
}

- (void)testButtwooCodec_isRegistered {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatButtwooV1];
    XCTAssertNotNil(codec, @"Buttwoo codec should be registered via +load");
    XCTAssertEqual(codec.feedFormat, SSBBFEFeedFormatButtwooV1);
}

- (void)testButtwooCodec_isCorrectClass {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatButtwooV1];
    XCTAssertTrue([codec isKindOfClass:[SSBButtwoo class]]);
}

- (void)testBambooCodec_isRegistered {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatBamboo];
    XCTAssertNotNil(codec, @"Bamboo codec should be registered via +load");
    XCTAssertEqual(codec.feedFormat, SSBBFEFeedFormatBamboo);
}

- (void)testBambooCodec_isCorrectClass {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatBamboo];
    XCTAssertTrue([codec isKindOfClass:[SSBBamboo class]]);
}

- (void)testBendyButtCodec_isRegistered {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatBendybuttV1];
    XCTAssertNotNil(codec, @"BendyButt codec should be registered via +load");
    XCTAssertEqual(codec.feedFormat, SSBBFEFeedFormatBendybuttV1);
}

#pragma mark - Thread Safety

- (void)testConcurrentRegistrationAndLookup {
    SSBFeedCodecRegistry *registry = [SSBFeedCodecRegistry sharedRegistry];
    SSBBFEFeedFormat testFormat = (SSBBFEFeedFormat)95;
    TestCodec *codec = [[TestCodec alloc] initWithFeedFormat:testFormat
                                               messageFormat:SSBBFEMessageFormatClassic];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    // Register concurrently from multiple threads
    for (int i = 0; i < 10; i++) {
        dispatch_group_async(group, queue, ^{
            [registry registerCodec:codec];
        });
    }

    // Lookup concurrently from multiple threads
    for (int i = 0; i < 10; i++) {
        dispatch_group_async(group, queue, ^{
            id<SSBFeedCodec> retrieved = [registry codecForFeedFormat:testFormat];
            // Either nil (if registration hasn't happened yet) or the test codec
            if (retrieved != nil) {
                XCTAssertEqual(retrieved, codec);
            }
        });
    }

    // Wait up to 5 seconds for all operations to complete
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));

    // After all operations, the codec should be registered
    id<SSBFeedCodec> final = [registry codecForFeedFormat:testFormat];
    XCTAssertEqual(final, codec);
}

#pragma mark - Codec Properties Consistency

- (void)testGabbyGrove_feedFormatAndMessageFormatConsistent {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatGabbygroveV1];
    XCTAssertEqual(codec.messageFormat, SSBBFEMessageFormatGabbygroveV1);
}

- (void)testButtwoo_feedFormatAndMessageFormatConsistent {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatButtwooV1];
    XCTAssertEqual(codec.messageFormat, SSBBFEMessageFormatButtwooV1);
}

- (void)testBamboo_feedFormatAndMessageFormatConsistent {
    id<SSBFeedCodec> codec = [[SSBFeedCodecRegistry sharedRegistry]
                               codecForFeedFormat:SSBBFEFeedFormatBamboo];
    XCTAssertEqual(codec.messageFormat, SSBBFEMessageFormatBamboo);
}

@end
