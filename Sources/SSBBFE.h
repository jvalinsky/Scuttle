#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBBFEType) {
    SSBBFETypeFeed = 0,
    SSBBFETypeMessage = 1,
    SSBBFETypeBlob = 2,
    SSBBFETypeEncryptionKey = 3,
    SSBBFETypeSignature = 4,
    SSBBFETypeEncrypted = 5,
    SSBBFETypeGeneric = 6,
    SSBBFETypeIdentity = 7
};

typedef NS_ENUM(NSInteger, SSBBFEFeedFormat) {
    SSBBFEFeedFormatClassic = 0,
    SSBBFEFeedFormatGabbygroveV1 = 1,
    SSBBFEFeedFormatBamboo = 2,
    SSBBFEFeedFormatBendybuttV1 = 3,
    SSBBFEFeedFormatButtwooV1 = 4,
    SSBBFEFeedFormatIndexedV1 = 5
};

typedef NS_ENUM(NSInteger, SSBBFEMessageFormat) {
    SSBBFEMessageFormatClassic = 0,
    SSBBFEMessageFormatGabbygroveV1 = 1,
    SSBBFEMessageFormatCloaked = 2,
    SSBBFEMessageFormatBamboo = 3,
    SSBBFEMessageFormatBendybuttV1 = 4,
    SSBBFEMessageFormatButtwooV1 = 5,
    SSBBFEMessageFormatIndexedV1 = 6
};

typedef NS_ENUM(NSInteger, SSBBFEBlobFormat) {
    SSBBFEBlobFormatClassic = 0
};

typedef NS_ENUM(NSInteger, SSBBFEGenericFormat) {
    SSBBFEGenericFormatString = 0,
    SSBBFEGenericFormatBoolean = 1,
    SSBBFEGenericFormatNil = 2,
    SSBBFEGenericFormatBytes = 3
};

typedef NS_ENUM(NSInteger, SSBBFETypes) {
    SSBBFETypesFeedClassic = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatClassic,
    SSBBFETypesFeedGabbygroveV1 = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatGabbygroveV1,
    SSBBFETypesFeedBamboo = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatBamboo,
    SSBBFETypesFeedBendybuttV1 = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatBendybuttV1,
    SSBBFETypesFeedButtwooV1 = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatButtwooV1,
    SSBBFETypesFeedIndexedV1 = (SSBBFETypeFeed << 8) | SSBBFEFeedFormatIndexedV1,
    
    SSBBFETypesMessageClassic = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatClassic,
    SSBBFETypesMessageGabbygroveV1 = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatGabbygroveV1,
    SSBBFETypesMessageCloaked = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatCloaked,
    SSBBFETypesMessageBamboo = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatBamboo,
    SSBBFETypesMessageBendybuttV1 = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatBendybuttV1,
    SSBBFETypesMessageButtwooV1 = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatButtwooV1,
    SSBBFETypesMessageIndexedV1 = (SSBBFETypeMessage << 8) | SSBBFEMessageFormatIndexedV1,
    
    SSBBFETypesBlobClassic = (SSBBFETypeBlob << 8) | SSBBFEBlobFormatClassic,
    
    SSBBFETypesGenericString = (SSBBFETypeGeneric << 8) | SSBBFEGenericFormatString,
    SSBBFETypesGenericBoolean = (SSBBFETypeGeneric << 8) | SSBBFEGenericFormatBoolean,
    SSBBFETypesGenericNil = (SSBBFETypeGeneric << 8) | SSBBFEGenericFormatNil,
    SSBBFETypesGenericBytes = (SSBBFETypeGeneric << 8) | SSBBFEGenericFormatBytes
};

typedef NS_ENUM(NSInteger, SSBBFEIdentityFormat) {
    SSBBFEIdentityFormatPoBox = 0,
    SSBBFEIdentityFormatGroup = 1
};

typedef NS_ENUM(NSInteger, SSBBFEEncryptionKeyFormat) {
    SSBBFEEncryptionKeyFormatBox2DmDh = 0,
    SSBBFEEncryptionKeyFormatBox2PoboxDh = 1
};

typedef NS_ENUM(NSInteger, SSBBFESignatureFormat) {
    SSBBFESignatureFormatMsgEd25519 = 0
};

typedef NS_ENUM(NSInteger, SSBBFEEncryptedFormat) {
    SSBBFEEncryptedFormatBox1 = 0,
    SSBBFEEncryptedFormatBox2 = 1
};

@interface SSBBFE : NSObject

+ (nullable NSData *)encodeFeedID:(id)feedID format:(SSBBFEFeedFormat)format;
+ (nullable NSData *)encodeMessageID:(id)messageID format:(SSBBFEMessageFormat)format;
+ (nullable NSData *)encodeBlobID:(id)blobID;
+ (nullable NSData *)encodeEncryptionKey:(NSData *)key format:(SSBBFEEncryptionKeyFormat)format;
+ (nullable NSData *)encodeSignature:(NSData *)signature;
+ (nullable NSData *)encodeEncrypted:(NSData *)ciphertext format:(SSBBFEEncryptedFormat)format;

+ (nullable NSData *)encodeGenericString:(NSString *)string;
+ (nullable NSData *)encodeBoolean:(BOOL)value;
+ (nullable NSData *)encodeNil;
+ (nullable NSData *)encodeGenericBytes:(NSData *)bytes;

+ (nullable NSData *)encodeIdentityPoBox:(NSData *)data;
+ (nullable NSData *)encodeIdentityGroup:(NSData *)data;

+ (nullable id)decode:(NSData *)bfeData type:(SSBBFEType *)outType format:(NSInteger *)outFormat;
+ (nullable id)decodeBFEData:(NSData *)bfeData;

+ (SSBBFEType)detectType:(NSData *)bfeData;
+ (NSInteger)detectFormat:(NSData *)bfeData;

+ (nullable NSString *)sigilStringFromBFE:(NSData *)bfeData;
+ (nullable NSData *)bfeDataFromSigilString:(NSString *)sigilString;

+ (NSString *)base64URLEncodedStringFromData:(NSData *)data;
+ (nullable NSData *)dataFromBase64URLEncodedString:(NSString *)base64URLString;

@end

NS_ASSUME_NONNULL_END
