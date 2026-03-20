#import "SSBBamboo.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import "blake2b.h"
#ifndef __APPLE__
#include <arpa/inet.h>
static inline uint64_t CFSwapInt64BigToHost(uint64_t x) {
    return be64toh(x);
}
#endif

// Bamboo binary entry layout (seq > 1):
//   author_public_key   bytes  0-31   (32 bytes, Ed25519 public key)
//   log_id              bytes 32-63   (32 bytes, log identifier)
//   is_end_of_log       byte  64      (1 byte, 0=no 1=yes)
//   lipmaa_link         bytes 65-96   (32 bytes, hash of lipmaa entry; absent if seq==1 or lipmaa==prev)
//   backlink            bytes 97-128  (32 bytes, hash of previous entry; absent if seq==1)
//   seq_number          bytes 65-72 (seq==1) or 129-136 (seq>1, with both links)  (8 bytes, big-endian uint64)
//   payload_hash        32 bytes
//   payload_size         8 bytes (big-endian uint64)
//   signature           64 bytes (Ed25519, signs all preceding fields)
//
// Per the task spec the layout for seq > 1 is:
//   [0-31]   author (32)
//   [32-63]  log_id (32)
//   [64]     is_end_of_log (1)
//   [65-96]  lipmaa_link (32)   -- only when seq > 1 AND lipmaa != previous
//   [97-128] backlink (32)      -- only when seq > 1
//   [129-136] seq_number (8)    -- big-endian uint64
//   ... BUT the spec description in the task says for seq==1 lipmaa_link and
//   backlink are absent, and gives concrete byte offsets. We follow those exactly.
//
// Concrete offsets from task spec:
//   For seq > 1:
//     author 0-31, log_id 32-63, is_end 64,
//     lipmaa_link 73-104, backlink 105-136,
//     seq_number 65-72 (NOTE: spec lists seq before links for both layouts;
//     re-reading: "seq_number (bytes 65-72 big-endian)" applies to BOTH cases,
//     so seq is at 65 always, then links follow at 73+)
//     payload_hash 137-168, payload_size 169-176, sig 177-240
//   For seq == 1:
//     no lipmaa_link, no backlink
//     payload_hash 73-104, payload_size 105-112, sig 113-176
//
// Minimum sizes:
//   seq==1:  32+32+1+8+32+8+64 = 177 bytes
//   seq>1 (both links): 32+32+1+8+32+32+32+8+64 = 241 bytes

static const NSUInteger kBambooMinSize = 177;

// Field offsets common to both seq==1 and seq>1
static const NSUInteger kAuthorOffset       = 0;   // 32 bytes
static const NSUInteger kLogIDOffset        = 32;  // 32 bytes
static const NSUInteger kIsEndOffset        = 64;  // 1 byte
static const NSUInteger kSeqOffset          = 65;  // 8 bytes (big-endian uint64)

// seq > 1 offsets (both lipmaa and backlink present)
static const NSUInteger kLipmaaLinkOffset   = 73;  // 32 bytes
static const NSUInteger kBacklinkOffset     = 105; // 32 bytes
static const NSUInteger kPayloadHashSeqN    = 137; // 32 bytes
static const NSUInteger kPayloadSizeSeqN    = 169; // 8 bytes
static const NSUInteger kSigOffsetSeqN      = 177; // 64 bytes

// seq == 1 offsets (no links)
static const NSUInteger kPayloadHashSeq1    = 73;  // 32 bytes
static const NSUInteger kPayloadSizeSeq1    = 105; // 8 bytes
static const NSUInteger kSigOffsetSeq1      = 113; // 64 bytes

@implementation SSBBambooProof
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_targetMessage forKey:@"targetMessage"];
    [coder encodeObject:_lipmaaPath forKey:@"lipmaaPath"];
    [coder encodeObject:_rootHash forKey:@"rootHash"];
    [coder encodeObject:_authorPubKey forKey:@"authorPubKey"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _targetMessage = [coder decodeObjectOfClass:[NSData class] forKey:@"targetMessage"];
        _lipmaaPath = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSData class], nil] forKey:@"lipmaaPath"];
        _rootHash = [coder decodeObjectOfClass:[NSData class] forKey:@"rootHash"];
        _authorPubKey = [coder decodeObjectOfClass:[NSData class] forKey:@"authorPubKey"];
    }
    return self;
}
@end

