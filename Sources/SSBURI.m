#import "SSBURI.h"

@interface SSBURI ()
@property (nonatomic, readwrite) SSBURIType type;
@property (nonatomic, readwrite) SSBURIFormat format;
@property (nonatomic, readwrite, copy, nullable) NSString *identifier;
@property (nonatomic, readwrite, copy, nullable) NSString *parentMessageId;
@property (nonatomic, readwrite, copy, nullable) NSString *multiserverAddress;
@property (nonatomic, readwrite, copy, nullable) NSDictionary<NSString *, NSString *> *queryParams;
@property (nonatomic, readwrite, copy) NSString *canonicalString;
@end

@implementation SSBURI

+ (nullable instancetype)URIWithString:(NSString *)uriString {
    if (!uriString || uriString.length == 0) {
        return nil;
    }

    // Accept legacy classic sigils directly (@feed, %msg, &blob).
    unichar prefix = [uriString characterAtIndex:0];
    if (prefix == '@' || prefix == '%' || prefix == '&') {
        SSBURI *uri = [[SSBURI alloc] init];
        uri.format = SSBURIFormatClassic;
        uri.identifier = uriString;
        uri.canonicalString = uriString;
        if (prefix == '@') {
            uri.type = SSBURITypeFeed;
        } else if (prefix == '%') {
            uri.type = SSBURITypeMessage;
        } else {
            uri.type = SSBURITypeBlob;
        }
        return uri;
    }

    if (![uriString hasPrefix:@"ssb:"]) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.canonicalString = uriString;
    
    NSString *afterScheme = [uriString substringFromIndex:4];
    if ([afterScheme hasPrefix:@"//"]) {
        afterScheme = [afterScheme substringFromIndex:2];
    }
    
    // Check for experimental
    if ([afterScheme hasPrefix:@"experimental"]) {
        uri.type = SSBURITypeExperimental;
        uri.format = SSBURIFormatUnknown;
        NSRange queryRange = [afterScheme rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            uri.queryParams = [self parseQueryParams:[afterScheme substringFromIndex:queryRange.location + 1]];
        }
        return uri;
    }
    
    // Check for multiserver address
    if ([afterScheme hasPrefix:@"address/multiserver?"] || [afterScheme hasPrefix:@"address:multiserver?"]) {
        uri.type = SSBURITypeAddress;
        uri.format = SSBURIFormatMultiserver;
        NSRange queryRange = [afterScheme rangeOfString:@"?"];
        if (queryRange.location != NSNotFound) {
            NSDictionary *params = [self parseQueryParams:[afterScheme substringFromIndex:queryRange.location + 1]];
            uri.queryParams = params;
            NSString *msAddr = params[@"multiserverAddress"];
            if (msAddr) {
                uri.multiserverAddress = [self decodeMultiserverAddress:msAddr];
            }
        }
        return uri;
    }
    
    // Parse parts separated by / or :
    NSString *pathPart = afterScheme;
    NSRange queryRange = [afterScheme rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        pathPart = [afterScheme substringToIndex:queryRange.location];
        uri.queryParams = [self parseQueryParams:[afterScheme substringFromIndex:queryRange.location + 1]];
    }

    NSArray<NSString *> *parts;
    if ([pathPart containsString:@"/"]) {
        parts = [pathPart componentsSeparatedByString:@"/"];
    } else {
        parts = [pathPart componentsSeparatedByString:@":"];
    }
    
    if (parts.count == 0 || parts[0].length == 0) {
        return nil;
    }

    uri.type = [self typeFromString:parts[0]];

    if (parts.count >= 2) {
        uri.format = [self formatFromString:parts[1]];
    }

    if (parts.count >= 3) {
        uri.identifier = parts[2];
    }

    if (parts.count >= 4) {
        uri.parentMessageId = parts[3];
    }

    return uri;
}

