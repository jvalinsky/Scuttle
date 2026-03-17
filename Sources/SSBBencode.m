#import "SSBBencode.h"

@implementation SSBBencode

+ (nullable NSData *)encodeInteger:(NSInteger)value {
    NSString *str = [NSString stringWithFormat:@"i%lde", (long)value];
    return [str dataUsingEncoding:NSUTF8StringEncoding];
}

+ (nullable NSData *)encodeString:(NSString *)string {
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!stringData) {
        return nil;
    }
    return [self encodeData:stringData];
}

+ (nullable NSData *)encodeData:(NSData *)data {
    if (!data) {
        return nil;
    }
    NSString *lenStr = [NSString stringWithFormat:@"%lu:", (unsigned long)data.length];
    NSMutableData *result = [[lenStr dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [result appendData:data];
    return result;
}

+ (nullable NSData *)encodeList:(NSArray<id> *)list {
    if (!list) {
        return nil;
    }
    NSMutableData *result = [NSMutableData dataWithBytes:"l" length:1];
    for (id item in list) {
        NSData *encoded = [self _encodeItem:item];
        if (!encoded) {
            return nil;
        }
        [result appendData:encoded];
    }
    [result appendBytes:"e" length:1];
    return result;
}

+ (nullable NSData *)encodeDict:(NSDictionary<NSString *, id> *)dict {
    if (!dict) {
        return nil;
    }
    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableData *result = [NSMutableData dataWithBytes:"d" length:1];
    for (NSString *key in sortedKeys) {
        NSData *keyData = [self encodeString:key];
        if (!keyData) {
            return nil;
        }
        [result appendData:keyData];
        NSData *valueData = [self _encodeItem:dict[key]];
        if (!valueData) {
            return nil;
        }
        [result appendData:valueData];
    }
    [result appendBytes:"e" length:1];
    return result;
}

+ (nullable NSData *)_encodeItem:(id)item {
    if ([item isKindOfClass:[NSData class]]) {
        return [self encodeData:item];
    } else if ([item isKindOfClass:[NSString class]]) {
        return [self encodeString:item];
    } else if ([item isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)item;
        if (strcmp([num objCType], @encode(NSInteger)) == 0 ||
            strcmp([num objCType], @encode(long)) == 0 ||
            strcmp([num objCType], @encode(int)) == 0) {
            return [self encodeInteger:num.integerValue];
        }
        return [self encodeString:[num stringValue]];
    } else if ([item isKindOfClass:[NSArray class]]) {
        return [self encodeList:item];
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        return [self encodeDict:item];
    } else if ([item isKindOfClass:[NSNull class]]) {
        // Encode null as a zero-length byte string
        return [@"0:" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return nil;
}

+ (nullable id)decode:(NSData *)data offset:(NSUInteger *)offset {
    if (!data || !offset || *offset >= data.length) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    uint8_t ch = bytes[*offset];

    if (ch == 'i') {
        (*offset)++;
        NSInteger value = 0;
        BOOL negative = NO;
        if (*offset < len && bytes[*offset] == '-') {
            negative = YES;
            (*offset)++;
        }
        while (*offset < len && bytes[*offset] >= '0' && bytes[*offset] <= '9') {
            value = value * 10 + (bytes[*offset] - '0');
            (*offset)++;
        }
        if (*offset >= len || bytes[*offset] != 'e') {
            return nil;
        }
        (*offset)++;
        return @(negative ? -value : value);
    } else if (ch >= '0' && ch <= '9') {
        NSUInteger strLen = 0;
        while (*offset < len && bytes[*offset] >= '0' && bytes[*offset] <= '9') {
            strLen = strLen * 10 + (bytes[*offset] - '0');
            (*offset)++;
        }
        if (*offset >= len || bytes[*offset] != ':') {
            return nil;
        }
        (*offset)++;
        if (*offset + strLen > len) {
            return nil;
        }
        NSData *result = [data subdataWithRange:NSMakeRange(*offset, strLen)];
        (*offset) += strLen;
        return result;
    } else if (ch == 'l') {
        (*offset)++;
        NSMutableArray *list = [NSMutableArray array];
        while (*offset < len && bytes[*offset] != 'e') {
            id item = [self decode:data offset:offset];
            if (!item) {
                return nil;
            }
            [list addObject:item];
        }
        if (*offset >= len || bytes[*offset] != 'e') {
            return nil;
        }
        (*offset)++;
        return list;
    } else if (ch == 'd') {
        (*offset)++;
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        while (*offset < len && bytes[*offset] != 'e') {
            NSData *keyData = [self decode:data offset:offset];
            if (!keyData || ![keyData isKindOfClass:[NSData class]]) {
                return nil;
            }
            NSString *key = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
            if (!key) {
                return nil;
            }
            id value = [self decode:data offset:offset];
            if (!value) {
                return nil;
            }
            dict[key] = value;
        }
        if (*offset >= len || bytes[*offset] != 'e') {
            return nil;
        }
        (*offset)++;
        return dict;
    } else if (ch == 'e') {
        return @[];
    }

    return nil;
}

@end
