#import <XCTest/XCTest.h>
#import "SRFeedItem.h"
#import "SSBMessage.h"

@interface SRFeedItemTests : XCTestCase
@end

@implementation SRFeedItemTests

#pragma mark - Helper

- (SSBMessage *)messageWithContent:(NSDictionary *)content {
    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = @"%test.sha256";
    msg.author = @"@test.ed25519";
    msg.sequence = 1;
    msg.content = content;
    msg.claimedTimestamp = 1700000000000;
    return msg;
}

#pragma mark - extractBlobIDFromMessage:

- (void)testExtractBlobID_noMentionsNoText_returnsNil {
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post"}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_mentionWithImageLink_returnsBlobID {
    NSDictionary *mention = @{@"link": @"&abc123.sha256", @"type": @"image/jpeg"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&abc123.sha256");
}

- (void)testExtractBlobID_mentionWithNoType_returnsLink {
    // No type means assume image
    NSDictionary *mention = @{@"link": @"&blob456.sha256"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&blob456.sha256");
}

- (void)testExtractBlobID_mentionWithNonImageType_returnsNil {
    NSDictionary *mention = @{@"link": @"&doc.sha256", @"type": @"application/pdf"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_mentionLinkWithoutAmpersand_returnsNil {
    NSDictionary *mention = @{@"link": @"@notablob.ed25519", @"type": @"image/png"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_mentionLinkWithoutSha256Suffix_returnsNil {
    NSDictionary *mention = @{@"link": @"&abc.blake3", @"type": @"image/png"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_multipleImageMentions_returnsFirst {
    NSArray *mentions = @[
        @{@"link": @"&first.sha256", @"type": @"image/jpeg"},
        @{@"link": @"&second.sha256", @"type": @"image/png"}
    ];
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": mentions}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&first.sha256");
}

- (void)testExtractBlobID_markdownImageInText_returnsBlobID {
    NSString *text = @"Here is an image: ![alt text](&imagehash.sha256)";
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"text": text}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&imagehash.sha256");
}

- (void)testExtractBlobID_markdownImageWithEmptyAlt_returnsBlobID {
    NSString *text = @"![](&blobid.sha256)";
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"text": text}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&blobid.sha256");
}

- (void)testExtractBlobID_textWithNoImage_returnsNil {
    NSString *text = @"Just some text without any images.";
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"text": text}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_mentionsNotArray_returnsNilFromMentions {
    // mentions is a string, not an array — should skip mentions, check text
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @"invalid"}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertNil(blobID);
}

- (void)testExtractBlobID_imageTypePrefixVariants_returnsLink {
    // "image/png" starts with "image/" so should be included
    NSDictionary *mention = @{@"link": @"&img.sha256", @"type": @"image/png"};
    SSBMessage *msg = [self messageWithContent:@{@"type": @"post", @"mentions": @[mention]}];
    NSString *blobID = [SRFeedItem extractBlobIDFromMessage:msg];
    XCTAssertEqualObjects(blobID, @"&img.sha256");
}

@end
