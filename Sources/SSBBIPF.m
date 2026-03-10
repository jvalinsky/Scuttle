//
//  SSBBIPF.m
//  ScuttleKit
//
//  BIPF (Binary In-Place Format) implementation for SIP-011
//  Based on: https://github.com/ssbc/sips/blob/master/011.md
//

#import "SSBBIPF.h"
#import <math.h>

@implementation SSBBIPF

#pragma mark - Public API

+ (nullable NSData *)encode:(id)value {
    if (!value || [value isEqual:[NSNull null]]) {
        return [self encodeNull];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [self encodeString:value];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [self encodeBytes:value];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)value;
        const char *type = [num objCType];
        if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0) {
            return [self encodeBool:[num boolValue]];
        }
        if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
            return [self encodeDouble:[num doubleValue]];
        }
        return [self encodeInteger:[num longLongValue]];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [self encodeList:value];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [self encodeDictionary:value];
    }
    return nil;
}

+ (nullable id)decode:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    NSUInteger offset = 0;
    if (![self readVarint:data offset:offset value:&tag]) return nil;
    offset += [self varintSize:tag];
    
    uint8_t type = tag & 0x07;
    uint64_t length = tag >> 3;
    
    switch (type) {
        case SSBBIPFTypeString: {
            NSUInteger strConsumed = 0;
            NSString *str = [self decodeString:data offset:offset consumed:&strConsumed];
            if (!str) return nil;
            if (consumed) *consumed = offset + strConsumed;
            return str;
        }
        case SSBBIPFTypeBytes: {
            if (offset + length > data.length) return nil;
            NSData *bytes = [data subdataWithRange:NSMakeRange(offset, length)];
            if (consumed) *consumed = offset + length;
            return bytes;
        }
        case SSBBIPFTypeInt: {
            if (offset + length > data.length) return nil;
            int64_t value = 0;
            for (uint64_t i = 0; i < length; i++) {
                uint8_t byte = ((uint8_t *)data.bytes)[offset + i];
                value |= ((int64_t)byte << (8 * i));
            }
            if (length > 0 && ((uint8_t *)data.bytes)[offset + length - 1] & 0x80) {
                value = value - (1LL << (length * 8));
            }
            if (consumed) *consumed = offset + length;
            return @(value);
        }
        case SSBBIPFTypeDouble: {
            if (offset + length > data.length) return nil;
            double value = 0;
            if (length == 8) {
                uint64_t bits = 0;
                for (uint64_t i = 0; i < 8; i++) {
                    bits |= ((uint64_t)((uint8_t *)data.bytes)[offset + i] << (8 * i));
                }
                memcpy(&value, &bits, 8);
            }
            if (consumed) *consumed = offset + length;
            return @(value);
        }
        case SSBBIPFTypeList: {
            NSMutableArray *list = [NSMutableArray array];
            NSUInteger currentOffset = offset;
            while (currentOffset < offset + length) {
                NSUInteger itemConsumed = 0;
                id item = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, offset + length - currentOffset)] consumed:&itemConsumed];
                if (!item) return nil;
                [list addObject:item];
                currentOffset += itemConsumed;
            }
            if (consumed) *consumed = offset + length;
            return list;
        }
        case SSBBIPFTypeDict: {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            NSUInteger currentOffset = offset;
            while (currentOffset < offset + length) {
                NSUInteger keyConsumed = 0;
                id key = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, offset + length - currentOffset)] consumed:&keyConsumed];
                if (!key || ![key isKindOfClass:[NSString class]]) return nil;
                currentOffset += keyConsumed;
                
                NSUInteger valueConsumed = 0;
                id value = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, offset + length - currentOffset)] consumed:&valueConsumed];
                if (!value) return nil;
                currentOffset += valueConsumed;
                
                dict[key] = value;
            }
            if (consumed) *consumed = offset + length;
            return dict;
        }
        case SSBBIPFTypeBoolNull: {
            if (length == 0) {
                if (consumed) *consumed = offset;
                return [NSNull null];
            }
            if (consumed) *consumed = offset;
            return @((BOOL)length);
        }
        case SSBBIPFTypeExtended:
        default:
            return nil;
    }
}

#pragma mark - Encoding

+ (nullable NSData *)encodeString:(NSString *)string {
    NSData *utf8Data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8Data) return nil;
    
    uint64_t tag = ((uint64_t)utf8Data.length << 3) | SSBBIPFTypeString;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:utf8Data];
    return result;
}

+ (nullable NSData *)encodeBytes:(NSData *)bytes {
    uint64_t tag = ((uint64_t)bytes.length << 3) | SSBBIPFTypeBytes;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:bytes];
    return result;
}

