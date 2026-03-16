#import "SSBGabbyGrove.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonCrypto.h>

// GabbyGrove protobuf field numbers
static const int kGGFieldAuthor       = 1; // bytes: Ed25519 public key (32 bytes)
static const int kGGFieldSequence     = 2; // varint: sequence number (1-based)
static const int kGGFieldPrevious     = 3; // bytes: previous message hash (32 bytes)
static const int kGGFieldLipmaa      = 4; // bytes: lipmaa link hash (32 bytes)
static const int kGGFieldContentHash  = 5; // bytes: HMAC-SHA256 of content (32 bytes)
static const int kGGFieldContent      = 6; // bytes: content
static const int kGGFieldIsEndOfFeed  = 7; // varint: 0=no, 1=yes
static const int kGGFieldSignature    = 8; // bytes: Ed25519 signature (64 bytes)

// Protobuf wire types
static const int kWireTypeVarint          = 0;
static const int kWireTypeLengthDelimited = 2;

@implementation SSBGabbyGrove

+ (void)load {
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:[SSBGabbyGrove sharedCodec]];
}

+ (instancetype)sharedCodec {
    static SSBGabbyGrove *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBGabbyGrove alloc] init];
    });
    return instance;
}

#pragma mark - SSBFeedCodec protocol

- (SSBBFEFeedFormat)feedFormat {
    return SSBBFEFeedFormatGabbygroveV1;
}

- (SSBBFEMessageFormat)messageFormat {
    return SSBBFEMessageFormatGabbygroveV1;
}

- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error {
    BOOL valid = [SSBGabbyGrove validateMessage:messageData];
    if (!valid && error) {
        *error = [NSError errorWithDomain:@"SSBGabbyGroveErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"GabbyGrove message validation failed: invalid structure or bad Ed25519 signature"}];
    }
    return valid;
}

- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error {
    NSData *key = [SSBGabbyGrove computeMessageKey:messageData];
    if (!key && error) {
        *error = [NSError errorWithDomain:@"SSBGabbyGroveErrorDomain"
                                     code:2
                                 userInfo:@{NSLocalizedDescriptionKey: @"GabbyGrove message key computation failed"}];
    }
    return key;
}

#pragma mark - Varint encoding (unsigned LEB128)

+ (void)appendVarint:(uint64_t)value toData:(NSMutableData *)data {
    do {
        uint8_t byte = value & 0x7F;
        value >>= 7;
        if (value != 0) {
            byte |= 0x80; // more bytes follow
        }
        [data appendBytes:&byte length:1];
    } while (value != 0);
}

+ (uint64_t)decodeVarintFrom:(const uint8_t *)bytes length:(NSUInteger)length offset:(NSUInteger *)offset {
    uint64_t result = 0;
    int shift = 0;
    NSUInteger pos = *offset;

    while (pos < length) {
        uint8_t byte = bytes[pos++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
            *offset = pos;
            return result;
        }
        if (shift >= 64) {
            // varint too long
            return 0;
        }
    }
    // truncated varint — do not advance offset
    return 0;
}

#pragma mark - BLAKE2b-256

// TODO: Replace SHA-256 with BLAKE2b-256 per RFC 7693 once a BLAKE2b dependency is added
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Lipmaa sequence

// Returns the lipmaa predecessor sequence number for sequence n (1-based).
// lipmaa(1) = 0 (no link needed)
// For n > 1, find the largest power of 3 <= (n-1), then return n - that power.
static uint64_t lipmaaSeq(uint64_t n) {
    if (n <= 1) return 0;
    uint64_t m = n - 1;
    // find largest power of 3 <= m
    uint64_t p = 1;
    while (p * 3 <= m) {
        p *= 3;
    }
    return n - p;
}

#pragma mark - Protobuf helpers

// Append a length-delimited protobuf field (wire type 2)
static void appendBytesField(NSMutableData *buf, int fieldNumber, const void *bytes, NSUInteger length) {
    uint64_t tag = ((uint64_t)fieldNumber << 3) | kWireTypeLengthDelimited;
    [SSBGabbyGrove appendVarint:tag toData:buf];
    [SSBGabbyGrove appendVarint:(uint64_t)length toData:buf];
    if (length > 0) {
        [buf appendBytes:bytes length:length];
    }
}

// Append a varint protobuf field (wire type 0)
static void appendVarintField(NSMutableData *buf, int fieldNumber, uint64_t value) {
    uint64_t tag = ((uint64_t)fieldNumber << 3) | kWireTypeVarint;
    [SSBGabbyGrove appendVarint:tag toData:buf];
    [SSBGabbyGrove appendVarint:value toData:buf];
}

#pragma mark - Message parsing

typedef struct {
    NSData *author;         // field 1: 32-byte Ed25519 pubkey
    uint64_t sequence;      // field 2: sequence number
    NSData *previous;       // field 3: 32-byte prev hash (nil for seq=1)
    NSData *lipmaa;         // field 4: 32-byte lipmaa hash (nil if same as previous)
    NSData *contentHash;    // field 5: 32-byte HMAC-SHA256
    NSData *content;        // field 6: content bytes
    uint64_t isEndOfFeed;   // field 7: 0 or 1
    NSData *signature;      // field 8: 64-byte Ed25519 signature
    NSUInteger signatureFieldOffset; // byte offset of start of field 8 tag in wire data
} GGMessage;

// Parse the wire-format protobuf into a GGMessage struct.
// Returns NO if parsing fails. signatureFieldOffset is set to the byte offset
// at which field 8 begins (used to extract the signed payload).
static BOOL parseMessage(NSData *data, GGMessage *msg) {
    memset(msg, 0, sizeof(*msg));
    msg->signatureFieldOffset = data.length; // default: no signature found

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    NSUInteger offset = 0;

    while (offset < length) {
        NSUInteger fieldStart = offset;
        uint64_t tag = [SSBGabbyGrove decodeVarintFrom:bytes length:length offset:&offset];
        if (offset == fieldStart) return NO; // failed to read tag

        int fieldNumber = (int)(tag >> 3);
        int wireType   = (int)(tag & 0x7);

        if (wireType == kWireTypeVarint) {
            NSUInteger valueStart = offset;
            uint64_t value = [SSBGabbyGrove decodeVarintFrom:bytes length:length offset:&offset];
            if (offset == valueStart) return NO;

            if (fieldNumber == kGGFieldSequence) {
                msg->sequence = value;
            } else if (fieldNumber == kGGFieldIsEndOfFeed) {
                msg->isEndOfFeed = value;
            }
            // Record offset of signature field tag
            if (fieldNumber == kGGFieldSignature) {
                msg->signatureFieldOffset = fieldStart;
            }
        } else if (wireType == kWireTypeLengthDelimited) {
            NSUInteger lenStart = offset;
            uint64_t fieldLen = [SSBGabbyGrove decodeVarintFrom:bytes length:length offset:&offset];
            if (offset == lenStart) return NO;
            if (offset + fieldLen > length) return NO;

            // Record offset of signature field tag before consuming bytes
            if (fieldNumber == kGGFieldSignature) {
                msg->signatureFieldOffset = fieldStart;
            }

            NSData *fieldData = [NSData dataWithBytesNoCopy:(void *)(bytes + offset)
                                                     length:(NSUInteger)fieldLen
                                               freeWhenDone:NO];
            switch (fieldNumber) {
                case kGGFieldAuthor:      msg->author      = fieldData; break;
                case kGGFieldPrevious:    msg->previous    = fieldData; break;
                case kGGFieldLipmaa:     msg->lipmaa     = fieldData; break;
                case kGGFieldContentHash: msg->contentHash = fieldData; break;
                case kGGFieldContent:     msg->content     = fieldData; break;
                case kGGFieldSignature:   msg->signature   = fieldData; break;
                default: break; // unknown field, skip
            }
            offset += (NSUInteger)fieldLen;
        } else {
            // Unsupported wire type — treat as parse failure
            return NO;
        }
    }
    return YES;
}

#pragma mark - Validation

+ (BOOL)validateMessage:(NSData *)messageData {
    if (!messageData || messageData.length == 0) return NO;

    GGMessage msg;
    if (!parseMessage(messageData, &msg)) return NO;

    // Structural checks
    if (!msg.author || msg.author.length != 32) return NO;
    if (msg.sequence < 1) return NO;
    if (!msg.signature || msg.signature.length != 64) return NO;

    // For seq > 1, previous must be present and 32 bytes
    if (msg.sequence > 1) {
        if (!msg.previous || msg.previous.length != 32) return NO;
    }

    // Lipmaa link: if lipmaa seq != previous seq, lipmaa must be present
    uint64_t lipmaaSeqNum = lipmaaSeq(msg.sequence);
    if (msg.sequence > 1 && lipmaaSeqNum != msg.sequence - 1) {
        // Lipmaa diverges from previous — field 4 should be present
        if (!msg.lipmaa || msg.lipmaa.length != 32) return NO;
    }

    // Content hash must be present and 32 bytes
    if (!msg.contentHash || msg.contentHash.length != 32) return NO;

    // The signed payload is all bytes before field 8 (the signature field)
    if (msg.signatureFieldOffset == 0 || msg.signatureFieldOffset > messageData.length) return NO;
    NSData *signedPayload = [messageData subdataWithRange:NSMakeRange(0, msg.signatureFieldOffset)];

    // Ed25519 signature verification using tweetnacl.
    // crypto_sign_open expects: signed message = signature (64 bytes) || message
    NSUInteger smLength = 64 + signedPayload.length;
    uint8_t *sm = (uint8_t *)malloc(smLength);
    if (!sm) return NO;

    memcpy(sm, msg.signature.bytes, 64);
    memcpy(sm + 64, signedPayload.bytes, signedPayload.length);

    uint8_t *opened = (uint8_t *)malloc(smLength);
    if (!opened) {
        free(sm);
        return NO;
    }

    unsigned long long openedLen = 0;
    int result = crypto_sign_open(opened, &openedLen, sm, (unsigned long long)smLength,
                                  (const unsigned char *)msg.author.bytes);

    free(sm);
    free(opened);

    return (result == 0);
}

#pragma mark - Message key

+ (nullable NSData *)computeMessageKey:(NSData *)messageData {
    if (!messageData || messageData.length == 0) return nil;
    return [SSBGabbyGrove blake2b256:messageData];
}

@end
