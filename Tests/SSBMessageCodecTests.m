#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBMessageCodec.h>

@interface SSBMessageCodecTests : XCTestCase
@end

@implementation SSBMessageCodecTests

- (void)testContactContentWithTarget {
    NSString *targetPubKey = @"testPubKey123";
    
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:targetPubKey following:YES];
    
    XCTAssertNotNil(content, @"Contact content should not be nil");
    XCTAssertEqualObjects(content[@"type"], @"contact", @"Type should be 'contact'");
    XCTAssertEqualObjects(content[@"contact"], targetPubKey, @"Contact should match target");
    XCTAssertEqualObjects(content[@"following"], @YES, @"Following should be YES");
}

- (void)testContactContentUnfollow {
    NSString *targetPubKey = @"testPubKey456";
    
    NSDictionary *content = [SSBMessageCodec contactContentWithTarget:targetPubKey following:NO];
    
    XCTAssertNotNil(content, @"Contact content should not be nil");
    XCTAssertEqualObjects(content[@"following"], @NO, @"Following should be NO");
}

- (void)testPostContentWithText {
    NSString *testText = @"Hello, World!";
    
    NSDictionary *content = [SSBMessageCodec postContentWithText:testText];
    
    XCTAssertNotNil(content, @"Post content should not be nil");
    XCTAssertEqualObjects(content[@"type"], @"post", @"Type should be 'post'");
    XCTAssertEqualObjects(content[@"text"], testText, @"Text should match");
}

- (void)testAboutContentForFeed {
    NSString *author = @"testAuthor789";
    NSString *name = @"Test User";
    NSString *descriptionText = @"A test user description";
    
    NSDictionary *content = [SSBMessageCodec aboutContentForFeed:author name:name description:descriptionText];
    
    XCTAssertNotNil(content, @"About content should not be nil");
    XCTAssertEqualObjects(content[@"type"], @"about", @"Type should be 'about'");
    XCTAssertEqualObjects(content[@"about"], author, @"About should match author");
    XCTAssertEqualObjects(content[@"name"], name, @"Name should match");
    XCTAssertEqualObjects(content[@"description"], descriptionText, @"Description should match");
}

- (void)testAboutContentNameOnly {
    NSString *author = @"testAuthorABC";
    NSString *name = @"Only Name";
    
    NSDictionary *content = [SSBMessageCodec aboutContentForFeed:author name:name description:nil];
    
    XCTAssertNotNil(content, @"About content should not be nil");
    XCTAssertEqualObjects(content[@"name"], name, @"Name should match");
    XCTAssertNil(content[@"description"], @"Description should be nil");
}

- (void)testVerifyMessage {
    NSDictionary *validMessage = @{
        @"key": @"%testKey123",
        @"value": @{
            @"author": @"@testAuthor.ed25519",
            @"sequence": @1,
            @"content": @{
                @"type": @"post",
                @"text": @"Test"
            },
            @"signature": @"invalidButPresent"
        }
    };
    
    BOOL isValid = [SSBMessageCodec verifyMessage:validMessage[@"value"]];
    XCTAssertFalse(isValid, @"Message with invalid signature should fail verification");
}

@end