+ (nullable NSData *)encodeInteger:(int64_t)integer {
    int64_t value = integer;
    NSMutableData *bytes = [NSMutableData data];
    
    if (value == 0) {
        [bytes appendBytes:(uint8_t[]){0} length:1];
    } else {
        uint8_t buf[10];
        int len = 0;
        uint64_t uvalue = (value < 0) ? (1ULL << 64) + value : value;
        while (uvalue > 0) {
            buf[len++] = uvalue & 0xFF;
            uvalue >>= 8;
        }
        [bytes appendBytes:buf length:len];
    }
    
    uint64_t tag = ((uint64_t)bytes.length << 3) | SSBBIPFTypeInt;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:bytes];
    return result;
}

+ (nullable NSData *)encodeDouble:(double)d {
    uint64_t bits;
    memcpy(&bits, &d, 8);
    NSMutableData *bytes = [NSMutableData dataWithBytes:&bits length:8];
    
    uint64_t tag = ((uint64_t)8 << 3) | SSBBIPFTypeDouble;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:bytes];
    return result;
}

+ (nullable NSData *)encodeList:(NSArray *)list {
    NSMutableData *encodedItems = [NSMutableData data];
    for (id item in list) {
        NSData *encoded = [self encode:item];
        if (!encoded) return nil;
        [encodedItems appendData:encoded];
    }
    
    uint64_t tag = ((uint64_t)encodedItems.length << 3) | SSBBIPFTypeList;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:encodedItems];
    return result;
}

+ (nullable NSData *)encodeDictionary:(NSDictionary *)dict {
    NSMutableData *encodedPairs = [NSMutableData data];
    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    for (NSString *key in sortedKeys) {
        NSData *encodedKey = [self encode:key];
        if (!encodedKey) return nil;
        id value = dict[key];
        NSData *encodedValue = [self encode:value];
        if (!encodedValue) return nil;
        [encodedPairs appendData:encodedKey];
        [encodedPairs appendData:encodedValue];
    }
    
    uint64_t tag = ((uint64_t)encodedPairs.length << 3) | SSBBIPFTypeDict;
    NSMutableData *result = [NSMutableData dataWithData:[self writeVarint:tag]];
    [result appendData:encodedPairs];
    return result;
}

+ (nullable NSData *)encodeBool:(BOOL)value {
    uint64_t tag = ((uint64_t)(value ? 1 : 0) << 3) | SSBBIPFTypeBoolNull;
    return [self writeVarint:tag];
}

+ (nullable NSData *)encodeNull {
    uint64_t tag = (0ULL << 3) | SSBBIPFTypeBoolNull;
    return [self writeVarint:tag];
}

#pragma mark - Decoding

+ (nullable NSString *)decodeString:(NSData *)data consumed:(NSUInteger *)consumed {
    return [self decodeString:data offset:0 consumed:consumed];
}

+ (nullable NSString *)decodeString:(NSData *)data offset:(NSUInteger)offset consumed:(NSUInteger *)consumed {
    if (data.length <= offset) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:offset value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeString) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    if (offset + headerSize + length > data.length) return nil;
    
    NSData *stringData = [data subdataWithRange:NSMakeRange(offset + headerSize, length)];
    NSString *str = [[NSString alloc] initWithData:stringData encoding:NSUTF8StringEncoding];
    if (!str) return nil;
    
    if (consumed) *consumed = headerSize + length;
    return str;
}

+ (nullable NSData *)decodeBytes:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeBytes) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    if (headerSize + length > data.length) return nil;
    
    NSData *bytes = [data subdataWithRange:NSMakeRange(headerSize, length)];
    if (consumed) *consumed = headerSize + length;
    return bytes;
}

+ (nullable NSNumber *)decodeInteger:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeInt) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    if (headerSize + length > data.length) return nil;
    
    int64_t value = 0;
    for (uint64_t i = 0; i < length; i++) {
        uint8_t byte = ((uint8_t *)data.bytes)[headerSize + i];
        value |= ((int64_t)byte << (8 * i));
    }
    if (length > 0 && ((uint8_t *)data.bytes)[headerSize + length - 1] & 0x80) {
        value = value - (1LL << (length * 8));
    }
    
    if (consumed) *consumed = headerSize + length;
    return @(value);
}

+ (nullable NSNumber *)decodeDouble:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length < 9) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeDouble) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    if (length != 8 || headerSize + 8 > data.length) return nil;
    
    uint64_t bits = 0;
    for (uint64_t i = 0; i < 8; i++) {
        bits |= ((uint64_t)((uint8_t *)data.bytes)[headerSize + i] << (8 * i));
    }
    
    double value;
    memcpy(&value, &bits, 8);
    
    if (consumed) *consumed = headerSize + 8;
    return @(value);
}