+ (NSDictionary<NSString *, NSString *> *)parseQueryParams:(NSString *)query {
    if (!query || query.length == 0) {
        return @{};
    }

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray<NSString *> *pairs = [query componentsSeparatedByString:@"&"];

    for (NSString *pair in pairs) {
        NSArray<NSString *> *keyValue = [pair componentsSeparatedByString:@"="];
        if (keyValue.count == 2) {
            NSString *key = keyValue[0];
            NSString *value = keyValue[1];
            value = [value stringByRemovingPercentEncoding];
            if (value) {
                params[key] = value;
            }
        } else if (keyValue.count == 1 && [keyValue[0] length] > 0) {
            params[keyValue[0]] = @"";
        }
    }

    return [params copy];
}

+ (nullable instancetype)uriWithMessage:(NSString *)messageId format:(SSBURIFormat)format {
    if (!messageId || messageId.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeMessage;
    uri.format = format;
    uri.identifier = messageId;

    NSString *formatStr = [self formatToString:format];
    uri.canonicalString = [NSString stringWithFormat:@"ssb:message/%@/%@", formatStr, messageId];

    return uri;
}

+ (nullable instancetype)uriWithFeed:(NSString *)feedId format:(SSBURIFormat)format {
    return [self uriWithFeed:feedId parentMessageId:nil format:format];
}

+ (nullable instancetype)uriWithFeed:(NSString *)feedId parentMessageId:(nullable NSString *)parentMsgId format:(SSBURIFormat)format {
    if (!feedId || feedId.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeFeed;
    uri.format = format;
    uri.identifier = feedId;
    uri.parentMessageId = parentMsgId;

    NSString *formatStr = [self formatToString:format];
    if (parentMsgId && parentMsgId.length > 0) {
        uri.canonicalString = [NSString stringWithFormat:@"ssb:feed/%@/%@/%@", formatStr, feedId, parentMsgId];
    } else {
        uri.canonicalString = [NSString stringWithFormat:@"ssb:feed/%@/%@", formatStr, feedId];
    }

    return uri;
}

+ (nullable instancetype)uriWithBlob:(NSString *)blobId format:(SSBURIFormat)format {
    if (!blobId || blobId.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeBlob;
    uri.format = format;
    uri.identifier = blobId;

    NSString *formatStr = [self formatToString:format];
    uri.canonicalString = [NSString stringWithFormat:@"ssb:blob/%@/%@", formatStr, blobId];

    return uri;
}

+ (nullable instancetype)uriWithEncryptionKey:(NSString *)key format:(SSBURIFormat)format {
    if (!key || key.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeEncryptionKey;
    uri.format = format;
    uri.identifier = key;

    NSString *formatStr = [self formatToString:format];
    uri.canonicalString = [NSString stringWithFormat:@"ssb:encryption-key/%@/%@", formatStr, key];

    return uri;
}

+ (nullable instancetype)uriWithIdentity:(NSString *)key format:(SSBURIFormat)format {
    if (!key || key.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeIdentity;
    uri.format = format;
    uri.identifier = key;

    NSString *formatStr = [self formatToString:format];
    uri.canonicalString = [NSString stringWithFormat:@"ssb:identity/%@/%@", formatStr, key];

    return uri;
}

+ (nullable instancetype)uriWithAddress:(NSString *)multiserverAddress {
    if (!multiserverAddress || multiserverAddress.length == 0) {
        return nil;
    }

    SSBURI *uri = [[SSBURI alloc] init];
    uri.type = SSBURITypeAddress;
    uri.format = SSBURIFormatMultiserver;
    uri.multiserverAddress = multiserverAddress;

    NSString *encoded = [self encodeMultiserverAddress:multiserverAddress];
    uri.canonicalString = [NSString stringWithFormat:@"ssb:address/multiserver?multiserverAddress=%@", encoded];

    return uri;
}

+ (NSString *)formatToString:(SSBURIFormat)format {
    switch (format) {
        case SSBURIFormatClassic:        return @"classic";
        case SSBURIFormatBendybuttV1:    return @"bendybutt-v1";
        case SSBURIFormatGabbygroveV1:   return @"gabbygrove-v1";
        case SSBURIFormatButtwooV1:      return @"buttwoo-v1";
        case SSBURIFormatMultiserver:    return @"multiserver";
        case SSBURIFormatBox2DmDh:       return @"box2-dm-dh";
        case SSBURIFormatPoBox:          return @"po-box";
        case SSBURIFormatFusion:         return @"fusion";
        default:                         return @"unknown";
    }
}

+ (SSBURIFormat)formatFromString:(NSString *)string {
    if (!string) return SSBURIFormatUnknown;

    NSDictionary *formatMap = @{
        @"classic":       @(SSBURIFormatClassic),
        @"sha256":        @(SSBURIFormatClassic),
        @"ed25519":       @(SSBURIFormatClassic),
        @"bendybutt-v1":  @(SSBURIFormatBendybuttV1),
        @"gabbygrove-v1": @(SSBURIFormatGabbygroveV1),
        @"buttwoo-v1":    @(SSBURIFormatButtwooV1),
        @"multiserver":   @(SSBURIFormatMultiserver),
        @"box2-dm-dh":    @(SSBURIFormatBox2DmDh),
        @"po-box":        @(SSBURIFormatPoBox),
        @"fusion":        @(SSBURIFormatFusion)
    };

    NSNumber *formatNum = formatMap[string];
    if (formatNum) {
        return (SSBURIFormat)[formatNum integerValue];
    }

    return SSBURIFormatUnknown;
}

+ (NSString *)typeToString:(SSBURIType)type {
    switch (type) {
        case SSBURITypeMessage:       return @"message";
        case SSBURITypeFeed:           return @"feed";
        case SSBURITypeBlob:          return @"blob";
        case SSBURITypeAddress:       return @"address";
        case SSBURITypeExperimental:  return @"experimental";
        case SSBURITypeEncryptionKey: return @"encryption-key";
        case SSBURITypeIdentity:      return @"identity";
        default:                       return @"unknown";
    }
}

+ (SSBURIType)typeFromString:(NSString *)string {
    if (!string) return SSBURITypeUnknown;

    NSDictionary *typeMap = @{
        @"message":        @(SSBURITypeMessage),
        @"feed":          @(SSBURITypeFeed),
        @"blob":          @(SSBURITypeBlob),
        @"address":       @(SSBURITypeAddress),
        @"experimental":  @(SSBURITypeExperimental),
        @"encryption-key": @(SSBURITypeEncryptionKey),
        @"identity":      @(SSBURITypeIdentity)
    };

    NSNumber *typeNum = typeMap[string];
    if (typeNum) {
        return (SSBURIType)[typeNum integerValue];
    }

    return SSBURITypeUnknown;
}

+ (NSString *)encodeMultiserverAddress:(NSString *)address {
    if (!address) return @"";

    NSCharacterSet *allowedChars = [NSCharacterSet characterSetWithCharactersInString:
                                    @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"];

    return [address stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
}

+ (nullable NSString *)decodeMultiserverAddress:(NSString *)encodedAddress {
    if (!encodedAddress) return nil;
    if (![encodedAddress containsString:@"%"]) return nil;

    NSString *decoded = [encodedAddress stringByRemovingPercentEncoding];
    if (decoded) return decoded;

    // Strict fallback parser: only allow valid %HH escapes.
    // (encodedAddress is guaranteed to contain "%" from the check above.)
    NSString *strictDecoded = [self manualDecodePercentEncoding:encodedAddress];
    return strictDecoded.length > 0 ? strictDecoded : nil;
}

+ (NSString *)manualDecodePercentEncoding:(NSString *)encoded {
    if (!encoded) return @"";

    NSMutableString *result = [NSMutableString string];
    NSScanner *scanner = [NSScanner scannerWithString:encoded];

    while (![scanner isAtEnd]) {
        NSString *unescaped;
        if ([scanner scanUpToString:@"%" intoString:&unescaped]) {
            [result appendString:unescaped];
        }

        if ([scanner scanString:@"%" intoString:nil]) {
            NSString *hex;
            if ([scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] intoString:&hex] && hex.length == 2) {
                unsigned int value;
                NSScanner *hexScanner = [NSScanner scannerWithString:hex];
                [hexScanner scanHexInt:&value];
                [result appendFormat:@"%c", (char)value];
            } else {
                return @"";
            }
        }
    }

    return result;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SSBURI: %@>", self.canonicalString];
}

@end
