#import "SSBBendyButt.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import "SSBCommonCryptoCompat.h"

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

#pragma mark - SSBFeedCodec Registration

+ (void)load {
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:[self sharedCodec]];
}

+ (instancetype)sharedCodec {
    static SSBBendyButt *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBBendyButt alloc] init];
    });
    return instance;
}

#pragma mark - SSBFeedCodec Protocol

- (SSBBFEFeedFormat)feedFormat {
    return SSBBFEFeedFormatBendybuttV1;
}

- (SSBBFEMessageFormat)messageFormat {
    return SSBBFEMessageFormatBendybuttV1;
}

- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error {
    BOOL valid = [SSBBendyButt validateMessage:messageData];
    if (!valid && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"BendyButt message invalid or signature mismatch"}];
    }
    return valid;
}

- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error {
    NSData *key = [SSBBendyButt computeMessageKey:messageData];
    if (!key && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:2
                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute BendyButt message key"}];
    }
    return key;
}

#pragma mark - Bencode pass-throughs (delegates to SSBBencode)

+ (nullable NSData *)encodeBencodeInteger:(NSInteger)value {
    return [SSBBencode encodeInteger:value];
}

+ (nullable NSData *)encodeBencodeString:(NSString *)string {
    return [SSBBencode encodeString:string];
}

+ (nullable NSData *)encodeBencodeData:(NSData *)data {
    return [SSBBencode encodeData:data];
}

+ (nullable NSData *)encodeBencodeList:(NSArray *)list {
    return [SSBBencode encodeList:list];
}

+ (nullable NSData *)encodeBencodeDict:(NSDictionary *)dict {
    return [SSBBencode encodeDict:dict];
}

+ (nullable id)decodeBencode:(NSData *)data offset:(NSUInteger *)offset {
    return [SSBBencode decode:data offset:offset];
}

#pragma mark - Initializer

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

    // Spec: key = SHA256([payload, signature]) — ssbc/bendy-butt-spec
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(messageData.bytes, (CC_LONG)messageData.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Content Signing

+ (nullable NSData *)signContent:(NSData *)content withKey:(NSData *)key {
    if (!content || !key) {
        return nil;
    }

    if (key.length == crypto_sign_SECRETKEYBYTES) {
        unsigned char signedMessage[crypto_sign_BYTES + content.length];
        unsigned long long signedLength = 0;
        int ret = crypto_sign(signedMessage, &signedLength,
                              content.bytes, (unsigned long long)content.length,
                              key.bytes);
        if (ret != 0 || signedLength < crypto_sign_BYTES) {
            return nil;
        }
        return [NSData dataWithBytes:signedMessage length:crypto_sign_BYTES];
    }

    if (key.length != 32) {
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
    if (!content || !author || author.length != 32) {
        return NO;
    }

    if (!signature) {
        return NO;
    }

    if (signature.length == crypto_sign_BYTES) {
        NSMutableData *signedMessage = [NSMutableData dataWithData:signature];
        [signedMessage appendData:content];
        unsigned char recovered[signedMessage.length];
        unsigned long long recoveredLen = 0;
        int ret = crypto_sign_open(recovered, &recoveredLen,
                                   signedMessage.bytes, (unsigned long long)signedMessage.length,
                                   author.bytes);
        if (ret != 0 || recoveredLen != content.length) {
            return NO;
        }
        return memcmp(recovered, content.bytes, content.length) == 0;
    }

    if (signature.length != 32) {
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

    NSData *rawSignature = [NSData dataWithBytes:signature length:crypto_sign_BYTES];
    return [SSBBFE encodeSignature:rawSignature];
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


@end
