#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBIndexFeed.h>
#import <SSBNetwork/SSBMetafeed.h>
#import <SSBNetwork/SSBBFE.h>

@interface SSBMetafeedKeys (Test)
- (instancetype)initWithPublicKey:(NSData *)publicKey secretKey:(NSData *)secretKey;
@end

@interface SSBIndexFeedTests : XCTestCase
@end

@implementation SSBIndexFeedTests

#pragma mark - SSBFeedCodec Protocol

- (void)testFeedFormat {
    SSBIndexFeed *codec = [SSBIndexFeed sharedCodec];
    XCTAssertEqual([codec feedFormat], SSBBFEFeedFormatIndexedV1);
    XCTAssertEqual([codec messageFormat], SSBBFEMessageFormatIndexedV1);
}

- (void)testVerifyMessageData_invalidJSON {
    SSBIndexFeed *codec = [SSBIndexFeed sharedCodec];
    NSData *badData = [@"{" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL valid = [codec verifyMessageData:badData error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

- (void)testComputeMessageKeyFromData {
    SSBIndexFeed *codec = [SSBIndexFeed sharedCodec];
    NSData *data = [@"test message" dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    NSData *key = [codec computeMessageKeyFromData:data error:&error];
    XCTAssertNotNil(key);
    XCTAssertNil(error);
    XCTAssertEqual(key.length, 32); // SHA-256
    
    // Empty data error
    NSData *empty = [NSData data];
    NSData *nullKey = [codec computeMessageKeyFromData:empty error:&error];
    XCTAssertNil(nullKey);
    XCTAssertNotNil(error);
}

#pragma mark - Index Feed API - URIs

- (void)testIndexFeedBFEIdentifier {
    XCTAssertEqualObjects([SSBIndexFeed indexFeedBFEIdentifier], @"indexed-v1");
    XCTAssertEqualObjects([SSBIndexFeed queryLanguageIdentifier], @"ssb-ql-0");
}

- (void)testCreateURI {
    XCTAssertEqualObjects([SSBIndexFeed createIndexFeedURIForFeedID:@"def"], @"ssb:feed/indexed-v1/def");
    XCTAssertEqualObjects([SSBIndexFeed createIndexMessageURIForMessageID:@"ghi"], @"ssb:message/indexed-v1/ghi");
    
    XCTAssertNil([SSBIndexFeed createIndexFeedURIForFeedID:@""]);
    XCTAssertNil([SSBIndexFeed createIndexMessageURIForMessageID:nil]);
}

#pragma mark - Index Feed API - Messages

- (void)testCreateIndexMessageWithKey {
    NSDictionary *msg = [SSBIndexFeed createIndexMessageWithKey:@"%abc.sha256" sequence:5];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed/index");
    XCTAssertEqualObjects(msg[@"indexed"][@"key"], @"%abc.sha256");
    XCTAssertEqualObjects(msg[@"indexed"][@"sequence"], @(5));
    
    XCTAssertNil([SSBIndexFeed createIndexMessageWithKey:nil sequence:5]);
    XCTAssertNil([SSBIndexFeed createIndexMessageWithKey:@"%abc" sequence:0]);
}

- (void)testParseIndexMessage {
    NSDictionary *content = @{
        @"type": @"metafeed/index",
        @"indexed": @{
            @"key": @"%abc.sha256",
            @"sequence": @(10)
        }
    };
    NSDictionary *parsed = [SSBIndexFeed parseIndexMessage:content];
    XCTAssertNotNil(parsed);
    XCTAssertEqualObjects(parsed[@"key"], @"%abc.sha256");
    XCTAssertEqualObjects(parsed[@"sequence"], @(10));
    
    // Invalid type
    XCTAssertNil([SSBIndexFeed parseIndexMessage:@{@"type": @"other"}]);
    // Missing fields
    NSDictionary *invalidContent = @{@"type": @"metafeed/index", @"indexed": @{}};
    XCTAssertNil([SSBIndexFeed parseIndexMessage:invalidContent]);
    XCTAssertNil([SSBIndexFeed parseIndexMessage:nil]);
}

#pragma mark - Index Feed API - Queries

- (void)testCreateQueryWithAuthor {
    NSDictionary *q1 = [SSBIndexFeed createQueryWithAuthor:@"@alice" messageType:@"post" isPrivate:NO];
    XCTAssertEqualObjects(q1[@"author"], @"@alice");
    XCTAssertEqualObjects(q1[@"type"], @"post");
    XCTAssertEqualObjects(q1[@"private"], @(NO));
    
    NSDictionary *q2 = [SSBIndexFeed createQueryWithAuthor:@"@bob" messageType:@"post" isPrivate:YES];
    XCTAssertEqualObjects(q2[@"author"], @"@bob");
    XCTAssertEqualObjects(q2[@"type"], [NSNull null]); // private implies type null
    XCTAssertEqualObjects(q2[@"private"], @(YES));
}

- (void)testQueryConvenienceCreators {
    XCTAssertEqualObjects([SSBIndexFeed createContactIndexQueryForAuthor:@"@a"][@"type"], @"contact");
    XCTAssertEqualObjects([SSBIndexFeed createAboutIndexQueryForAuthor:@"@a"][@"type"], @"about");
    XCTAssertEqualObjects([SSBIndexFeed createPostsIndexQueryForAuthor:@"@a" channel:nil][@"type"], @"post");
    
    XCTAssertEqualObjects([SSBIndexFeed createContactIndexQuery][@"type"], @"contact");
    XCTAssertEqualObjects([SSBIndexFeed createAboutIndexQuery][@"type"], @"about");
    XCTAssertEqualObjects([SSBIndexFeed createPostsIndexQuery][@"type"], @"post");
}

#pragma mark - Index Feed API - Derived / Existing

- (void)testCreateAddDerivedMessage {
    NSDictionary *query = @{@"type": @"post"};
    uint8_t dummyKey[32] = {0};
    NSData *pub = [NSData dataWithBytes:dummyKey length:32];
    SSBMetafeedKeys *keys = [[SSBMetafeedKeys alloc] initWithPublicKey:pub secretKey:pub];
    
    NSDictionary *msg = [SSBIndexFeed createAddDerivedMessageForIndexFeed:@"@feed"
                                                               feedPurpose:@"index"
                                                                     query:query
                                                                  metafeedID:@"@meta"
                                                                   feedKeys:keys];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed/add/derived");
    XCTAssertEqualObjects(msg[@"feedpurpose"], @"index");
    XCTAssertEqualObjects(msg[@"subfeed"], @"@feed");
    XCTAssertEqualObjects(msg[@"querylang"], @"ssb-ql-0");
    
    XCTAssertNil([SSBIndexFeed createAddDerivedMessageForIndexFeed:nil feedPurpose:@"index" query:query metafeedID:@"@meta" feedKeys:keys]);
}

- (void)testAddExistingMessageForIndexFeed {
    uint8_t dummyKey[32] = {0};
    NSData *pub = [NSData dataWithBytes:dummyKey length:32];
    SSBMetafeedKeys *keys = [[SSBMetafeedKeys alloc] initWithPublicKey:pub secretKey:pub];
    
    NSDictionary *msg = [SSBIndexFeed addExistingMessageForIndexFeed:@"@indexfeed" metafeedID:@"@meta" feedKeys:keys];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed");
    XCTAssertEqualObjects(msg[@"metafeedType"], @"add/existing");
    XCTAssertEqualObjects(msg[@"feed"], @"@indexfeed");
}

#pragma mark - Index Feed API - BFE / ID Helpers

- (void)testIndexedIDHelpers {
    uint8_t dummyKey[32] = {1};
    NSData *pub = [NSData dataWithBytes:dummyKey length:32];
    
    NSString *feedId = [SSBIndexFeed indexedFeedIDFromPublicKey:pub];
    XCTAssertNotNil(feedId);
    
    NSData *parsedPub = [SSBIndexFeed publicKeyFromIndexedFeedID:feedId];
    XCTAssertEqualObjects(parsedPub, pub);
    
    XCTAssertNil([SSBIndexFeed indexedFeedIDFromPublicKey:[NSData data]]);
    XCTAssertNil([SSBIndexFeed publicKeyFromIndexedFeedID:@"@invalid"]);
}

- (void)testMessageIDHelpers {
    NSString *msgId = @"%AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    NSString *indexedId = [SSBIndexFeed indexedMessageIDFromMessageID:msgId];
    XCTAssertNotNil(indexedId);
    
    NSString *parsedId = [SSBIndexFeed messageIDFromIndexedMessageID:indexedId];
    XCTAssertEqualObjects(parsedId, msgId);
    
    XCTAssertNil([SSBIndexFeed indexedMessageIDFromMessageID:@"%invalid"]);
}

- (void)testQueryConvenienceBuilders {
    NSDictionary *q1 = [SSBIndexFeed createGenericIndexQueryWithAuthor:@"@author" messageType:@"post" channel:@"main"];
    XCTAssertNotNil(q1);
    
    NSDictionary *q2 = [SSBIndexFeed createQueryWithAuthor:@"@author" messageType:@"post" channel:@"main"];
    XCTAssertNotNil(q2);
    
    NSDictionary *q3 = [SSBIndexFeed createContactIndexQueryForAuthor:@"@author"];
    XCTAssertNotNil(q3);
    
    NSDictionary *q4 = [SSBIndexFeed createAboutIndexQueryForAuthor:@"@author"];
    XCTAssertNotNil(q4);
    
    NSDictionary *q5 = [SSBIndexFeed createPostsIndexQueryForAuthor:@"@author" channel:@"main"];
    XCTAssertNotNil(q5);
    
    NSDictionary *q6 = [SSBIndexFeed createContactIndexQuery];
    XCTAssertNotNil(q6);
    
    NSDictionary *q7 = [SSBIndexFeed createAboutIndexQuery];
    XCTAssertNotNil(q7);
    
    NSDictionary *q8 = [SSBIndexFeed createPostsIndexQuery];
    XCTAssertNotNil(q8);
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSData *nonce = [SSBIndexFeed performSelector:@selector(generateNonce)];
#pragma clang diagnostic pop
    XCTAssertNotNil(nonce);
    XCTAssertEqual(nonce.length, 32);
}

- (void)testVerifyMessageData {
    SSBIndexFeed *feed = [SSBIndexFeed sharedCodec];
    
    XCTAssertNotNil(feed);
    
    // Test non-JSON data
    NSData *badJson = [@"%invalid json" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL valid = [feed verifyMessageData:badJson error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    
    // Test invalid signature dictionary
    NSDictionary *msg = @{@"type": @"post", @"signature": @"bad"};
    NSData *msgData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    valid = [feed verifyMessageData:msgData error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

#pragma mark - Index Feed API - Misc

- (void)testIndexTypeFromQuery {
    XCTAssertEqual([SSBIndexFeed indexTypeFromQuery:@{@"type": @"contact"}], SSBIndexFeedTypeContacts);
    XCTAssertEqual([SSBIndexFeed indexTypeFromQuery:@{@"type": @"about"}], SSBIndexFeedTypeAbouts);
    XCTAssertEqual([SSBIndexFeed indexTypeFromQuery:@{@"type": @"post"}], SSBIndexFeedTypePosts);
    XCTAssertEqual([SSBIndexFeed indexTypeFromQuery:@{@"type": @"custom"}], SSBIndexFeedTypeCustom);
    XCTAssertEqual([SSBIndexFeed indexTypeFromQuery:nil], SSBIndexFeedTypeCustom);
}

- (void)testCreateIndexFeedForQuery {
    NSDictionary *query = @{@"type": @"post"};
    uint8_t dummyKey[32] = {0};
    NSData *pub = [NSData dataWithBytes:dummyKey length:32];
    SSBMetafeedKeys *keys = [[SSBMetafeedKeys alloc] initWithPublicKey:pub secretKey:pub];
    
    NSDictionary *msg = [SSBIndexFeed createIndexFeedForQuery:query feedPurpose:@"index" metafeedID:@"@meta.ed25519" feedKeys:keys];
    XCTAssertNotNil(msg);
    XCTAssertEqualObjects(msg[@"type"], @"metafeed/add/derived");
}

@end
