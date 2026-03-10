//
//  SSBBIPF.h
//  ScuttleKit
//
//  BIPF (Binary In-Place Format) implementation for SIP-011
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SSBBIPFType) {
    SSBBIPFTypeString = 0,
    SSBBIPFTypeBytes = 1,
    SSBBIPFTypeInt = 2,
    SSBBIPFTypeDouble = 3,
    SSBBIPFTypeList = 4,
    SSBBIPFTypeDict = 5,
    SSBBIPFTypeBoolNull = 6,
    SSBBIPFTypeExtended = 7
};

@interface SSBBIPF : NSObject

+ (nullable NSData *)encode:(id)value;
+ (nullable id)decode:(NSData *)data consumed:(NSUInteger *)consumed;

+ (nullable NSData *)encodeString:(NSString *)string;
+ (nullable NSData *)encodeBytes:(NSData *)bytes;
+ (nullable NSData *)encodeInteger:(int64_t)integer;
+ (nullable NSData *)encodeDouble:(double)d;
+ (nullable NSData *)encodeList:(NSArray<id> *)list;
+ (nullable NSData *)encodeDictionary:(NSDictionary<NSString *, id> *)dict;
+ (nullable NSData *)encodeBool:(BOOL)value;
+ (nullable NSData *)encodeNull;

+ (nullable NSString *)decodeString:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSData *)decodeBytes:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSNumber *)decodeInteger:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSNumber *)decodeDouble:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSArray<id> *)decodeList:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSDictionary<NSString *, id> *)decodeDictionary:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable NSNumber *)decodeBool:(NSData *)data consumed:(NSUInteger *)consumed;
+ (nullable id)decodeNull:(NSData *)data consumed:(NSUInteger *)consumed;

+ (uint8_t)readVarint:(NSData *)data offset:(NSUInteger)offset value:(uint64_t *)value;
+ (NSData *)writeVarint:(uint64_t)value;

+ (NSString *)humanReadable:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
