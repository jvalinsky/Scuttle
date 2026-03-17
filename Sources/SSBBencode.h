#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bencode encoding and decoding utilities used by BendyButt-family feed formats.
/// This class owns the canonical implementation; SSBBendyButt delegates to it.
@interface SSBBencode : NSObject

/// Encodes an integer value: i<value>e
+ (nullable NSData *)encodeInteger:(NSInteger)value;

/// Encodes a UTF-8 string as a bencode byte string: <len>:<utf8bytes>
+ (nullable NSData *)encodeString:(NSString *)string;

/// Encodes arbitrary bytes as a bencode byte string: <len>:<bytes>
+ (nullable NSData *)encodeData:(NSData *)data;

/// Encodes an ordered list: l<items>e
/// Items may be NSData, NSString, NSNumber (integer), NSArray, NSDictionary, or NSNull.
+ (nullable NSData *)encodeList:(NSArray<id> *)list;

/// Encodes a dictionary with lexicographically sorted keys: d<key><value>...e
/// Keys must be NSString; values may be any encodable type.
+ (nullable NSData *)encodeDict:(NSDictionary<NSString *, id> *)dict;

/// Decodes a bencode-encoded value from data starting at *offset.
/// Updates *offset to point past the decoded value.
/// Returns NSData for byte strings, NSNumber for integers, NSArray for lists,
/// NSDictionary for dicts, or nil on parse failure.
+ (nullable id)decode:(NSData *)data offset:(NSUInteger *)offset;

@end

NS_ASSUME_NONNULL_END
