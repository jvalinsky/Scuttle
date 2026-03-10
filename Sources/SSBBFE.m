#import "SSBBFE.h"

@implementation SSBBFE

#pragma mark - Feed ID Encoding

+ (nullable NSData *)encodeFeedID:(id)feedID format:(SSBBFEFeedFormat)format {
    NSData *keyData = nil;
    
    if ([feedID isKindOfClass:[NSString class]]) {
        NSString *feedIDString = (NSString *)feedID;
        if ([feedIDString hasPrefix:@"@"]) {
            NSString *base64Part = nil;
            if ([feedIDString containsString:@".ed25519"]) {
                base64Part = [[feedIDString substringFromIndex:1] stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
            } else {
                base64Part = [feedIDString substringFromIndex:1];
            }
            NSData *decoded = [self dataFromBase64URLEncodedString:base64Part];
            if (decoded.length > 0) {
                keyData = decoded;
            }
        } else {
            keyData = [self dataFromBase64URLEncodedString:feedIDString];
        }
    } else if ([feedID isKindOfClass:[NSData class]]) {
        keyData = (NSData *)feedID;
    }
    
    if (!keyData || keyData.length == 0) {
        return nil;
    }
    
    if (keyData.length != 32) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeFeed;
    uint8_t formatByte = (uint8_t)format;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:keyData];
    
    return bfeData;
}

#pragma mark - Message ID Encoding

+ (nullable NSData *)encodeMessageID:(id)messageID format:(SSBBFEMessageFormat)format {
    NSData *hashData = nil;
    
    if ([messageID isKindOfClass:[NSString class]]) {
        NSString *msgIDString = (NSString *)messageID;
        if ([msgIDString hasPrefix:@"%"]) {
            NSString *base64Part = nil;
            if ([msgIDString containsString:@".sha256"]) {
                base64Part = [[msgIDString substringFromIndex:1] stringByReplacingOccurrencesOfString:@".sha256" withString:@""];
            } else if ([msgIDString containsString:@".cloaked"]) {
                base64Part = [[msgIDString substringFromIndex:1] stringByReplacingOccurrencesOfString:@".cloaked" withString:@""];
            } else {
                base64Part = [msgIDString substringFromIndex:1];
            }
            NSData *decoded = [self dataFromBase64URLEncodedString:base64Part];
            if (decoded.length > 0) {
                hashData = decoded;
            }
        } else {
            hashData = [self dataFromBase64URLEncodedString:msgIDString];
        }
    } else if ([messageID isKindOfClass:[NSData class]]) {
        hashData = (NSData *)messageID;
    }
    
    if (!hashData || hashData.length == 0) {
        return nil;
    }
    
    NSUInteger expectedLength = (format == SSBBFEMessageFormatBamboo) ? 64 : 32;
    if (hashData.length != expectedLength) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeMessage;
    uint8_t formatByte = (uint8_t)format;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:hashData];
    
    return bfeData;
}

#pragma mark - Blob ID Encoding

+ (nullable NSData *)encodeBlobID:(id)blobID {
    NSData *hashData = nil;
    
    if ([blobID isKindOfClass:[NSString class]]) {
        NSString *blobIDString = (NSString *)blobID;
        if ([blobIDString hasPrefix:@"&"]) {
            NSString *base64Part = nil;
            if ([blobIDString containsString:@".sha256"]) {
                base64Part = [[blobIDString substringFromIndex:1] stringByReplacingOccurrencesOfString:@".sha256" withString:@""];
            } else {
                base64Part = [blobIDString substringFromIndex:1];
            }
            NSData *decoded = [self dataFromBase64URLEncodedString:base64Part];
            if (decoded.length > 0) {
                hashData = decoded;
            }
        } else {
            hashData = [self dataFromBase64URLEncodedString:blobIDString];
        }
    } else if ([blobID isKindOfClass:[NSData class]]) {
        hashData = (NSData *)blobID;
    }
    
    if (!hashData || hashData.length == 0) {
        return nil;
    }
    
    if (hashData.length != 32) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeBlob;
    uint8_t formatByte = (uint8_t)SSBBFEBlobFormatClassic;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:hashData];
    
    return bfeData;
}

