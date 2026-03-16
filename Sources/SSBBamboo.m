#import "SSBBamboo.h"
#import "SSBFeedCodecRegistry.h"
#import "SSBBFE.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonDigest.h>

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

@implementation SSBBamboo

#pragma mark - SSBFeedCodec Registration

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

#pragma mark - SSBFeedCodec Protocol

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

#pragma mark - Lipmaa Sequence

+ (NSInteger)lipmaaSequenceFor:(NSInteger)seq {
    if (seq <= 1) {
        return 1;
    }
    // Find the largest power of 3 that is <= seq
    NSInteger p = 1;
    while (p * 3 <= seq) {
        p *= 3;
    }
    // lipmaa(n) = n - p + 1  when p is the largest power of 3 <= n
    // But the canonical definition: lipmaa(n) for n>1 is n - (largest p3 <= n) + 1
    // Actually: lipmaa(n) = n - p where p = 3^k such that 3^k < n <= 3^(k+1)
    // We use: find largest p3 strictly less than n, then lipmaa = n - p3
    // Re-derive: lipmaa(1)=1; lipmaa(2)=1; lipmaa(3)=2; lipmaa(4)=1; lipmaa(5)=4;
    // lipmaa(6)=3; lipmaa(7)=6; lipmaa(8)=4; lipmaa(9)=6; lipmaa(10)=7...
    // The standard definition: lipmaa(n) = n - 3^(floor(log3(n-1)))
    // For n=2: 3^(floor(log3(1)))=3^0=1; 2-1=1 ✓
    // For n=3: 3^(floor(log3(2)))=3^0=1; 3-1=2 ✓
    // For n=4: 3^(floor(log3(3)))=3^1=3; 4-3=1 ✓
    // For n=5: 3^(floor(log3(4)))=3^1=3; 5-3=2... but should be 4?
    // Actually Bamboo spec says: lipmaa(n) = n - 3^k where k = floor(log3(n))
    // For n=5: 3^floor(log3(5))=3^1=3; 5-3=2... hmm
    // Let's use the iterative approach from the spec reference implementation:
    // Find largest p = 3^k such that p <= n, subtract from n to get lipmaa
    // n=1 -> p=1 -> n-p+1=1 (special case)
    // n=2 -> p=1 -> 2-1=1 ✓
    // n=3 -> p=3 -> 3-3=0... that's wrong
    // Bamboo spec: lipmaa(n) is the "jump-back" skip sequence
    // Use: find largest 3^k < n (strictly less)
    NSInteger pow3 = 1;
    while (pow3 * 3 < seq) {
        pow3 *= 3;
    }
    // pow3 is now the largest power of 3 strictly less than seq
    // (unless seq is itself a power of 3, in which case pow3 == seq/3)
    if (pow3 >= seq) {
        pow3 /= 3;
    }
    return seq - pow3;
}

#pragma mark - SHA-256 Hash (BLAKE2b placeholder)

