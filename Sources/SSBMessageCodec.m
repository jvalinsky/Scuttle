#import "SSBMessageCodec.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

@interface SSBChannel : NSObject
@property (nonatomic, copy) NSString *name;
+ (nullable instancetype)channelWithName:(NSString *)name;
+ (NSString *)normalize:(NSString *)name;
@end

@interface SSBMention : NSObject
@property (nonatomic, copy, nullable) NSString *feedId;
@property (nonatomic, copy, nullable) NSString *messageId;
@property (nonatomic, copy, nullable) NSString *blobId;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, assign) NSUInteger blobSize;
@end

static os_log_t codecLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.scuttlebutt.room", "Codec");
    });
    return log;
}

@implementation SSBMessageCodec

#pragma mark - JSON Encoding Helpers

+ (NSString *)jsonStringLiteral:(NSString *)str {
    if (!str) return @"null";
    NSMutableString *result = [NSMutableString stringWithString:@"\""];
    NSUInteger len = str.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [str characterAtIndex:i];
        switch (c) {
            case '"':  [result appendString:@"\\\""]; break;
            case '\\': [result appendString:@"\\\\"]; break;
            case '\b': [result appendString:@"\\b"];  break;
            case '\f': [result appendString:@"\\f"];  break;
            case '\n': [result appendString:@"\\n"];  break;
            case '\r': [result appendString:@"\\r"];  break;
            case '\t': [result appendString:@"\\t"];  break;
            default:
                if (c < 0x20) {
                    [result appendFormat:@"\\u%04x", c];
                } else {
                    [result appendFormat:@"%C", c];
                }
                break;
        }
    }
    [result appendString:@"\""];
    return result;
}

+ (NSString *)indentString:(int)indent {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [s appendString:@"  "];
    }
    return s;
}

+ (NSString *)jsonEncodeObject:(id)obj indent:(int)indent {
    if (!obj || [obj isEqual:[NSNull null]]) {
        return @"null";
    }

    if ([obj isKindOfClass:[NSString class]]) {
        return [self jsonStringLiteral:obj];
    }

    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)obj;
        if (strcmp([num objCType], @encode(BOOL)) == 0 ||
            strcmp([num objCType], @encode(char)) == 0) {
            // Distinguish booleans: check against known boolean singletons
            if ([num isEqual:@YES]) return @"true";
            if ([num isEqual:@NO]) return @"false";
        }
        // Integer check: no decimal point for integer values
        if (strcmp([num objCType], @encode(int)) == 0 ||
            strcmp([num objCType], @encode(long)) == 0 ||
            strcmp([num objCType], @encode(long long)) == 0 ||
            strcmp([num objCType], @encode(NSInteger)) == 0 ||
            strcmp([num objCType], @encode(short)) == 0 ||
            strcmp([num objCType], @encode(unsigned int)) == 0 ||
            strcmp([num objCType], @encode(unsigned long)) == 0 ||
            strcmp([num objCType], @encode(unsigned long long)) == 0) {
            return [NSString stringWithFormat:@"%lld", [num longLongValue]];
        }
        // Floating point
        return [NSString stringWithFormat:@"%g", [num doubleValue]];
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        if (arr.count == 0) return @"[]";

        NSMutableString *result = [NSMutableString stringWithString:@"[\n"];
        NSString *childIndent = [self indentString:indent + 1];
        NSString *closeIndent = [self indentString:indent];

        for (NSUInteger i = 0; i < arr.count; i++) {
            [result appendFormat:@"%@%@", childIndent, [self jsonEncodeObject:arr[i] indent:indent + 1]];
            if (i < arr.count - 1) {
                [result appendString:@","];
            }
            [result appendString:@"\n"];
        }
        [result appendFormat:@"%@]", closeIndent];
        return result;
    }

    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        if (dict.count == 0) return @"{}";

        NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableString *result = [NSMutableString stringWithString:@"{\n"];
        NSString *childIndent = [self indentString:indent + 1];
        NSString *closeIndent = [self indentString:indent];

        for (NSUInteger i = 0; i < sortedKeys.count; i++) {
            NSString *key = sortedKeys[i];
            id val = dict[key];
            [result appendFormat:@"%@%@: %@", childIndent, [self jsonStringLiteral:key], [self jsonEncodeObject:val indent:indent + 1]];
            if (i < sortedKeys.count - 1) {
                [result appendString:@","];
            }
            [result appendString:@"\n"];
        }
        [result appendFormat:@"%@}", closeIndent];
        return result;
    }

    // Fallback: use description
    return [self jsonStringLiteral:[obj description]];
}

