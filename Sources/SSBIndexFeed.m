#import "SSBIndexFeed.h"
#import "SSBBFE.h"
#import "SSBMetafeed.h"
#import "SSBURI.h"
#import "tweetnacl.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const kIndexedV1Format = @"indexed-v1";
static NSString *const kQueryLanguageV0 = @"ssb-ql-0";
static NSString *const kMetafeedIndexType = @"metafeed/index";
static NSString *const kMetafeedAddDerivedType = @"metafeed/add/derived";

@implementation SSBIndexFeed

+ (NSString *)indexFeedBFEIdentifier {
    return kIndexedV1Format;
}

+ (nullable NSString *)createIndexFeedURIForFeedID:(NSString *)feedID {
    if (!feedID || feedID.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"ssb:feed/%@/%@", kIndexedV1Format, feedID];
}

+ (nullable NSString *)createIndexMessageURIForMessageID:(NSString *)messageID {
    if (!messageID || messageID.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"ssb:message/%@/%@", kIndexedV1Format, messageID];
}

+ (nullable NSDictionary *)createIndexMessageWithKey:(NSString *)messageKey
                                           sequence:(NSInteger)sequence {
    if (!messageKey || messageKey.length == 0) {
        return nil;
    }

    if (sequence < 1) {
        return nil;
    }

    NSDictionary *content = @{
        @"type": kMetafeedIndexType,
        @"indexed": @{
            @"key": messageKey,
            @"sequence": @(sequence)
        }
    };

    return content;
}

