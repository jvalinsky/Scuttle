#import <XCTest/XCTest.h>
#import "SRMarkdownParser.h"

// Expose private class methods for testing
@interface SRMarkdownParser (Testing)
+ (NSFont *)italicFontOfSize:(CGFloat)size;
@end

@interface SRMarkdownParserTests : XCTestCase
@end

@implementation SRMarkdownParserTests

#pragma mark - attributedStringFromMarkdown: edge cases

- (void)testEmptyInput_returnsEmptyAttributedString {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@""];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, 0U);
}

- (void)testPlainText_preservesContent {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"Hello world"];
    XCTAssertEqualObjects(result.string, @"Hello world");
}

- (void)testBold_appliesBoldFont {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"**bold**"];
    XCTAssertEqualObjects(result.string, @"**bold**");
    // The inner "bold" range should have a bold font
    NSRange captureRange = NSMakeRange(2, 4); // "bold"
    NSFont *font = [result attribute:NSFontAttributeName atIndex:captureRange.location effectiveRange:nil];
    XCTAssertNotNil(font);
    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
    XCTAssertTrue((traits & NSBoldFontMask) != 0, @"Bold text should have bold font trait");
}

- (void)testItalic_appliesItalicFont {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"*italic*"];
    XCTAssertEqualObjects(result.string, @"*italic*");
    NSRange captureRange = NSMakeRange(1, 6); // "italic"
    NSFont *font = [result attribute:NSFontAttributeName atIndex:captureRange.location effectiveRange:nil];
    XCTAssertNotNil(font);
    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
    XCTAssertTrue((traits & NSItalicFontMask) != 0, @"Italic text should have italic font trait");
}

- (void)testLink_http_appliesLinkAttribute {
    NSString *url = @"http://example.com";
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:url];
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertNotNil(link, @"HTTP URLs should get link attribute");
}

- (void)testLink_https_appliesLinkAttribute {
    NSString *url = @"https://example.com/path?q=1";
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:url];
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertNotNil(link, @"HTTPS URLs should get link attribute");
}

- (void)testLink_appliesUnderline {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"https://example.com"];
    NSNumber *underline = [result attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertEqualObjects(underline, @(NSUnderlineStyleSingle));
}

- (void)testMention_ed25519_appliesLinkAttribute {
    NSString *text = @"@LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=.ed25519";
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:text];
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertNotNil(link, @"SSB mentions should get a link attribute");
    XCTAssertTrue([[link absoluteString] hasPrefix:@"ssb://profile/"], @"Mention link should use ssb://profile/ scheme");
}

- (void)testMention_shortName_appliesLinkAttribute {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"@alice"];
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertNotNil(link);
}

- (void)testChannel_appliesLinkAttribute {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"#ssb"];
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertNotNil(link, @"Channel references should get a link attribute");
    XCTAssertTrue([[link absoluteString] hasPrefix:@"ssb://channel/"], @"Channel link should use ssb://channel/ scheme");
}

- (void)testChannel_appliesUnderline {
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"#ssb"];
    NSNumber *underline = [result attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertEqualObjects(underline, @(NSUnderlineStyleSingle));
}

- (void)testMixedContent_allPatternsApplied {
    NSString *text = @"Hello **world** https://example.com #ssb";
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:text];
    XCTAssertEqualObjects(result.string, text);
    // "world" at index 8 should be bold
    NSFont *boldFont = [result attribute:NSFontAttributeName atIndex:8 effectiveRange:nil];
    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:boldFont];
    XCTAssertTrue((traits & NSBoldFontMask) != 0);
    // URL at index 17 should have a link
    NSURL *link = [result attribute:NSLinkAttributeName atIndex:17 effectiveRange:nil];
    XCTAssertNotNil(link);
}

- (void)testAttributedStringFromMarkdown_withLinkColor {
    NSColor *customColor = [NSColor redColor];
    NSAttributedString *result = [SRMarkdownParser attributedStringFromMarkdown:@"https://example.com" linkColor:customColor];
    NSColor *fg = [result attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil];
    XCTAssertEqualObjects(fg, customColor);
}

#pragma mark - italicFontOfSize:

- (void)testItalicFontOfSize_returnsFont {
    NSFont *font = [SRMarkdownParser italicFontOfSize:13];
    XCTAssertNotNil(font);
    XCTAssertEqualWithAccuracy(font.pointSize, 13.0, 0.01);
}

@end
