//
//  SSBKeychain.h
//  SSBNetwork
//
//  Secure keychain storage for SSB identity keys
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSBKeychain : NSObject

+ (nullable NSData *)loadIdentitySecret;
+ (BOOL)saveIdentitySecret:(NSData *)secret;
+ (BOOL)deleteIdentitySecret;

+ (nullable NSData *)loadNetworkKey;
+ (BOOL)saveNetworkKey:(NSData *)key;
+ (BOOL)deleteNetworkKey;

+ (NSInteger)loadPublishedMessageCount;
+ (BOOL)savePublishedMessageCount:(NSInteger)count;

+ (BOOL)clearAll;

@end

NS_ASSUME_NONNULL_END