#pragma mark - Legacy Encoding

+ (nullable NSData *)encodeLegacyValue:(NSDictionary *)value includeSignature:(BOOL)includeSig {
    NSMutableString *json = [NSMutableString string];
    [json appendString:@"{\n"];

    // previous
    id prev = value[@"previous"];
    if (!prev || [prev isEqual:[NSNull null]]) {
        [json appendString:@"  \"previous\": null,\n"];
    } else {
        [json appendFormat:@"  \"previous\": %@,\n", [self jsonStringLiteral:prev]];
    }

    // author
    [json appendFormat:@"  \"author\": %@,\n", [self jsonStringLiteral:value[@"author"]]];

    // sequence
    [json appendFormat:@"  \"sequence\": %ld,\n", (long)[value[@"sequence"] integerValue]];

    // timestamp
    [json appendFormat:@"  \"timestamp\": %lld,\n", [value[@"timestamp"] longLongValue]];

    // hash
    [json appendFormat:@"  \"hash\": %@,\n", [self jsonStringLiteral:value[@"hash"]]];

    // content
    [json appendFormat:@"  \"content\": %@", [self jsonEncodeObject:value[@"content"] indent:1]];

    if (includeSig) {
        [json appendString:@",\n"];
        [json appendFormat:@"  \"signature\": %@\n", [self jsonStringLiteral:value[@"signature"]]];
    } else {
        [json appendString:@"\n"];
    }

    [json appendString:@"}"];

    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Signing

+ (nullable NSDictionary *)createSignedMessageWithContent:(NSDictionary *)content
                                                   author:(NSString *)author
                                                 sequence:(NSInteger)sequence
                                              previousKey:(nullable NSString *)previousKey
                                                secretKey:(NSData *)secretKey {
    if (secretKey.length != crypto_sign_ed25519_SECRETKEYBYTES) {
        os_log_error(codecLog(), "Invalid secret key length: %zu (expected %d)",
                     secretKey.length, crypto_sign_ed25519_SECRETKEYBYTES);
        return nil;
    }

    NSDictionary *unsignedValue = @{
        @"previous": previousKey ?: [NSNull null],
        @"author": author,
        @"sequence": @(sequence),
        @"timestamp": @((int64_t)([[NSDate date] timeIntervalSince1970] * 1000)),
        @"hash": @"sha256",
        @"content": content
    };

    NSData *unsignedBytes = [self encodeLegacyValue:unsignedValue includeSignature:NO];
    if (!unsignedBytes) {
        os_log_error(codecLog(), "Failed to encode unsigned message value");
        return nil;
    }

    unsigned long long smlen = 0;
    NSUInteger msgLen = unsignedBytes.length;
    unsigned char *sm = malloc(crypto_sign_ed25519_BYTES + msgLen);
    if (!sm) return nil;

    int ret = crypto_sign_ed25519(sm, &smlen,
                                  unsignedBytes.bytes, msgLen,
                                  secretKey.bytes);
    if (ret != 0) {
        os_log_error(codecLog(), "crypto_sign_ed25519 failed");
        free(sm);
        return nil;
    }

    NSData *sig = [NSData dataWithBytes:sm length:crypto_sign_ed25519_BYTES];
    free(sm);

    NSString *sigStr = [NSString stringWithFormat:@"%@.sig.ed25519",
                        [sig base64EncodedStringWithOptions:0]];

    NSMutableDictionary *signedValue = [unsignedValue mutableCopy];
    signedValue[@"signature"] = sigStr;

    os_log_debug(codecLog(), "Signed message seq %ld for %{public}@", (long)sequence, author);
    return signedValue;
}

#pragma mark - Key Computation

+ (nullable NSString *)computeMessageKey:(NSDictionary *)signedValue {
    NSData *bytes = [self encodeLegacyValue:signedValue includeSignature:YES];
    if (!bytes) return nil;

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);

    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return [NSString stringWithFormat:@"%%%@.sha256",
            [hashData base64EncodedStringWithOptions:0]];
}

#pragma mark - Content Warning (SIP 10)

+ (BOOL)shouldShowContentForMessage:(NSDictionary *)messageValue {
    NSString *cw = [self contentWarningForMessage:messageValue];
    return (cw == nil || cw.length == 0);
}

+ (nullable NSString *)contentWarningForMessage:(NSDictionary *)messageValue {
    NSDictionary *content = messageValue[@"content"];
    if ([content isKindOfClass:[NSDictionary class]]) {
        return content[@"contentWarning"];
    }
    return nil;
}

#pragma mark - Verification