#pragma mark - Encryption Key Encoding

+ (nullable NSData *)encodeEncryptionKey:(NSData *)key format:(SSBBFEEncryptionKeyFormat)format {
    if (!key || key.length != 32) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeEncryptionKey;
    uint8_t formatByte = (uint8_t)format;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:key];
    
    return bfeData;
}

#pragma mark - Signature Encoding

+ (nullable NSData *)encodeSignature:(NSData *)signature {
    if (!signature || signature.length != 64) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeSignature;
    uint8_t formatByte = (uint8_t)SSBBFESignatureFormatMsgEd25519;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:signature];
    
    return bfeData;
}

#pragma mark - Encrypted Data Encoding

+ (nullable NSData *)encodeEncrypted:(NSData *)ciphertext format:(SSBBFEEncryptedFormat)format {
    if (!ciphertext || ciphertext.length == 0) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeEncrypted;
    uint8_t formatByte = (uint8_t)format;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:ciphertext];
    
    return bfeData;
}

#pragma mark - Generic Data Encoding

+ (nullable NSData *)encodeGenericString:(NSString *)string {
    if (!string) {
        return nil;
    }
    
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!stringData) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeGeneric;
    uint8_t formatByte = (uint8_t)SSBBFEGenericFormatString;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:stringData];
    
    return bfeData;
}

+ (nullable NSData *)encodeBoolean:(BOOL)value {
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeGeneric;
    uint8_t formatByte = (uint8_t)SSBBFEGenericFormatBoolean;
    uint8_t dataByte = value ? 1 : 0;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendBytes:&dataByte length:1];
    
    return bfeData;
}

+ (nullable NSData *)encodeNil {
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeGeneric;
    uint8_t formatByte = (uint8_t)SSBBFEGenericFormatNil;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    
    return bfeData;
}

+ (nullable NSData *)encodeGenericBytes:(NSData *)bytes {
    if (!bytes) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeGeneric;
    uint8_t formatByte = (uint8_t)SSBBFEGenericFormatBytes;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:bytes];
    
    return bfeData;
}

#pragma mark - Identity Encoding

+ (nullable NSData *)encodeIdentityPoBox:(NSData *)data {
    if (!data || data.length != 32) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeIdentity;
    uint8_t formatByte = (uint8_t)SSBBFEIdentityFormatPoBox;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:data];
    
    return bfeData;
}

+ (nullable NSData *)encodeIdentityGroup:(NSData *)data {
    if (!data || data.length != 32) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    uint8_t typeByte = (uint8_t)SSBBFETypeIdentity;
    uint8_t formatByte = (uint8_t)SSBBFEIdentityFormatGroup;
    [bfeData appendBytes:&typeByte length:1];
    [bfeData appendBytes:&formatByte length:1];
    [bfeData appendData:data];
    
    return bfeData;
}

#pragma mark - Decoding

+ (nullable id)decodeBFEData:(NSData *)bfeData {
    return [self decode:bfeData type:nil format:nil];
}

+ (nullable id)decode:(NSData *)bfeData type:(SSBBFEType *)outType format:(NSInteger *)outFormat {
    if (!bfeData || bfeData.length < 2) {
        return nil;
    }
    
    const uint8_t *bytes = bfeData.bytes;
    uint8_t typeByte = bytes[0];
    uint8_t formatByte = bytes[1];
    
    if (outType) {
        *outType = (SSBBFEType)typeByte;
    }
    if (outFormat) {
        *outFormat = formatByte;
    }
    
    NSData *data = [bfeData subdataWithRange:NSMakeRange(2, bfeData.length - 2)];
    
    switch (typeByte) {
        case SSBBFETypeFeed:
        case SSBBFETypeMessage:
        case SSBBFETypeBlob:
        case SSBBFETypeEncryptionKey:
        case SSBBFETypeIdentity:
            return data;
            
        case SSBBFETypeSignature:
            return data;
            
        case SSBBFETypeEncrypted:
            return data;
            
        case SSBBFETypeGeneric:
            switch (formatByte) {
                case SSBBFEGenericFormatString:
                    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                case SSBBFEGenericFormatBoolean:
                    if (data.length >= 1) {
                        return @(((const uint8_t *)data.bytes)[0] != 0);
                    }
                    return @NO;
                case SSBBFEGenericFormatNil:
                    return [NSNull null];
                case SSBBFEGenericFormatBytes:
                    return data;
                default:
                    return data;
            }
            
        default:
            return data;
    }
}

