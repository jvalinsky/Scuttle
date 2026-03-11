//
//  SRMarkdownParser.h
//  SSBNetwork
//
//  Simple markdown parser for SSB posts
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRMarkdownParser : NSObject

/// Parses markdown text and returns an attributed string with formatting
/// Supports: **bold**, *italic*, links, @mentions, #channels
+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)text;

/// Parse plain text and return attributed string with clickable links/mentions/channels
+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)text 
                                           linkColor:(NSColor *)linkColor;

@end

NS_ASSUME_NONNULL_END
