#import <Foundation/Foundation.h>
#import "SSBFeedCodec.h"

@class SSBMetafeedKeys;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBIndexFeedType) {
    SSBIndexFeedTypeContacts,
    SSBIndexFeedTypeAbouts,
    SSBIndexFeedTypePosts,
    SSBIndexFeedTypeCustom
};

/// Index feed (indexed-v1) utilities and SSBFeedCodec conformance.
/// Index feed messages use Classic JSON wire format with Ed25519 signing,
/// carrying content type "metafeed/index". The codec delegates crypto
/// operations to SSBMessageCodec and self-registers at +load time.
@interface SSBIndexFeed : NSObject <SSBFeedCodec>

+ (instancetype)sharedCodec;

+ (NSString *)indexFeedBFEIdentifier;

+ (nullable NSString *)createIndexFeedURIForFeedID:(NSString *)feedID;

+ (nullable NSString *)createIndexMessageURIForMessageID:(NSString *)messageID;

+ (nullable NSDictionary<NSString *, id> *)createIndexMessageWithKey:(NSString *)messageKey
                                           sequence:(NSInteger)sequence;

+ (nullable NSDictionary<NSString *, id> *)parseIndexMessage:(NSDictionary<NSString *, id> *)content;

+ (nullable NSDictionary<NSString *, id> *)createQueryWithAuthor:(NSString *)author
                                       messageType:(nullable NSString *)messageType
                                         isPrivate:(BOOL)isPrivate;

+ (nullable NSDictionary<NSString *, id> *)createQueryWithAuthor:(nullable NSString *)author
                                       messageType:(nullable NSString *)messageType
                                            channel:(nullable NSString *)channel
#ifdef __APPLE__
    __deprecated_msg("Use createQueryWithAuthor:messageType:isPrivate:")
#endif
    ;

+ (NSString *)queryLanguageIdentifier;

+ (nullable NSDictionary<NSString *, id> *)createAddDerivedMessageForIndexFeed:(NSString *)indexFeedID
                                                   feedPurpose:(NSString *)feedPurpose
                                                         query:(NSDictionary<NSString *, id> *)query
                                                      metafeedID:(NSString *)metafeedID
                                                       feedKeys:(SSBMetafeedKeys *)feedKeys;

+ (nullable NSDictionary<NSString *, id> *)createContactIndexQueryForAuthor:(NSString *)author;

+ (nullable NSDictionary<NSString *, id> *)createAboutIndexQueryForAuthor:(nullable NSString *)author;

+ (nullable NSDictionary<NSString *, id> *)createPostsIndexQueryForAuthor:(nullable NSString *)author
                                                   channel:(nullable NSString *)channel;

+ (nullable NSDictionary<NSString *, id> *)createContactIndexQuery;

+ (nullable NSDictionary<NSString *, id> *)createAboutIndexQuery;

+ (nullable NSDictionary<NSString *, id> *)createPostsIndexQuery;

+ (nullable NSDictionary<NSString *, id> *)createGenericIndexQueryWithAuthor:(nullable NSString *)author
                                                messageType:(nullable NSString *)messageType
                                                   channel:(nullable NSString *)channel;

+ (nullable NSDictionary<NSString *, id> *)createIndexFeedForQuery:(NSDictionary<NSString *, id> *)query
                                      feedPurpose:(NSString *)feedPurpose
                                        metafeedID:(NSString *)metafeedID
                                         feedKeys:(SSBMetafeedKeys *)feedKeys;

+ (nullable NSString *)indexedFeedIDFromPublicKey:(NSData *)publicKey;

+ (nullable NSData *)publicKeyFromIndexedFeedID:(NSString *)feedID;

+ (nullable NSString *)indexedMessageIDFromMessageID:(NSString *)messageID;

+ (nullable NSString *)messageIDFromIndexedMessageID:(NSString *)indexedMessageID;

+ (SSBIndexFeedType)indexTypeFromQuery:(NSDictionary<NSString *, id> *)query;

+ (nullable NSDictionary<NSString *, id> *)addExistingMessageForIndexFeed:(NSString *)indexFeedID
                                             metafeedID:(NSString *)metafeedID
                                              feedKeys:(SSBMetafeedKeys *)feedKeys;

@end

NS_ASSUME_NONNULL_END
