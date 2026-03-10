#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBURIType) {
    SSBURITypeMessage,
    SSBURITypeFeed,
    SSBURITypeBlob,
    SSBURITypeAddress,
    SSBURITypeExperimental,
    SSBURITypeEncryptionKey,
    SSBURITypeIdentity,
    SSBURITypeUnknown
};

typedef NS_ENUM(NSInteger, SSBURIFormat) {
    SSBURIFormatClassic,
    SSBURIFormatBendybuttV1,
    SSBURIFormatGabbygroveV1,
    SSBURIFormatButtwooV1,
    SSBURIFormatMultiserver,
    SSBURIFormatBox2DmDh,
    SSBURIFormatPoBox,
    SSBURIFormatFusion,
    SSBURIFormatUnknown
};

@interface SSBURI : NSObject

@property (nonatomic, readonly) SSBURIType type;
@property (nonatomic, readonly) SSBURIFormat format;
@property (nonatomic, readonly, copy, nullable) NSString *identifier;
@property (nonatomic, readonly, copy, nullable) NSString *parentMessageId;
@property (nonatomic, readonly, copy, nullable) NSString *multiserverAddress;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, NSString *> *queryParams;
@property (nonatomic, readonly, copy) NSString *canonicalString;

+ (nullable instancetype)URIWithString:(NSString *)uriString;

+ (nullable instancetype)uriWithMessage:(NSString *)messageId format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithFeed:(NSString *)feedId format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithFeed:(NSString *)feedId parentMessageId:(nullable NSString *)parentMsgId format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithBlob:(NSString *)blobId format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithEncryptionKey:(NSString *)key format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithIdentity:(NSString *)key format:(SSBURIFormat)format;
+ (nullable instancetype)uriWithAddress:(NSString *)multiserverAddress;

+ (NSString *)formatToString:(SSBURIFormat)format;
+ (SSBURIFormat)formatFromString:(NSString *)string;

+ (NSString *)typeToString:(SSBURIType)type;
+ (SSBURIType)typeFromString:(NSString *)string;

+ (NSString *)encodeMultiserverAddress:(NSString *)address;
+ (nullable NSString *)decodeMultiserverAddress:(NSString *)encodedAddress;

@end

NS_ASSUME_NONNULL_END
