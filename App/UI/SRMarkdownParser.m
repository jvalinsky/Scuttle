//
//  SRMarkdownParser.m
//  SSBNetwork
//
//  Simple markdown parser for SSB posts
//

#import "SRMarkdownParser.h"

@implementation SRMarkdownParser

+ (NSFont *)italicFontOfSize:(CGFloat)size {
    NSFont *font = [NSFont systemFontOfSize:size];
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *italicFont = [fontManager convertFont:font toHaveTrait:NSFontItalicTrait];
    return italicFont ?: font;
}

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)text {
    return [self attributedStringFromMarkdown:text linkColor:[NSColor linkColor]];
}

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)text linkColor:(NSColor *)linkColor {
    if (!text || text.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange fullRange = NSMakeRange(0, text.length);
    
    // Default font and color
    NSDictionary *defaultAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    [result setAttributes:defaultAttrs range:fullRange];
    
    // Bold: **text**
    [self applyPatternToAttributedString:result
                                  pattern:@"\\*\\*(.+?)\\*\\*"
                             attributeKey:NSFontAttributeName
                           attributeValue:[NSFont boldSystemFontOfSize:13]];
    
    // Italic: *text* (but not **)
    [self applyPatternToAttributedString:result
                                  pattern:@"(?<!\\*)\\*([^*]+)\\*"
                             attributeKey:NSFontAttributeName
                           attributeValue:[self italicFontOfSize:13]];
    
    // Links: http://... or https://...
    [self applyLinkPatternToAttributedString:result
                                    pattern:@"https?://[^\\s<>\"']+"
                                  linkColor:linkColor];
    
    // Mentions: @key (SSB style @pubkey.ed25519 or short @name)
    [self applyMentionPatternToAttributedString:result
                                      pattern:@"@[A-Za-z0-9+/=]+\\.ed25519|@[A-Za-z][A-Za-z0-9_-]*"
                                    linkColor:linkColor];
    
    // Channels: #channel-name
    [self applyChannelPatternToAttributedString:result
                                      pattern:@"#[A-Za-z][A-Za-z0-9_-]*"
                                    linkColor:linkColor];
    
    return result;
}

+ (void)applyPatternToAttributedString:(NSMutableAttributedString *)attrString
                               pattern:(NSString *)pattern
                          attributeKey:(NSString *)key
                        attributeValue:(id)value {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:0
                                                                          error:&error];
    if (error) return;
    
    NSString *string = attrString.string;
    NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    
    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges > 1) {
            NSRange captureRange = [match rangeAtIndex:1];
            [attrString addAttribute:key value:value range:captureRange];
        }
    }
}

+ (void)applyLinkPatternToAttributedString:(NSMutableAttributedString *)attrString
                                   pattern:(NSString *)pattern
                                 linkColor:(NSColor *)linkColor {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:0
                                                                          error:&error];
    if (error) return;
    
    NSString *string = attrString.string;
    NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSRange range = match.range;
        NSString *url = [string substringWithRange:range];
        
        [attrString addAttribute:NSForegroundColorAttributeName value:linkColor range:range];
        [attrString addAttribute:NSLinkAttributeName value:[NSURL URLWithString:url] range:range];
        [attrString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    }
}

+ (void)applyMentionPatternToAttributedString:(NSMutableAttributedString *)attrString
                                      pattern:(NSString *)pattern
                                    linkColor:(NSColor *)linkColor {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:0
                                                                          error:&error];
    if (error) return;
    
    NSString *string = attrString.string;
    NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSRange range = match.range;
        NSString *mention = [string substringWithRange:range];
        
        NSString *ssbKey = [mention substringFromIndex:1]; // Remove @
        NSURL *profileURL = [NSURL URLWithString:[NSString stringWithFormat:@"ssb://profile/%@", ssbKey]];
        
        [attrString addAttribute:NSForegroundColorAttributeName value:linkColor range:range];
        [attrString addAttribute:NSLinkAttributeName value:profileURL range:range];
        [attrString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    }
}

+ (void)applyChannelPatternToAttributedString:(NSMutableAttributedString *)attrString
                                      pattern:(NSString *)pattern
                                    linkColor:(NSColor *)linkColor {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:0
                                                                          error:&error];
    if (error) return;
    
    NSString *string = attrString.string;
    NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSRange range = match.range;
        NSString *channel = [string substringWithRange:range];
        
        NSString *channelName = [channel substringFromIndex:1]; // Remove #
        NSURL *channelURL = [NSURL URLWithString:[NSString stringWithFormat:@"ssb://channel/%@", channelName]];
        
        [attrString addAttribute:NSForegroundColorAttributeName value:linkColor range:range];
        [attrString addAttribute:NSLinkAttributeName value:channelURL range:range];
        [attrString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    }
}

@end
