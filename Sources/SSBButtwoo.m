#import "SSBButtwoo.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBBencode.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonDigest.h>

// Buttwoo wire format (bencode):
//   Message = [payload, signature_bfe]
//   Payload = [author_bfe, sequence, previous_bfe, timestamp, content_data]
//
// Author BFE:   type=0x00 (Feed), format=0x04 (SSBBFEFeedFormatButtwooV1) + 32-byte key
// Previous BFE: type=0x01 (Message), format=0x05 (SSBBFEMessageFormatButtwooV1) + 32-byte hash,
//               or BFE nil (type=0x06 format=0x02)
//
// Signature BFE: type=0x04 (Signature), format=0x00 + 64-byte Ed25519 signature over payload bytes

static const NSUInteger kMaxMessageSize = 8192;

@implementation SSBButtwoo

#pragma mark - SSBFeedCodec Registration

+ (void)load {
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:[self sharedCodec]];
}

+ (instancetype)sharedCodec {
    static SSBButtwoo *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBButtwoo alloc] init];
    });
    return instance;
}

#pragma mark - SSBFeedCodec Protocol

- (SSBBFEFeedFormat)feedFormat {
    return SSBBFEFeedFormatButtwooV1;
}

- (SSBBFEMessageFormat)messageFormat {
    return SSBBFEMessageFormatButtwooV1;
}

- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error {
    BOOL valid = [SSBButtwoo validateMessage:messageData];
    if (!valid && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"Buttwoo message invalid or signature mismatch"}];
    }
    return valid;
}

- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error {
    NSData *key = [SSBButtwoo computeMessageKey:messageData];
    if (!key && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:2
                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute Buttwoo message key"}];
    }
    return key;
}

#pragma mark - Deterministic Key

+ (nullable NSData *)computeDeterministicKey:(NSData *)authorPublicKey sequence:(NSInteger)sequence {
    if (!authorPublicKey || authorPublicKey.length != 32) {
        return nil;
    }
    if (sequence < 1) {
        return nil;
    }

    // Concatenate 32-byte author pubkey + 8-byte big-endian sequence number
    NSMutableData *input = [NSMutableData dataWithData:authorPublicKey];
    uint64_t seqBE = CFSwapInt64HostToBig((uint64_t)sequence);
    [input appendBytes:&seqBE length:8];

    // SHA-256 of the 40-byte input (stand-in for BLAKE2b)
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);

    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Message Validation