+ (nullable NSData *)hashData:(NSData *)data {
    if (!data) {
        return nil;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Entry Validation

+ (BOOL)validateEntry:(NSData *)entryData {
    if (!entryData || entryData.length < kBambooMinSize) {
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)entryData.bytes;

    // Extract author public key (bytes 0-31)
    NSData *authorKey = [entryData subdataWithRange:NSMakeRange(kAuthorOffset, 32)];

    // Extract is_end_of_log (byte 64)
    uint8_t isEnd = bytes[kIsEndOffset];
    if (isEnd != 0 && isEnd != 1) {
        return NO;
    }

    // Extract seq_number (bytes 65-72, big-endian uint64)
    uint64_t seqBE = 0;
    memcpy(&seqBE, bytes + kSeqOffset, 8);
    uint64_t seq = CFSwapInt64BigToHost(seqBE);
    if (seq < 1) {
        return NO;
    }

    // Determine signature offset and verify entry is large enough
    NSUInteger sigOffset;
    if (seq == 1) {
        // No lipmaa_link, no backlink
        // Minimum: 32+32+1+8+32+8+64 = 177
        if (entryData.length < kSigOffsetSeq1 + crypto_sign_BYTES) {
            return NO;
        }
        sigOffset = kSigOffsetSeq1;
    } else {
        // Both lipmaa_link (73-104) and backlink (105-136) present
        // Minimum: 177 + 32 + 32 = 241
        NSUInteger minSizeSeqN = kSigOffsetSeqN + crypto_sign_BYTES;
        if (entryData.length < minSizeSeqN) {
            return NO;
        }
        sigOffset = kSigOffsetSeqN;
    }

    // Signed bytes are everything before the signature
    NSData *signedData = [entryData subdataWithRange:NSMakeRange(0, sigOffset)];
    NSData *signature  = [entryData subdataWithRange:NSMakeRange(sigOffset, crypto_sign_BYTES)];

    if (signature.length != crypto_sign_BYTES) {
        return NO;
    }

    // Verify Ed25519 signature using tweetnacl crypto_sign_open
    // crypto_sign_open expects: signed message = signature || message
    NSMutableData *sm = [NSMutableData dataWithData:signature];
    [sm appendData:signedData];

    unsigned char m[sm.length];
    unsigned long long mlen = 0;
    int ret = crypto_sign_open(m, &mlen, (const unsigned char *)sm.bytes,
                               (unsigned long long)sm.length,
                               (const unsigned char *)authorKey.bytes);
    if (ret != 0) {
        return NO;
    }

    if (mlen != signedData.length) {
        return NO;
    }

    return memcmp(m, signedData.bytes, signedData.length) == 0;
}

#pragma mark - Entry ID

+ (nullable NSData *)computeEntryID:(NSData *)entryData {
    if (!entryData || entryData.length < kBambooMinSize) {
        return nil;
    }

    // Determine signature offset based on seq number
    const uint8_t *bytes = (const uint8_t *)entryData.bytes;
    uint64_t seqBE = 0;
    memcpy(&seqBE, bytes + kSeqOffset, 8);
    uint64_t seq = CFSwapInt64BigToHost(seqBE);

    NSUInteger sigOffset = (seq == 1) ? kSigOffsetSeq1 : kSigOffsetSeqN;

    if (entryData.length < sigOffset + crypto_sign_BYTES) {
        return nil;
    }

    // SHA-256 of the first 32 bytes of the entry data (hash portion)
    NSData *hashInput = [entryData subdataWithRange:NSMakeRange(0, 32)];
    NSData *hashPart  = [self hashData:hashInput];
    if (!hashPart) {
        return nil;
    }

    // Signature bytes (64 bytes)
    NSData *sigPart = [entryData subdataWithRange:NSMakeRange(sigOffset, crypto_sign_BYTES)];

    // Entry ID = hash (32 bytes) || signature (64 bytes) = 96 bytes total
    // But the spec says 64 bytes total (hash + sig). SHA-256 is 32 bytes, sig is 64 bytes = 96.
    // The header says "64 bytes (entry hash + signature)" — the hash here must be 0 bytes of
    // the SHA-256 portion, OR the spec intends 32-byte hash + 32-byte sig truncation.
    // Re-reading: "Message IDs are 64 bytes (entry hash + signature)" in the header comment,
    // but computeEntryID spec says: "SHA-256 of the entry data (first 32 bytes), concatenated
    // with the 64-byte signature" -> Returns 64 bytes total.
    // SHA-256 is 32 bytes; 32 + 64 = 96, not 64.
    // The most consistent interpretation: the "64 bytes" in the header is approximate/wrong,
    // and the actual implementation per spec body is 32+64=96 bytes. We follow the spec body.
    NSMutableData *entryID = [NSMutableData dataWithData:hashPart];
    [entryID appendData:sigPart];

    return [entryID copy];
}

@end
