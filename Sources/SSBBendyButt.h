#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBFeedCodec.h>
#import <SSBNetwork/SSBBencode.h>

NS_ASSUME_NONNULL_BEGIN

/// Handles Bendy Butt (bbfeed-v1) message creation, validation, and key computation.
/// Conforms to SSBFeedCodec so it can be dispatched from SSBFeedCodecRegistry.
@interface SSBBendyButt : NSObject <SSBFeedCodec>

/// Returns the shared codec instance registered in SSBFeedCodecRegistry.
+ (instancetype)sharedCodec;

@property (nonatomic, readonly) NSData *author;
@property (nonatomic, readonly) NSInteger sequence;
@property (nonatomic, readonly, nullable) NSData *previous;
@property (nonatomic, readonly) NSInteger timestamp;
@property (nonatomic, readonly, nullable) NSData *content;
@property (nonatomic, readonly, nullable) NSData *contentSignature;
@property (nonatomic, readonly, nullable) NSData *encryptedContent;
@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly) NSData *messageKey;

+ (nullable instancetype)messageWithContent:(NSDictionary<NSString *, id> *)content
                                     author:(NSData *)author
                               authorSecret:(NSData *)authorSecret
                                   sequence:(NSInteger)sequence
                                   previous:(nullable NSData *)previous
                                  timestamp:(NSInteger)timestamp
                            contentSecretKey:(NSData *)contentSecretKey;

+ (nullable instancetype)messageWithEncryptedContent:(NSData *)encryptedContent
                                              author:(NSData *)author
                                        authorSecret:(NSData *)authorSecret
                                            sequence:(NSInteger)sequence
                                            previous:(nullable NSData *)previous
                                           timestamp:(NSInteger)timestamp
                                     contentSecretKey:(NSData *)contentSecretKey;

+ (nullable NSData *)createMessageWithContent:(NSDictionary<NSString *, id> *)content
                                       author:(NSData *)author
                                 authorSecret:(NSData *)authorSecret
                                     sequence:(NSInteger)sequence
                                     previous:(nullable NSData *)previous
                                    timestamp:(NSInteger)timestamp
                              contentSecretKey:(NSData *)contentSecretKey;

+ (BOOL)validateMessage:(NSData *)messageData;

+ (nullable NSData *)computeMessageKey:(NSData *)messageData;

+ (nullable NSData *)signContent:(NSData *)content withKey:(NSData *)key;

+ (BOOL)verifyContentSignature:(NSData *)signature
                     onContent:(NSData *)content
                        author:(NSData *)author;

/// @name Bencode helpers — delegate to SSBBencode; preserved for binary compatibility.
+ (nullable NSData *)encodeBencodeInteger:(NSInteger)value;
+ (nullable NSData *)encodeBencodeString:(NSString *)string;
+ (nullable NSData *)encodeBencodeData:(NSData *)data;
+ (nullable NSData *)encodeBencodeList:(NSArray<id> *)list;
+ (nullable NSData *)encodeBencodeDict:(NSDictionary<NSString *, id> *)dict;
+ (nullable id)decodeBencode:(NSData *)data offset:(NSUInteger *)offset;

@end

NS_ASSUME_NONNULL_END