@implementation SSBBamboo

+ (void)load {
    [[SSBFeedCodecRegistry sharedRegistry] registerCodec:[self sharedCodec]];
}

+ (instancetype)sharedCodec {
    static SSBBamboo *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSBBamboo alloc] init];
    });
    return instance;
}

@synthesize feedFormat = _feedFormat;
@synthesize messageFormat = _messageFormat;

- (SSBBFEFeedFormat)feedFormat {
    return SSBBFEFeedFormatBamboo;
}

- (SSBBFEMessageFormat)messageFormat {
    return SSBBFEMessageFormatBamboo;
}

- (BOOL)verifyMessageData:(NSData *)messageData error:(NSError **)error {
    BOOL valid = [SSBBamboo validateEntry:messageData];
    if (!valid && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:1
                                userInfo:@{NSLocalizedDescriptionKey: @"Bamboo entry invalid or signature mismatch"}];
    }
    return valid;
}

- (nullable NSData *)computeMessageKeyFromData:(NSData *)messageData error:(NSError **)error {
    NSData *key = [SSBBamboo computeEntryID:messageData];
    if (!key && error) {
        *error = [NSError errorWithDomain:@"SSBFeedCodec" code:2
                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to compute Bamboo entry ID"}];
    }
    return key;
}

#pragma mark - Lipmaa

+ (NSInteger)lipmaaSequenceFor:(NSInteger)seq {
    if (seq <= 1) {
        return 1;
    }

    NSInteger largestPowerOfThreeBelowSeq = 1;
    while (largestPowerOfThreeBelowSeq <= (NSIntegerMax / 3) &&
           largestPowerOfThreeBelowSeq * 3 < seq) {
        largestPowerOfThreeBelowSeq *= 3;
    }

    return MAX(1, seq - largestPowerOfThreeBelowSeq);
}

#pragma mark - Hashing

+ (nullable NSData *)hashData:(NSData *)data {
    if (!data) {
        return nil;
    }

    uint8_t hash[32];
    if (blake2b256(hash, data.bytes, data.length) != 0) return nil;
    return [NSData dataWithBytes:hash length:sizeof(hash)];
}

#pragma mark - Entry Validation

+ (BOOL)validateEntry:(NSData *)entryData {
    if (!entryData) return NO;
    if (entryData.length < kBambooMinSize) return NO;
    const uint8_t *bytes = (const uint8_t *)entryData.bytes;
    if (bytes[kIsEndOffset] != 0 && bytes[kIsEndOffset] != 1) return NO;
    uint64_t seqBE = 0;
    memcpy(&seqBE, bytes + kSeqOffset, 8);
    uint64_t seq = CFSwapInt64BigToHost(seqBE);
    if (seq < 1) return NO;
    BOOL hasLinks = (seq > 1);
    NSUInteger expectedSize = hasLinks ? 241 : 177;
    if (entryData.length != expectedSize) return NO;
    uint64_t payloadSizeBE = 0;
    memcpy(&payloadSizeBE, bytes + (hasLinks ? kPayloadSizeSeqN : kPayloadSizeSeq1), 8);
    uint64_t payloadSize = CFSwapInt64BigToHost(payloadSizeBE);
    if (payloadSize > 65536) return NO;
    NSUInteger sigOffset = hasLinks ? kSigOffsetSeqN : kSigOffsetSeq1;
    NSData *author = [entryData subdataWithRange:NSMakeRange(kAuthorOffset, 32)];
    NSData *signature = [entryData subdataWithRange:NSMakeRange(sigOffset, 64)];
    NSData *signedData = [entryData subdataWithRange:NSMakeRange(0, sigOffset)];
    return [self verifySignature:signature forData:signedData withAuthor:author];
}

+ (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data withAuthor:(NSData *)author {
    if (signature.length != 64 || author.length != 32) return NO;
    NSUInteger signedMessageLength = signature.length + data.length;
    uint8_t *signedMessage = (uint8_t *)malloc(signedMessageLength);
    if (!signedMessage) {
        return NO;
    }

    memcpy(signedMessage, signature.bytes, signature.length);
    memcpy(signedMessage + signature.length, data.bytes, data.length);

    uint8_t *opened = (uint8_t *)malloc(signedMessageLength);
    if (!opened) {
        free(signedMessage);
        return NO;
    }

    unsigned long long openedLength = 0;
    int ret = crypto_sign_open(opened,
                               &openedLength,
                               signedMessage,
                               (unsigned long long)signedMessageLength,
                               author.bytes);

    free(signedMessage);
    free(opened);

    return (ret == 0 && openedLength == data.length);
}

#pragma mark - Entry ID

+ (nullable NSData *)computeEntryID:(NSData *)entryData {
    if (![self validateEntry:entryData]) {
        return nil;
    }
    return [self hashData:entryData];
}

#pragma mark - Lipmaa Proofs

+ (BOOL)verifyProof:(SSBBambooProof *)proof error:(NSError **)error {
    // 1. Verify target message signature
    if (![self validateEntry:proof.targetMessage]) {
        if (error) *error = [NSError errorWithDomain:@"SSBBamboo" code:101 userInfo:@{NSLocalizedDescriptionKey: @"Invalid target message signature"}];
        return NO;
    }

    // 2. Compute Target ID
    NSData *currentID = [self computeEntryID:proof.targetMessage];
    
    // 3. Extract sequence and Lipmaa link from target
    const uint8_t *bytes = (const uint8_t *)proof.targetMessage.bytes;
    uint64_t seqBE = 0;
    memcpy(&seqBE, bytes + kSeqOffset, 8);
    uint64_t targetSeq = CFSwapInt64BigToHost(seqBE);
    
    if (targetSeq == 1) {
        // Root message is its own proof
        return [currentID isEqualToData:proof.rootHash];
    }

    // 4. Verify Lipmaa Path
    // Each hash in proof.lipmaaPath must be the lipmaa_link of the message that follows it.
    // In a QR-optimized proof, we provide the hashes of the skip-targets.
    
    NSData *expectedLipmaaLink = [self extractLipmaaLink:proof.targetMessage];
    if (!expectedLipmaaLink) {
         if (error) *error = [NSError errorWithDomain:@"SSBBamboo" code:102 userInfo:@{NSLocalizedDescriptionKey: @"Missing Lipmaa link in target message"}];
         return NO;
    }

    // In this implementation, we verify that the first hash in the path matches the target's lipmaa_link,
    // and the last hash in the path matches the rootHash.
    if (proof.lipmaaPath.count == 0) {
        return [expectedLipmaaLink isEqualToData:proof.rootHash];
    }

    if (![proof.lipmaaPath.firstObject isEqualToData:expectedLipmaaLink]) {
         if (error) *error = [NSError errorWithDomain:@"SSBBamboo" code:103 userInfo:@{NSLocalizedDescriptionKey: @"Lipmaa path mismatch"}];
         return NO;
    }

    if (![proof.lipmaaPath.lastObject isEqualToData:proof.rootHash]) {
         if (error) *error = [NSError errorWithDomain:@"SSBBamboo" code:104 userInfo:@{NSLocalizedDescriptionKey: @"Lipmaa path does not terminate at root"}];
         return NO;
    }

    return YES;
}

+ (nullable NSData *)extractLipmaaLink:(NSData *)entryData {
    if (entryData.length < kPayloadHashSeqN) return nil;
    const uint8_t *bytes = (const uint8_t *)entryData.bytes;
    uint64_t seqBE = 0;
    memcpy(&seqBE, bytes + kSeqOffset, 8);
    uint64_t seq = CFSwapInt64BigToHost(seqBE);
    if (seq <= 1) return nil;
    return [entryData subdataWithRange:NSMakeRange(kLipmaaLinkOffset, 32)];
}

+ (nullable NSData *)serializeProof:(SSBBambooProof *)proof {
#if __has_include(<os/log.h>)
    return [NSKeyedArchiver archivedDataWithRootObject:proof requiringSecureCoding:YES error:nil];
#else
    return [NSKeyedArchiver archivedDataWithRootObject:proof];
#endif
}

+ (nullable SSBBambooProof *)deserializeProof:(NSData *)data {
#if __has_include(<os/log.h>)
    return [NSKeyedUnarchiver unarchivedObjectOfClass:[SSBBambooProof class] fromData:data error:nil];
#else
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
#endif
}

@end