+ (BOOL)verifyMessage:(NSDictionary *)signedValue {
    NSString *author = signedValue[@"author"];
    if (!author || author.length < 2) return NO;

    // Strip @ prefix and .ed25519 suffix
    NSString *b64Key = [author substringFromIndex:1];
    NSRange suffixRange = [b64Key rangeOfString:@".ed25519"];
    if (suffixRange.location == NSNotFound) return NO;
    b64Key = [b64Key substringToIndex:suffixRange.location];

    NSData *pubKey = [[NSData alloc] initWithBase64EncodedString:b64Key options:0];
    if (pubKey.length != crypto_sign_ed25519_PUBLICKEYBYTES) return NO;

    // Extract signature
    NSString *sigStr = signedValue[@"signature"];
    if (!sigStr) return NO;
    NSString *sigB64 = [sigStr stringByReplacingOccurrencesOfString:@".sig.ed25519" withString:@""];
    NSData *sig = [[NSData alloc] initWithBase64EncodedString:sigB64 options:0];
    if (sig.length != crypto_sign_ed25519_BYTES) return NO;

    // Encode unsigned value
    NSData *unsignedBytes = [self encodeLegacyValue:signedValue includeSignature:NO];
    if (!unsignedBytes) return NO;

    // Construct signed message: sig(64) + message
    NSUInteger smLen = crypto_sign_ed25519_BYTES + unsignedBytes.length;
    unsigned char *sm = malloc(smLen);
    if (!sm) return NO;
    memcpy(sm, sig.bytes, crypto_sign_ed25519_BYTES);
    memcpy(sm + crypto_sign_ed25519_BYTES, unsignedBytes.bytes, unsignedBytes.length);

    unsigned char *m = malloc(smLen);
    if (!m) { free(sm); return NO; }
    unsigned long long mlen = 0;

    int ret = crypto_sign_ed25519_open(m, &mlen, sm, smLen, pubKey.bytes);
    free(sm);
    free(m);

    return ret == 0;
}

#pragma mark - Content Helpers

+ (NSDictionary *)postContentWithText:(NSString *)text {
    return @{
        @"type": @"post",
        @"text": text
    };
}

+ (NSDictionary *)postContentWithText:(NSString *)text root:(nullable NSString *)root branch:(nullable NSString *)branch {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"post";
    content[@"text"] = text;
    if (root) content[@"root"] = root;
    if (branch) content[@"branch"] = branch;
    return content;
}

+ (NSDictionary *)rootPostContentWithText:(NSString *)text
                                   channel:(nullable NSString *)channel
                            contentWarning:(nullable NSString *)contentWarning
                                 mentions:(nullable NSArray *)mentions
                                    recps:(nullable NSArray *)recps {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"post";
    content[@"text"] = text;
    if (channel) content[@"channel"] = channel;
    if (contentWarning) content[@"contentWarning"] = contentWarning;
    if (mentions) content[@"mentions"] = mentions;
    if (recps) content[@"recps"] = recps;
    return content;
}

+ (NSDictionary *)replyContentWithText:(NSString *)text
                                  root:(NSString *)root
                                branch:(id)branch
                              channel:(nullable NSString *)channel
                       contentWarning:(nullable NSString *)contentWarning
                            mentions:(nullable NSArray *)mentions
                               recps:(nullable NSArray *)recps {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"post";
    content[@"text"] = text;
    content[@"root"] = root;
    if ([branch isKindOfClass:[NSArray class]]) {
        content[@"branch"] = branch;
    } else {
        content[@"branch"] = @[branch];
    }
    if (channel) content[@"channel"] = channel;
    if (contentWarning) content[@"contentWarning"] = contentWarning;
    if (mentions) content[@"mentions"] = mentions;
    if (recps) content[@"recps"] = recps;
    return content;
}

+ (NSDictionary *)voteContentForMessage:(NSString *)messageId
                              expression:(NSString *)expression
                                   value:(int)value
                                    root:(nullable NSString *)root
                                  branch:(nullable NSArray *)branch {
    NSMutableDictionary *vote = [NSMutableDictionary dictionary];
    vote[@"link"] = messageId;
    vote[@"expression"] = expression;
    vote[@"value"] = @(value);
    
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"vote";
    content[@"vote"] = vote;
    if (root) content[@"root"] = root;
    if (branch) content[@"branch"] = branch;
    return content;
}

+ (NSDictionary *)likeVoteForMessage:(NSString *)messageId {
    return [self voteContentForMessage:messageId expression:@"heart" value:1 root:nil branch:nil];
}