#pragma mark - Type Detection

+ (SSBBFEType)detectType:(NSData *)bfeData {
    if (!bfeData || bfeData.length < 1) {
        return (SSBBFEType)-1;
    }
    
    const uint8_t *bytes = bfeData.bytes;
    return (SSBBFEType)bytes[0];
}

+ (NSInteger)detectFormat:(NSData *)bfeData {
    if (!bfeData || bfeData.length < 2) {
        return -1;
    }
    
    const uint8_t *bytes = bfeData.bytes;
    return bytes[1];
}

#pragma mark - Sigil String Conversion

+ (nullable NSString *)sigilStringFromBFE:(NSData *)bfeData {
    if (!bfeData || bfeData.length < 2) {
        return nil;
    }
    
    const uint8_t *bytes = bfeData.bytes;
    uint8_t typeByte = bytes[0];
    uint8_t formatByte = bytes[1];
    
    NSData *data = [bfeData subdataWithRange:NSMakeRange(2, bfeData.length - 2)];
    NSString *base64 = [self base64URLEncodedStringFromData:data];
    
    if (!base64) {
        return nil;
    }
    
    switch (typeByte) {
        case SSBBFETypeFeed:
            switch (formatByte) {
                case SSBBFEFeedFormatClassic:
                    return [NSString stringWithFormat:@"@%@.ed25519", base64];
                case SSBBFEFeedFormatGabbygroveV1:
                    return [NSString stringWithFormat:@"@%@.ggfeed-v1", base64];
                case SSBBFEFeedFormatBamboo:
                    return [NSString stringWithFormat:@"@%@.bamboo", base64];
                case SSBBFEFeedFormatBendybuttV1:
                    return [NSString stringWithFormat:@"@%@.bbfeed-v1", base64];
                case SSBBFEFeedFormatButtwooV1:
                    return [NSString stringWithFormat:@"@%@.buttwoo-v1", base64];
                case SSBBFEFeedFormatIndexedV1:
                    return [NSString stringWithFormat:@"@%@.indexedfeed-v1", base64];
                default:
                    return [NSString stringWithFormat:@"@%@", base64];
            }
            
        case SSBBFETypeMessage:
            switch (formatByte) {
                case SSBBFEMessageFormatClassic:
                    return [NSString stringWithFormat:@"%%%@.sha256", base64];
                case SSBBFEMessageFormatGabbygroveV1:
                    return [NSString stringWithFormat:@"%%%@.ggmsg-v1", base64];
                case SSBBFEMessageFormatCloaked:
                    return [NSString stringWithFormat:@"%%%@.cloaked", base64];
                case SSBBFEMessageFormatBamboo:
                    return [NSString stringWithFormat:@"%%%@.bamboo", base64];
                case SSBBFEMessageFormatBendybuttV1:
                    return [NSString stringWithFormat:@"%%%@.bbmsg-v1", base64];
                case SSBBFEMessageFormatButtwooV1:
                    return [NSString stringWithFormat:@"%%%@.buttwoo-v1", base64];
                case SSBBFEMessageFormatIndexedV1:
                    return [NSString stringWithFormat:@"%%%@.indexedmsg-v1", base64];
                default:
                    return [NSString stringWithFormat:@"%%%@", base64];
            }
            
        case SSBBFETypeBlob:
            return [NSString stringWithFormat:@"&%@.sha256", base64];
            
        default:
            return base64;
    }
}