+ (BOOL)validateMessage:(NSData *)messageData {
    if (!messageData || messageData.length == 0) {
        return NO;
    }

    if (messageData.length > kMaxMessageSize) {
        return NO;
    }

    // Parse the outer bencode list: [payload, signature_bfe]
    NSUInteger offset = 0;
    id decoded = [SSBBencode decode:messageData offset:&offset];
    if (![decoded isKindOfClass:[NSArray class]]) {
        return NO;
    }

    NSArray *message = (NSArray *)decoded;
    if (message.count != 2) {
        return NO;
    }

    // payload is bencode-encoded bytes (NSData), sig_bfe is NSData
    NSData *payloadData  = message[0];
    NSData *signatureBFE = message[1];

    if (![payloadData isKindOfClass:[NSData class]] ||
        ![signatureBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    // Parse payload: [author_bfe, seq, prev_bfe, timestamp, content]
    NSUInteger payloadOffset = 0;
    id payloadDecoded = [SSBBencode decode:payloadData offset:&payloadOffset];
    if (![payloadDecoded isKindOfClass:[NSArray class]]) {
        return NO;
    }

    NSArray *payload = (NSArray *)payloadDecoded;
    if (payload.count != 5) {
        return NO;
    }

    NSData   *authorBFE   = payload[0];
    NSNumber *sequenceNum = payload[1];
    NSData   *previousBFE = payload[2];
    id        timestamp   = payload[3];
    id        content     = payload[4];

    if (![authorBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    if (![sequenceNum isKindOfClass:[NSNumber class]] || sequenceNum.integerValue < 1) {
        return NO;
    }

    if (![previousBFE isKindOfClass:[NSData class]]) {
        return NO;
    }

    if (![timestamp isKindOfClass:[NSNumber class]]) {
        return NO;
    }

    // content can be any bencode value (NSData, NSNumber, NSArray, NSDictionary)
    if (!content) {
        return NO;
    }

    // Author must be BFE feed with format SSBBFEFeedFormatButtwooV1 (type 0x00, format 0x04)
    SSBBFEType authorType     = [SSBBFE detectType:authorBFE];
    NSInteger  authorFormat   = [SSBBFE detectFormat:authorBFE];
    if (authorType != SSBBFETypeFeed || authorFormat != SSBBFEFeedFormatButtwooV1) {
        return NO;
    }

    // Author BFE must contain exactly 32 bytes of key after the 2-byte type/format prefix
    if (authorBFE.length != 34) {
        return NO;
    }

    // Previous must be BFE message format Buttwoo or BFE nil
    SSBBFEType prevType   = [SSBBFE detectType:previousBFE];
    NSInteger  prevFormat = [SSBBFE detectFormat:previousBFE];
    BOOL prevIsNil = (prevType == SSBBFETypeGeneric && prevFormat == SSBBFEGenericFormatNil);
    BOOL prevIsMsg = (prevType == SSBBFETypeMessage && prevFormat == SSBBFEMessageFormatButtwooV1);
    if (!prevIsNil && !prevIsMsg) {
        return NO;
    }

    // Extract 32-byte author key from BFE (bytes 2-33)
    NSData *authorKey = [authorBFE subdataWithRange:NSMakeRange(2, 32)];

    // Signature BFE: type=0x04 (Signature), format=0x00, followed by 64-byte signature
    SSBBFEType sigType = [SSBBFE detectType:signatureBFE];
    if (sigType != SSBBFETypeSignature) {
        return NO;
    }

    if (signatureBFE.length < 2 + crypto_sign_BYTES) {
        return NO;
    }

    NSData *signature = [signatureBFE subdataWithRange:NSMakeRange(2, crypto_sign_BYTES)];

    // Verify Ed25519 signature on payload bytes using tweetnacl crypto_sign_open
    // crypto_sign_open expects: sm = signature || message
    NSMutableData *sm = [NSMutableData dataWithData:signature];
    [sm appendData:payloadData];

    unsigned char m[sm.length];
    unsigned long long mlen = 0;
    int ret = crypto_sign_open(m, &mlen,
                               (const unsigned char *)sm.bytes,
                               (unsigned long long)sm.length,
                               (const unsigned char *)authorKey.bytes);
    if (ret != 0) {
        return NO;
    }

    if (mlen != payloadData.length) {
        return NO;
    }

    return memcmp(m, payloadData.bytes, payloadData.length) == 0;
}

#pragma mark - Message Key

+ (nullable NSData *)computeMessageKey:(NSData *)messageData {
    if (!messageData || messageData.length == 0) {
        return nil;
    }

    if (messageData.length > kMaxMessageSize) {
        return nil;
    }

    // Parse outer message to extract payload
    NSUInteger offset = 0;
    id decoded = [SSBBencode decode:messageData offset:&offset];
    if (![decoded isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSArray *message = (NSArray *)decoded;
    if (message.count < 1) {
        return nil;
    }

    NSData *payloadData = message[0];
    if (![payloadData isKindOfClass:[NSData class]]) {
        return nil;
    }

    // Parse payload to extract author BFE and sequence number
    NSUInteger payloadOffset = 0;
    id payloadDecoded = [SSBBencode decode:payloadData offset:&payloadOffset];
    if (![payloadDecoded isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSArray *payload = (NSArray *)payloadDecoded;
    if (payload.count < 2) {
        return nil;
    }

    NSData   *authorBFE   = payload[0];
    NSNumber *sequenceNum = payload[1];

    if (![authorBFE isKindOfClass:[NSData class]] || authorBFE.length != 34) {
        return nil;
    }

    if (![sequenceNum isKindOfClass:[NSNumber class]] || sequenceNum.integerValue < 1) {
        return nil;
    }

    // Extract 32-byte author key from BFE (bytes 2-33)
    NSData *authorKey = [authorBFE subdataWithRange:NSMakeRange(2, 32)];

    return [self computeDeterministicKey:authorKey sequence:sequenceNum.integerValue];
}

@end