+ (nullable NSDictionary *)parseIndexMessage:(NSDictionary *)content {
    if (!content) {
        return nil;
    }

    NSString *type = content[@"type"];
    if (![type isEqualToString:kMetafeedIndexType]) {
        return nil;
    }

    NSDictionary *indexed = content[@"indexed"];
    if (![indexed isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *key = indexed[@"key"];
    NSNumber *sequence = indexed[@"sequence"];

    if (!key || !sequence) {
        return nil;
    }

    return @{
        @"key": key,
        @"sequence": sequence
    };
}

+ (nullable NSDictionary *)createQueryWithAuthor:(NSString *)author
                                     messageType:(nullable NSString *)messageType
                                       isPrivate:(BOOL)isPrivate {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[@"author"] = author;
    query[@"type"] = messageType ?: [NSNull null];
    query[@"private"] = @(isPrivate);
    
    // If private: true then type MUST be null
    if (isPrivate) {
        query[@"type"] = [NSNull null];
    }
    
    return [query copy];
}

+ (nullable NSDictionary *)createQueryWithAuthor:(nullable NSString *)author
                                     messageType:(nullable NSString *)messageType
                                         channel:(nullable NSString *)channel {
    return [self createQueryWithAuthor:author ?: @"" messageType:messageType isPrivate:NO];
}

+ (NSString *)queryLanguageIdentifier {
    return kQueryLanguageV0;
}

+ (nullable NSDictionary *)createAddDerivedMessageForIndexFeed:(NSString *)indexFeedID
                                                   feedPurpose:(NSString *)feedPurpose
                                                         query:(NSDictionary *)query
                                                      metafeedID:(NSString *)metafeedID
                                                       feedKeys:(SSBMetafeedKeys *)feedKeys {
    if (!indexFeedID || !feedPurpose || !query || !metafeedID || !feedKeys) {
        return nil;
    }

    NSError *error;
    NSData *queryJSONData = [NSJSONSerialization dataWithJSONObject:query options:0 error:&error];
    if (error || !queryJSONData) {
        return nil;
    }

    NSString *queryJSON = [[NSString alloc] initWithData:queryJSONData encoding:NSUTF8StringEncoding];
    if (!queryJSON) {
        return nil;
    }

    NSDictionary *content = @{
        @"type": kMetafeedAddDerivedType,
        @"feedpurpose": @"index",
        @"subfeed": indexFeedID,
        @"querylang": kQueryLanguageV0,
        @"query": queryJSON
    };

    return content;
}

+ (nullable NSDictionary *)createContactIndexQueryForAuthor:(NSString *)author {
    return [self createQueryWithAuthor:author messageType:@"contact" isPrivate:NO];
}

+ (nullable NSDictionary *)createAboutIndexQueryForAuthor:(NSString *)author {
    return [self createQueryWithAuthor:author messageType:@"about" isPrivate:NO];
}

+ (nullable NSDictionary *)createPostsIndexQueryForAuthor:(nullable NSString *)author
                                                 channel:(nullable NSString *)channel {
    return [self createQueryWithAuthor:author ?: @"" messageType:@"post" isPrivate:NO];
}

+ (nullable NSDictionary *)createContactIndexQuery {
    return [self createQueryWithAuthor:@"" messageType:@"contact" isPrivate:NO];
}

+ (nullable NSDictionary *)createAboutIndexQuery {
    return [self createQueryWithAuthor:@"" messageType:@"about" isPrivate:NO];
}

+ (nullable NSDictionary *)createPostsIndexQuery {
    return [self createQueryWithAuthor:@"" messageType:@"post" isPrivate:NO];
}

+ (nullable NSDictionary *)createGenericIndexQueryWithAuthor:(nullable NSString *)author
                                                 messageType:(nullable NSString *)messageType
                                                     channel:(nullable NSString *)channel {
    return [self createQueryWithAuthor:author ?: @"" messageType:messageType isPrivate:NO];
}

+ (nullable NSDictionary *)createIndexFeedForQuery:(NSDictionary *)query
                                      feedPurpose:(NSString *)feedPurpose
                                        metafeedID:(NSString *)metafeedID
                                         feedKeys:(SSBMetafeedKeys *)feedKeys {
    if (!query || !feedPurpose || !metafeedID || !feedKeys) {
        return nil;
    }

    NSData *subfeedSeed = [self deriveIndexSeedFromMetafeed:metafeedID purpose:feedPurpose feedKeys:feedKeys];
    if (!subfeedSeed) {
        return nil;
    }

    unsigned char publicKey[32];
    unsigned char secretKey[64];
    crypto_sign_seed_keypair(publicKey, secretKey, subfeedSeed.bytes);

    NSData *pubKeyData = [NSData dataWithBytes:publicKey length:32];
    NSString *indexedFeedID = [self indexedFeedIDFromPublicKey:pubKeyData];

    if (!indexedFeedID) {
        return nil;
    }

    return [self createAddDerivedMessageForIndexFeed:indexedFeedID
                                         feedPurpose:feedPurpose
                                               query:query
                                            metafeedID:metafeedID
                                             feedKeys:feedKeys];
}

+ (nullable NSString *)indexedFeedIDFromPublicKey:(NSData *)publicKey {
    if (!publicKey || publicKey.length != 32) {
        return nil;
    }

    NSData *bfeData = [SSBBFE encodeFeedID:publicKey format:SSBBFEFeedFormatIndexedV1];
    if (!bfeData) {
        return nil;
    }

    NSString *feedID = [SSBBFE sigilStringFromBFE:bfeData];
    return feedID;
}

+ (nullable NSData *)publicKeyFromIndexedFeedID:(NSString *)feedID {
    if (!feedID || feedID.length == 0) {
        return nil;
    }

    NSData *bfeData = [SSBBFE bfeDataFromSigilString:feedID];
    if (!bfeData || bfeData.length < 2) {
        return nil;
    }

    SSBBFEType type = [SSBBFE detectType:bfeData];
    NSInteger format = [SSBBFE detectFormat:bfeData];

    if (type != SSBBFETypeFeed || format != SSBBFEFeedFormatIndexedV1) {
        return nil;
    }

    return [bfeData subdataWithRange:NSMakeRange(2, bfeData.length - 2)];
}

+ (nullable NSString *)indexedMessageIDFromMessageID:(NSString *)messageID {
    if (!messageID || messageID.length == 0) {
        return nil;
    }

    NSString *hashPart = messageID;
    if ([messageID hasPrefix:@"%"]) {
        hashPart = [messageID substringFromIndex:1];
    }

    NSData *hashData = [SSBBFE dataFromBase64URLEncodedString:hashPart];
    if (!hashData) {
        return nil;
    }

    NSData *bfeData = [SSBBFE encodeMessageID:hashData format:SSBBFEMessageFormatIndexedV1];
    if (!bfeData) {
        return nil;
    }

    NSString *msgID = [SSBBFE sigilStringFromBFE:bfeData];
    if (!msgID) {
        return nil;
    }

    return [NSString stringWithFormat:@"%%%@", msgID];
}

+ (nullable NSString *)messageIDFromIndexedMessageID:(NSString *)indexedMessageID {
    if (!indexedMessageID || indexedMessageID.length == 0) {
        return nil;
    }

    NSString *hashPart = indexedMessageID;
    if ([indexedMessageID hasPrefix:@"%"]) {
        hashPart = [indexedMessageID substringFromIndex:1];
    }

    NSData *bfeData = [SSBBFE bfeDataFromSigilString:hashPart];
    if (!bfeData || bfeData.length < 2) {
        return nil;
    }

    SSBBFEType type = [SSBBFE detectType:bfeData];
    NSInteger format = [SSBBFE detectFormat:bfeData];

    if (type != SSBBFETypeMessage || format != SSBBFEMessageFormatIndexedV1) {
        return nil;
    }

    NSData *hashData = [bfeData subdataWithRange:NSMakeRange(2, bfeData.length - 2)];
    NSString *base64Hash = [SSBBFE base64URLEncodedStringFromData:hashData];

    return [NSString stringWithFormat:@"%%%@", base64Hash];
}

+ (SSBIndexFeedType)indexTypeFromQuery:(NSDictionary *)query {
    if (!query) {
        return SSBIndexFeedTypeCustom;
    }

    NSString *type = query[@"type"];
    NSString *author = query[@"author"];

    if ([type isEqualToString:@"contact"]) {
        return SSBIndexFeedTypeContacts;
    }

    if ([type isEqualToString:@"about"]) {
        return SSBIndexFeedTypeAbouts;
    }

    if ([type isEqualToString:@"post"]) {
        return SSBIndexFeedTypePosts;
    }

    return SSBIndexFeedTypeCustom;
}

+ (nullable NSDictionary *)addExistingMessageForIndexFeed:(NSString *)indexFeedID
                                                metafeedID:(NSString *)metafeedID
                                                 feedKeys:(SSBMetafeedKeys *)feedKeys {
    if (!indexFeedID || !metafeedID || !feedKeys) {
        return nil;
    }

    NSDictionary *content = @{
        @"type": @"metafeed",
        @"metafeedType": @"add/existing",
        @"feed": indexFeedID,
        @"purpose": @"index"
    };

    return content;
}

#pragma mark - Private Helpers

+ (nullable NSData *)sha256:(NSData *)data {
    if (!data) {
        return nil;
    }

    NSMutableData *hash = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    if (!hash) {
        return nil;
    }

    CC_SHA256(data.bytes, (CC_LONG)data.length, hash.mutableBytes);
    return hash;
}

+ (nullable NSData *)deriveIndexSeedFromMetafeed:(NSString *)metafeedID
                                          purpose:(NSString *)purpose
                                        feedKeys:(SSBMetafeedKeys *)feedKeys {
    if (!metafeedID || !purpose || !feedKeys) {
        return nil;
    }

    NSString *purposeInfo = [NSString stringWithFormat:@"ssb-meta-feed-seed-v1:index:%@", purpose];

    NSData *metafeedKeyData = [SSBBFE bfeDataFromSigilString:metafeedID];
    if (!metafeedKeyData || metafeedKeyData.length < 2) {
        return nil;
    }

    NSData *metafeedPublicKey = [metafeedKeyData subdataWithRange:NSMakeRange(2, metafeedKeyData.length - 2)];

    NSString *infoString = purposeInfo;
    NSData *infoData = [infoString dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *combined = [NSMutableData dataWithData:metafeedPublicKey];
    [combined appendData:infoData];

    NSData *saltData = [@"ssb" dataUsingEncoding:NSUTF8StringEncoding];
    [combined appendData:saltData];

    return [self sha256:combined];
}

+ (nullable NSData *)generateNonce {
    NSMutableData *nonce = [NSMutableData dataWithLength:32];
    if (!nonce) {
        return nil;
    }

    int result = SecRandomCopyBytes(kSecRandomDefault, 32, nonce.mutableBytes);
    if (result != errSecSuccess) {
        return nil;
    }

    return nonce;
}

@end
