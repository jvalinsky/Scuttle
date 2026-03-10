#import "SSBBendyButt.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonHMAC.h>

static const NSUInteger kMaxMessageSize = 8192;

@interface SSBBendyButt ()
@property (nonatomic, readwrite) NSData *author;
@property (nonatomic, readwrite) NSInteger sequence;
@property (nonatomic, readwrite, nullable) NSData *previous;
@property (nonatomic, readwrite) NSInteger timestamp;
@property (nonatomic, readwrite, nullable) NSData *content;
@property (nonatomic, readwrite, nullable) NSData *contentSignature;
@property (nonatomic, readwrite, nullable) NSData *encryptedContent;
@property (nonatomic, readwrite) NSData *signature;
@property (nonatomic, readwrite) NSData *messageKey;
@end

@implementation SSBBendyButt

- (instancetype)initWithAuthor:(NSData *)author
                      sequence:(NSInteger)sequence
                      previous:(NSData *)previous
                     timestamp:(NSInteger)timestamp
                        content:(NSData *)content
               contentSignature:(NSData *)contentSignature
                encryptedContent:(NSData *)encryptedContent
                      signature:(NSData *)signature
                     messageKey:(NSData *)messageKey {
    self = [super init];
    if (self) {
        _author = author;
        _sequence = sequence;
        _previous = previous;
        _timestamp = timestamp;
        _content = content;
        _contentSignature = contentSignature;
        _encryptedContent = encryptedContent;
        _signature = signature;
        _messageKey = messageKey;
    }
    return self;
}

#pragma mark - Message Creation

+ (nullable instancetype)messageWithContent:(NSDictionary *)content
                                     author:(NSData *)author
                               authorSecret:(NSData *)authorSecret
                                   sequence:(NSInteger)sequence
                                   previous:(nullable NSData *)previous
                                  timestamp:(NSInteger)timestamp
                            contentSecretKey:(NSData *)contentSecretKey {
    NSData *contentData = [self encodeBencodeDict:content];
    if (!contentData) {
        return nil;
    }

    NSData *contentSignatureData = [self signContent:contentData withKey:contentSecretKey];
    if (!contentSignatureData) {
        return nil;
    }

    NSData *authorBFE = [self encodeBFEFeedID:author];
    if (!authorBFE) {
        return nil;
    }

    NSData *previousBFE = previous ? [self encodeBFEMessageID:previous] : [SSBBFE encodeNil];
    if (!previousBFE) {
        return nil;
    }

    NSArray *contentSection = @[contentData, contentSignatureData];
    NSData *contentSectionData = [self encodeBencodeList:contentSection];
    if (!contentSectionData) {
        return nil;
    }

    NSArray *payload = @[authorBFE, @(sequence), previousBFE, @(timestamp), contentSectionData];
    NSData *payloadData = [self encodeBencodeList:payload];
    if (!payloadData) {
        return nil;
    }

    NSData *signatureData = [self signPayload:payloadData withAuthorSecret:authorSecret];
    if (!signatureData) {
        return nil;
    }

    NSArray *message = @[payloadData, signatureData];
    NSData *messageData = [self encodeBencodeList:message];
    if (!messageData) {
        return nil;
    }

    if (messageData.length > kMaxMessageSize) {
        return nil;
    }

    NSData *messageKeyData = [self computeMessageKey:messageData];
    if (!messageKeyData) {
        return nil;
    }

    return [[SSBBendyButt alloc] initWithAuthor:author
                                       sequence:sequence
                                       previous:previous
                                      timestamp:timestamp
                                         content:contentData
                                contentSignature:contentSignatureData
                                 encryptedContent:nil
                                       signature:signatureData
                                      messageKey:messageKeyData];
}