+ (nullable NSData *)bfeDataFromSigilString:(NSString *)sigilString {
    if (!sigilString || sigilString.length < 2) {
        return nil;
    }
    
    unichar sigil = [sigilString characterAtIndex:0];
    NSString *remainder = [sigilString substringFromIndex:1];
    NSString *suffix = @"";
    NSString *base64Part = remainder;
    
    if ([remainder containsString:@"."]) {
        NSRange lastDotRange = [remainder rangeOfString:@"." options:NSBackwardsSearch];
        suffix = [remainder substringFromIndex:lastDotRange.location];
        base64Part = [remainder substringToIndex:lastDotRange.location];
    }
    
    NSData *data = [self dataFromBase64URLEncodedString:base64Part];
    if (!data) {
        return nil;
    }
    
    NSMutableData *bfeData = [NSMutableData data];
    
    switch (sigil) {
        case '@': {
            uint8_t typeByte = (uint8_t)SSBBFETypeFeed;
            uint8_t formatByte = 0;
            
            if ([suffix isEqualToString:@".ed25519"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatClassic;
            } else if ([suffix isEqualToString:@".ggfeed-v1"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatGabbygroveV1;
            } else if ([suffix isEqualToString:@".bamboo"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatBamboo;
            } else if ([suffix isEqualToString:@".bbfeed-v1"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatBendybuttV1;
            } else if ([suffix isEqualToString:@".buttwoo-v1"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatButtwooV1;
            } else if ([suffix isEqualToString:@".indexedfeed-v1"]) {
                formatByte = (uint8_t)SSBBFEFeedFormatIndexedV1;
            }
            
            [bfeData appendBytes:&typeByte length:1];
            [bfeData appendBytes:&formatByte length:1];
            [bfeData appendData:data];
            break;
        }
            
        case '%': {
            uint8_t typeByte = (uint8_t)SSBBFETypeMessage;
            uint8_t formatByte = 0;
            
            if ([suffix isEqualToString:@".sha256"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatClassic;
            } else if ([suffix isEqualToString:@".ggmsg-v1"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatGabbygroveV1;
            } else if ([suffix isEqualToString:@".cloaked"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatCloaked;
            } else if ([suffix isEqualToString:@".bamboo"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatBamboo;
            } else if ([suffix isEqualToString:@".bbmsg-v1"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatBendybuttV1;
            } else if ([suffix isEqualToString:@".buttwoo-v1"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatButtwooV1;
            } else if ([suffix isEqualToString:@".indexedmsg-v1"]) {
                formatByte = (uint8_t)SSBBFEMessageFormatIndexedV1;
            }
            
            [bfeData appendBytes:&typeByte length:1];
            [bfeData appendBytes:&formatByte length:1];
            [bfeData appendData:data];
            break;
        }
            
        case '&': {
            uint8_t typeByte = (uint8_t)SSBBFETypeBlob;
            uint8_t formatByte = (uint8_t)SSBBFEBlobFormatClassic;
            [bfeData appendBytes:&typeByte length:1];
            [bfeData appendBytes:&formatByte length:1];
            [bfeData appendData:data];
            break;
        }
            
        default:
            return nil;
    }
    
    return bfeData;
}

#pragma mark - Base64 URL Encoding

+ (NSString *)base64URLEncodedStringFromData:(NSData *)data {
    if (!data) {
        return nil;
    }
    
    NSString *standardBase64 = [data base64EncodedStringWithOptions:0];
    
    NSString *urlSafe = [[standardBase64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
                         stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    
    urlSafe = [urlSafe stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    return urlSafe;
}

+ (nullable NSData *)dataFromBase64URLEncodedString:(NSString *)base64URLString {
    if (!base64URLString || base64URLString.length == 0) {
        return nil;
    }
    
    NSMutableString *standardBase64 = [base64URLString mutableCopy];
    
    [standardBase64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, standardBase64.length)];
    [standardBase64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, standardBase64.length)];
    
    while (standardBase64.length % 4 != 0) {
        [standardBase64 appendString:@"="];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:standardBase64 options:0];
}

@end