+ (nullable NSArray *)decodeList:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeList) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    NSMutableArray *list = [NSMutableArray array];
    NSUInteger currentOffset = headerSize;
    NSUInteger endOffset = headerSize + length;
    
    while (currentOffset < endOffset) {
        NSUInteger itemConsumed = 0;
        id item = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, endOffset - currentOffset)] consumed:&itemConsumed];
        if (!item) return nil;
        [list addObject:item];
        currentOffset += itemConsumed;
    }
    
    if (consumed) *consumed = headerSize + length;
    return list;
}

+ (nullable NSDictionary *)decodeDictionary:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeDict) return nil;
    
    NSUInteger headerSize = [self varintSize:tag];
    uint64_t length = tag >> 3;
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSUInteger currentOffset = headerSize;
    NSUInteger endOffset = headerSize + length;
    
    while (currentOffset < endOffset) {
        NSUInteger keyConsumed = 0;
        id key = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, endOffset - currentOffset)] consumed:&keyConsumed];
        if (!key || ![key isKindOfClass:[NSString class]]) return nil;
        currentOffset += keyConsumed;
        
        NSUInteger valueConsumed = 0;
        id value = [self decode:[data subdataWithRange:NSMakeRange(currentOffset, endOffset - currentOffset)] consumed:&valueConsumed];
        if (!value) return nil;
        currentOffset += valueConsumed;
        
        dict[key] = value;
    }
    
    if (consumed) *consumed = headerSize + length;
    return dict;
}

+ (nullable NSNumber *)decodeBool:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeBoolNull) return nil;
    
    uint64_t length = tag >> 3;
    if (length > 1) return nil;
    
    if (consumed) *consumed = [self varintSize:tag];
    return @(length == 1);
}

+ (nullable id)decodeNull:(NSData *)data consumed:(NSUInteger *)consumed {
    if (data.length == 0) return nil;
    
    uint64_t tag;
    if (![self readVarint:data offset:0 value:&tag]) return nil;
    
    uint8_t type = tag & 0x07;
    if (type != SSBBIPFTypeBoolNull) return nil;
    
    uint64_t length = tag >> 3;
    if (length != 0) return nil;
    
    if (consumed) *consumed = [self varintSize:tag];
    return [NSNull null];
}

#pragma mark - Varint Helpers

+ (uint8_t)readVarint:(NSData *)data offset:(NSUInteger)offset value:(uint64_t *)value {
    if (!value || data.length <= offset) return 0;
    
    *value = 0;
    uint8_t bytesRead = 0;
    
    while (offset + bytesRead < data.length && bytesRead < 10) {
        uint8_t byte = ((uint8_t *)data.bytes)[offset + bytesRead];
        *value |= ((uint64_t)(byte & 0x7F) << (7 * bytesRead));
        bytesRead++;
        if (!(byte & 0x80)) break;
    }
    
    return bytesRead;
}

+ (NSData *)writeVarint:(uint64_t)value {
    NSMutableData *result = [NSMutableData data];
    while (value > 0x7F) {
        uint8_t byte = (value & 0x7F) | 0x80;
        [result appendBytes:&byte length:1];
        value >>= 7;
    }
    uint8_t byte = value & 0x7F;
    [result appendBytes:&byte length:1];
    return result;
}

+ (NSUInteger)varintSize:(uint64_t)value {
    if (value < (1ULL << 7)) return 1;
    if (value < (1ULL << 14)) return 2;
    if (value < (1ULL << 21)) return 3;
    if (value < (1ULL << 28)) return 4;
    if (value < (1ULL << 35)) return 5;
    if (value < (1ULL << 42)) return 6;
    if (value < (1ULL << 49)) return 7;
    if (value < (1ULL << 56)) return 8;
    return 9;
}

#pragma mark - Human Readable (Debug)

+ (NSString *)humanReadable:(NSData *)data {
    if (!data || data.length == 0) return @"";
    
    NSUInteger consumed = 0;
    id value = [self decode:data consumed:&consumed];
    
    if (!value) return @"<invalid BIPF>";
    
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"\"%@\"", value];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)value;
        const char *type = [num objCType];
        if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0) {
            return [num boolValue] ? @"true" : @"false";
        }
        if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
            return [NSString stringWithFormat:@"%g", [num doubleValue]];
        }
        return [NSString stringWithFormat:@"%lld", [num longLongValue]];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in value) {
            NSData *itemData = [self encode:item];
            if (itemData) {
                [items addObject:[self humanReadable:itemData]];
            }
        }
        return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *key in [value allKeys]) {
            NSData *keyData = [self encode:key];
            NSData *valData = [self encode:value[key]];
            if (keyData && valData) {
                [pairs addObject:[NSString stringWithFormat:@"%@:%@", [self humanReadable:keyData], [self humanReadable:valData]]];
            }
        }
        return [NSString stringWithFormat:@"{%@}", [pairs componentsJoinedByString:@","]];
    }
    if ([value isEqual:[NSNull null]]) {
        return @"null";
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"#%@#", [(NSData *)value base64EncodedStringWithOptions:0]];
    }
    return [value description];
}

@end
