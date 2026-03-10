#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBMetafeedPurpose) {
    SSBMetafeedPurposeClassic = 0,
    SSBMetafeedPurposeV1 = 1,
    SSBMetafeedPurposeShard = 2,
    SSBMetafeedPurposeApplication = 3,
    SSBMetafeedPurposeGroup = 4
};

typedef NS_ENUM(NSInteger, SSBMetafeedMessageType) {
    SSBMetafeedMessageTypeAddExisting = 0,
    SSBMetafeedMessageTypeAddDerived = 1,
    SSBMetafeedMessageTypeUpdate = 2,
    SSBMetafeedMessageTypeTombstone = 3,
    SSBMetafeedMessageTypeSeed = 4,
    SSBMetafeedMessageTypeAnnounce = 5
};

@interface SSBMetafeedKeys : NSObject
@property (nonatomic, readonly) NSData *publicKey;
@property (nonatomic, readonly) NSData *secretKey;
@property (nonatomic, readonly) NSString *feedID;
@end

@interface SSBMetafeed : NSObject

+ (nullable instancetype)createRootMetafeedFromSeed:(NSData *)seed;

+ (nullable NSData *)deriveKeyFromSeed:(NSData *)seed
                                   info:(NSString *)info;

+ (nullable NSDictionary<NSString *, id> *)createMetafeed:(NSString *)metafeedID
                          addExistingFeed:(NSString *)feedID
                                   purpose:(SSBMetafeedPurpose)purpose;

+ (nullable NSDictionary<NSString *, id> *)createMetafeed:(NSString *)metafeedID
                           addDerivedFeed:(NSString *)feedName
                                   purpose:(SSBMetafeedPurpose)purpose
                                     nonce:(NSData *)nonce;

+ (nullable NSDictionary<NSString *, id> *)createMetafeed:(NSString *)metafeedID
                            updateFeed:(NSString *)feedID
                                 name:(nullable NSString *)name
                             purpose:(SSBMetafeedPurpose)purpose;

+ (nullable NSDictionary<NSString *, id> *)createMetafeed:(NSString *)metafeedID
                          tombstoneFeed:(NSString *)feedID
                                reason:(nullable NSString *)reason;

+ (nullable NSDictionary<NSString *, id> *)createMetafeedAnnounceMessage:(NSString *)metafeedID
                                               onMainFeed:(NSString *)mainFeedID
                                                secretKey:(NSData *)secretKey;

+ (nullable NSData *)encryptSeedForBackup:(NSData *)seed
                                   toFeed:(NSString *)feedID
                               feedKeys:(SSBMetafeedKeys *)keys;

+ (nullable NSData *)decryptSeedFromMessage:(NSDictionary<NSString *, id> *)message
                                   feedKeys:(SSBMetafeedKeys *)keys;

+ (NSString *)shardNibbleForMetafeedID:(NSString *)metafeedID
                                  name:(NSString *)name;

+ (nullable NSData *)generateSeed;

+ (nullable NSData *)sha256:(NSData *)data;

+ (nullable NSDictionary<NSString *, id> *)createSeedMessage:(NSData *)seed
                                 forMetafeed:(NSString *)metafeedID
                                      secretKey:(NSData *)secretKey
                                     onMainFeed:(NSString *)mainFeedID;

@property (nonatomic, readonly) NSString *ID;
@property (nonatomic, readonly) SSBMetafeedKeys *keys;
@property (nonatomic, readonly) SSBMetafeed *v1Subfeed;
@property (nonatomic, readonly) NSArray<SSBMetafeed *> *shardFeeds;

#pragma mark - Instance Operations (SIP 2)

/// Generates an 'add/existing' message for the current metafeed.
- (nullable NSDictionary<NSString *, id> *)addExistingFeedMessage:(NSString *)feedID
                                                          purpose:(SSBMetafeedPurpose)purpose;

/// Generates an 'add/derived' message for the current metafeed.
- (nullable NSDictionary<NSString *, id> *)addDerivedFeedMessage:(NSString *)feedName
                                                         purpose:(SSBMetafeedPurpose)purpose
                                                           nonce:(NSData *)nonce;

/// Generates a 'tombstone' message for a subfeed.
- (nullable NSDictionary<NSString *, id> *)tombstoneFeedMessage:(NSString *)feedID
                                                         reason:(nullable NSString *)reason;

@end

NS_ASSUME_NONNULL_END