+ (NSDictionary *)contactContentWithTarget:(NSString *)target following:(BOOL)following {
    return @{
        @"type": @"contact",
        @"contact": target,
        @"following": @(following)
    };
}

+ (NSDictionary *)contactContentWithTarget:(NSString *)target
                                 following:(BOOL)following
                                    blocking:(BOOL)blocking {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"contact";
    content[@"contact"] = target;
    content[@"following"] = @(following);
    if (blocking) content[@"blocking"] = @(blocking);
    return content;
}

+ (NSDictionary *)aboutContentForFeed:(NSString *)feedId name:(nullable NSString *)name description:(nullable NSString *)description {
    if (!feedId) return nil;
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"about";
    content[@"about"] = feedId;
    if (name) content[@"name"] = name;
    if (description) content[@"description"] = description;
    return content;
}

+ (NSDictionary *)aboutAvatarContentForFeed:(NSString *)feedId
                                        name:(nullable NSString *)name
                                   imageBlob:(nullable NSString *)blobId
                                 description:(nullable NSString *)description {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"type"] = @"about";
    content[@"about"] = feedId;
    if (name) content[@"name"] = name;
    if (blobId) content[@"image"] = blobId;
    if (description) content[@"description"] = description;
    return content;
}

+ (NSString *)normalizeChannelName:(NSString *)name {
    if (!name || name.length == 0) return nil;
    
    NSMutableString *normalized = [name mutableCopy];
    
    CFStringTransform((__bridge CFMutableStringRef)normalized, NULL, kCFStringTransformStripDiacritics, false);
    
    NSCharacterSet *disallowed = [NSCharacterSet characterSetWithCharactersInString:@"#,.\"!?()[] "];
    NSString *filtered = @"";
    for (NSUInteger i = 0; i < normalized.length; i++) {
        unichar c = [normalized characterAtIndex:i];
        if (![disallowed characterIsMember:c]) {
            filtered = [filtered stringByAppendingFormat:@"%C", c];
        }
    }
    
    if (filtered.length > 30) {
        filtered = [filtered substringToIndex:30];
    }
    
    return filtered.lowercaseString;
}

+ (BOOL)isValidChannelName:(NSString *)name {
    if (!name || name.length == 0 || name.length > 30) return NO;
    
    NSCharacterSet *disallowed = [NSCharacterSet characterSetWithCharactersInString:@"#,.\"!?()[] "];
    for (NSUInteger i = 0; i < name.length; i++) {
        if ([disallowed characterIsMember:[name characterAtIndex:i]]) {
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - Mention Helpers

+ (NSDictionary *)mentionForFeed:(NSString *)feedId name:(nullable NSString *)name {
    NSMutableDictionary *mention = [NSMutableDictionary dictionary];
    mention[@"link"] = feedId;
    if (name) mention[@"name"] = name;
    return mention;
}

+ (NSDictionary *)mentionForMessage:(NSString *)messageId {
    return @{@"link": messageId};
}

+ (NSDictionary *)mentionForBlob:(NSString *)blobId name:(nullable NSString *)name size:(NSUInteger)size {
    NSMutableDictionary *mention = [NSMutableDictionary dictionary];
    mention[@"link"] = blobId;
    if (name) mention[@"name"] = name;
    if (size > 0) mention[@"size"] = @(size);
    return mention;
}

#pragma mark - Message ID Validation

+ (BOOL)isValidMessageId:(NSString *)msgId {
    if (!msgId || msgId.length < 2) return NO;
    unichar sigil = [msgId characterAtIndex:0];
    if (sigil != '%') return NO;
    NSString *rest = [msgId substringFromIndex:1];
    NSRange dotRange = [rest rangeOfString:@"."];
    if (dotRange.location == NSNotFound) return NO;
    return YES;
}

+ (BOOL)isValidFeedId:(NSString *)feedId {
    if (!feedId || feedId.length < 2) return NO;
    unichar sigil = [feedId characterAtIndex:0];
    if (sigil != '@') return NO;
    NSString *rest = [feedId substringFromIndex:1];
    NSRange dotRange = [rest rangeOfString:@"."];
    if (dotRange.location == NSNotFound) return NO;
    return YES;
}

+ (BOOL)isValidBlobId:(NSString *)blobId {
    if (!blobId || blobId.length < 2) return NO;
    unichar sigil = [blobId characterAtIndex:0];
    if (sigil != '&') return NO;
    NSString *rest = [blobId substringFromIndex:1];
    NSRange dotRange = [rest rangeOfString:@"."];
    if (dotRange.location == NSNotFound) return NO;
    return YES;
}

@end