+ (nullable instancetype)messageWithEncryptedContent:(NSData *)encryptedContent
                                              author:(NSData *)author
                                        authorSecret:(NSData *)authorSecret
                                            sequence:(NSInteger)sequence
                                            previous:(nullable NSData *)previous
                                           timestamp:(NSInteger)timestamp
                                     contentSecretKey:(NSData *)contentSecretKey {
    NSData *authorBFE = [self encodeBFEFeedID:author];
    if (!authorBFE) {
        return nil;
    }

    NSData *previousBFE = previous ? [self encodeBFEMessageID:previous] : [SSBBFE encodeNil];
    if (!previousBFE) {
        return nil;
    }

    NSData *encryptedBFE = [SSBBFE encodeEncrypted:encryptedContent format:SSBBFEEncryptedFormatBox1];
    if (!encryptedBFE) {
        return nil;
    }

    NSArray *payload = @[authorBFE, @(sequence), previousBFE, @(timestamp), encryptedBFE];
    NSData *payloadData = [self encodeBencodeList:payload];
    if (!payloadData) {
        return nil;
    }

    NSData *contentData = [@"encrypted" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *contentSignatureData = [self signContent:contentData withKey:contentSecretKey];

    NSData *signatureData = [self signPayload:payloadData withAuthorSecret:authorSecret];
    if (!signatureData) {
        return nil;
    }

    NSArray *message = @[payloadData, signatureData];
    NSData *messageData = [self encodeBencodeList:message];
    if (!messageData) {
        return nil;
    }

    if (messageData.length > kMaxMessageSize) {
        return nil;
    }

    NSData *messageKeyData = [self computeMessageKey:messageData];
    if (!messageKeyData) {
        return nil;
    }

    return [[SSBBendyButt alloc] initWithAuthor:author
                                       sequence:sequence
                                       previous:previous
                                      timestamp:timestamp
                                         content:contentData
                                contentSignature:contentSignatureData
                                 encryptedContent:encryptedContent
                                       signature:signatureData
                                      messageKey:messageKeyData];
}

+ (nullable NSData *)createMessageWithContent:(NSDictionary *)content
                                       author:(NSData *)author
                                 authorSecret:(NSData *)authorSecret
                                     sequence:(NSInteger)sequence
                                     previous:(nullable NSData *)previous
                                    timestamp:(NSInteger)timestamp
                                contentSecretKey:(NSData *)contentSecretKey {
    NSData *contentData = [self encodeBencodeDict:content];
    if (!contentData) {
        return nil;
    }

    NSData *contentSignatureData = [self signContent:contentData withKey:contentSecretKey];
    if (!contentSignatureData) {
        return nil;
    }

    NSData *authorBFE = [self encodeBFEFeedID:author];
    if (!authorBFE) {
        return nil;
    }

    NSData *previousBFE = previous ? [self encodeBFEMessageID:previous] : [SSBBFE encodeNil];
    if (!previousBFE) {
        return nil;
    }

    NSArray *contentSection = @[contentData, contentSignatureData];
    NSData *contentSectionData = [self encodeBencodeList:contentSection];
    if (!contentSectionData) {
        return nil;
    }

    NSArray *payload = @[authorBFE, @(sequence), previousBFE, @(timestamp), contentSectionData];
    NSData *payloadData = [self encodeBencodeList:payload];
    if (!payloadData) {
        return nil;
    }

    NSData *signatureData = [self signPayload:payloadData withAuthorSecret:authorSecret];
    if (!signatureData) {
        return nil;
    }

    NSArray *message = @[payloadData, signatureData];
    NSData *messageData = [self encodeBencodeList:message];
    if (!messageData) {
        return nil;
    }

    if (messageData.length > kMaxMessageSize) {
        return nil;
    }

    return messageData;
}

#pragma mark - Validation

+ (BOOL)validateMessage:(NSData *)messageData {
    if (!messageData || messageData.length == 0) {
        return NO;
    }

    if (messageData.length > kMaxMessageSize) {
        return NO;
    }

    NSUInteger offset = 0;
    NSArray *message = [self decodeBencode:messageData offset:&offset];
    if (!message || message.count != 2) {
        return NO;
    }

    NSData *payloadData = message[0];
    NSData *signatureBFE = message[1];

    if (![payloadData isKindOfClass:[NSData class]] || ![signatureBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    offset = 0;
    NSArray *payload = [self decodeBencode:payloadData offset:&offset];
    if (!payload || payload.count != 5) {
        return NO;
    }

    NSData *authorBFE = payload[0];
    NSNumber *sequenceNum = payload[1];
    NSData *previousBFE = payload[2];
    NSNumber *timestampNum = payload[3];
    id contentSection = payload[4];

    if (![authorBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    if (![sequenceNum isKindOfClass:[NSNumber class]] || sequenceNum.integerValue < 1) {
        return NO;
    }

    if (![previousBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    if (![timestampNum isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    SSBBFEType authorType = [SSBBFE detectType:authorBFE];
    NSInteger authorFormat = [SSBBFE detectFormat:authorBFE];
    if (authorType != SSBBFETypeFeed || authorFormat != SSBBFEFeedFormatBendybuttV1) {
        return NO;
    }

    SSBBFEType prevType = [SSBBFE detectType:previousBFE];
    NSInteger prevFormat = [SSBBFE detectFormat:previousBFE];
    if (prevType == SSBBFETypeGeneric && prevFormat == SSBBFEGenericFormatNil) {
    } else if (prevType != SSBBFETypeMessage || prevFormat != SSBBFEMessageFormatBendybuttV1) {
        return NO;
    }

    if (![contentSection isKindOfClass:[NSData class]] && ![contentSection isKindOfClass:[NSArray class]]) {
        return NO;
    }

    NSData *authorKey = [authorBFE subdataWithRange:NSMakeRange(2, authorBFE.length - 2)];
    if (authorKey.length != 32) {
        return NO;
    }

    if (![self verifyPayloadSignature:signatureBFE onPayload:payloadData author:authorKey]) {
        return NO;
    }

    return YES;
}

#pragma mark - Message Key

+ (nullable NSData *)computeMessageKey:(NSData *)messageData {
    if (!messageData || messageData.length == 0) {
        return nil;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(messageData.bytes, (CC_LONG)messageData.length, digest);

    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Content Signing

+ (nullable NSData *)signContent:(NSData *)content withKey:(NSData *)key {
    if (!content || !key || key.length != 32) {
        return nil;
    }

    NSString *prefix = @"bendybutt";
    NSData *prefixData = [prefix dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *signData = [NSMutableData dataWithData:prefixData];
    [signData appendData:content];

    unsigned char fullMac[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, key.bytes, key.length, signData.bytes, signData.length, fullMac);

    return [NSData dataWithBytes:fullMac length:32];
}

+ (BOOL)verifyContentSignature:(NSData *)signature
                     onContent:(NSData *)content
                        author:(NSData *)author {
    if (!signature || signature.length != 32) {
        return NO;
    }

    if (!content || !author || author.length != 32) {
        return NO;
    }

    NSString *prefix = @"bendybutt";
    NSData *prefixData = [prefix dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *signData = [NSMutableData dataWithData:prefixData];
    [signData appendData:content];

    unsigned char fullMac[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, author.bytes, author.length, signData.bytes, signData.length, fullMac);

    return memcmp(signature.bytes, fullMac, 32) == 0;
}

#pragma mark - Payload Signing

+ (nullable NSData *)signPayload:(NSData *)payload withAuthorSecret:(NSData *)authorSecret {
    if (!payload || !authorSecret || authorSecret.length != 64) {
        return nil;
    }

    unsigned char signature[crypto_sign_BYTES + payload.length];
    unsigned long long smlen;
    int ret = crypto_sign(signature, &smlen, payload.bytes, (unsigned long long)payload.length, authorSecret.bytes);
    if (ret != 0) {
        return nil;
    }

    return [NSData dataWithBytes:signature length:crypto_sign_BYTES];
}

+ (BOOL)verifyPayloadSignature:(NSData *)signatureBFE onPayload:(NSData *)payload author:(NSData *)authorKey {
    if (!signatureBFE || !payload || !authorKey || authorKey.length != 32) {
        return NO;
    }

    SSBBFEType sigType = [SSBBFE detectType:signatureBFE];
    if (sigType != SSBBFETypeSignature) {
        return NO;
    }

    NSData *signature = [signatureBFE subdataWithRange:NSMakeRange(2, signatureBFE.length - 2)];
    if (signature.length != crypto_sign_BYTES) {
        return NO;
    }

    NSMutableData *sm = [NSMutableData dataWithData:signature];
    [sm appendData:payload];

    unsigned char m[sm.length];
    unsigned long long mlen;
    int ret = crypto_sign_open(m, &mlen, sm.bytes, (unsigned long long)sm.length, authorKey.bytes);

    if (ret != 0) {
        return NO;
    }

    if (mlen != payload.length) {
        return NO;
    }

    return memcmp(m, payload.bytes, payload.length) == 0;
}

#pragma mark - BFE Encoding

+ (nullable NSData *)encodeBFEFeedID:(NSData *)keyData {
    if (!keyData || keyData.length != 32) {
        return nil;
    }

    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeFeed;
    uint8_t formatByte = (uint8_t)SSBBFEFeedFormatBendybuttV1;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:keyData];

    return bfeData;
}

+ (nullable NSData *)encodeBFEMessageID:(NSData *)hashData {
    if (!hashData || hashData.length != 32) {
        return nil;
    }

    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeMessage;
    uint8_t formatByte = (uint8_t)SSBBFEMessageFormatBendybuttV1;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:hashData];

    return bfeData;
}

#pragma mark - Bencode Encoding

+ (nullable NSData *)encodeBencodeInteger:(NSInteger)value {
    NSString *intStr = [NSString stringWithFormat:@"i%lde", (long)value];
    return [intStr dataUsingEncoding:NSUTF8StringEncoding];
}

+ (nullable NSData *)encodeBencodeString:(NSString *)string {
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!stringData) {
        return nil;
    }
    NSString *lenStr = [NSString stringWithFormat:@"%lu:", (unsigned long)stringData.length];
    NSMutableData *result = [[lenStr dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [result appendData:stringData];
    return result;
}

+ (nullable NSData *)encodeBencodeData:(NSData *)data {
    if (!data) {
        return nil;
    }
    NSString *lenStr = [NSString stringWithFormat:@"%lu:", (unsigned long)data.length];
    NSMutableData *result = [[lenStr dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [result appendData:data];
    return result;
}

+ (nullable NSData *)encodeBencodeList:(NSArray *)list {
    if (!list) {
        return nil;
    }

    NSMutableData *result = [NSMutableData dataWithBytes:"l" length:1];

    for (id item in list) {
        NSData *encoded = [self encodeBencodeItem:item];
        if (!encoded) {
            return nil;
        }
        [result appendData:encoded];
    }

    [result appendBytes:"e" length:1];
    return result;
}

+ (nullable NSData *)encodeBencodeDict:(NSDictionary *)dict {
    if (!dict) {
        return nil;
    }

    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableData *result = [NSMutableData dataWithBytes:"d" length:1];

    for (NSString *key in sortedKeys) {
        NSData *keyData = [self encodeBencodeString:key];
        if (!keyData) {
            return nil;
        }
        [result appendData:keyData];

        id value = dict[key];
        NSData *valueData = [self encodeBencodeItem:value];
        if (!valueData) {
            return nil;
        }
        [result appendData:valueData];
    }

    [result appendBytes:"e" length:1];
    return result;
}

+ (nullable NSData *)encodeBencodeItem:(id)item {
    if ([item isKindOfClass:[NSData class]]) {
        return [self encodeBencodeData:item];
    } else if ([item isKindOfClass:[NSString class]]) {
        return [self encodeBencodeString:item];
    } else if ([item isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)item;
        if (strcmp([num objCType], @encode(NSInteger)) == 0 ||
            strcmp([num objCType], @encode(long)) == 0 ||
            strcmp([num objCType], @encode(int)) == 0) {
            return [self encodeBencodeInteger:num.integerValue];
        }
        return [self encodeBencodeString:[num stringValue]];
    } else if ([item isKindOfClass:[NSArray class]]) {
        return [self encodeBencodeList:item];
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        return [self encodeBencodeDict:item];
    } else if ([item isKindOfClass:[NSNull class]]) {
        return [@"0:" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return nil;
}

#pragma mark - Bencode Decoding

+ (nullable id)decodeBencode:(NSData *)data offset:(NSUInteger *)offset {
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
    }
    else if (ch >= '0' && ch <= '9') {
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
        NSData *strData = [data subdataWithRange:NSMakeRange(*offset, strLen)];
        (*offset) += strLen;
        return strData;
    }
    else if (ch == 'l') {
        (*offset)++;
        NSMutableArray *list = [NSMutableArray array];
        while (*offset < len && bytes[*offset] != 'e') {
            id item = [self decodeBencode:data offset:offset];
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
    }
    else if (ch == 'd') {
        (*offset)++;
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        while (*offset < len && bytes[*offset] != 'e') {
            NSData *keyData = [self decodeBencode:data offset:offset];
            if (!keyData || ![keyData isKindOfClass:[NSData class]]) {
                return nil;
            }
            NSString *key = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
            if (!key) {
                return nil;
            }
            id value = [self decodeBencode:data offset:offset];
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
    }
    else if (ch == 'e') {
        return @[];
    }

    return nil;
}

@end
