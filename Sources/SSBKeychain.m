//
//  SSBKeychain.m
//  SSBNetwork
//
//  Secure keychain storage for SSB identity keys using Security.framework
//

#import "SSBKeychain.h"
#import <Security/Security.h>

static NSString * const kServiceName = @"com.scuttlekit.identity";
static NSString * const kIdentityKey = @"ssb_identity_secret";
static NSString * const kNetworkKey = @"ssb_network_key";
static NSString * const kMessageCountKey = @"ssb_published_count";

@implementation SSBKeychain

+ (NSMutableDictionary *)baseQuery {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = kServiceName;
    return query;
}

+ (nullable NSData *)loadDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        return data;
    }
    
    return nil;
}

+ (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    [self deleteDataForKey:key];

    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

+ (BOOL)deleteDataForKey:(NSString *)key {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

#pragma mark - Identity Secret

+ (nullable NSData *)loadIdentitySecret {
    return [self loadDataForKey:kIdentityKey];
}

+ (BOOL)saveIdentitySecret:(NSData *)secret {
    return [self saveData:secret forKey:kIdentityKey];
}

+ (BOOL)deleteIdentitySecret {
    return [self deleteDataForKey:kIdentityKey];
}

#pragma mark - Network Key

+ (nullable NSData *)loadNetworkKey {
    return [self loadDataForKey:kNetworkKey];
}

+ (BOOL)saveNetworkKey:(NSData *)key {
    return [self saveData:key forKey:kNetworkKey];
}

+ (BOOL)deleteNetworkKey {
    return [self deleteDataForKey:kNetworkKey];
}

#pragma mark - Published Message Count (for fork prevention)

+ (NSInteger)loadPublishedMessageCount {
    NSData *data = [self loadDataForKey:kMessageCountKey];
    if (data && data.length >= sizeof(NSInteger)) {
        NSInteger count;
        [data getBytes:&count length:sizeof(NSInteger)];
        return count;
    }
    return 0;
}

+ (BOOL)savePublishedMessageCount:(NSInteger)count {
    NSData *data = [NSData dataWithBytes:&count length:sizeof(NSInteger)];
    return [self saveData:data forKey:kMessageCountKey];
}

#pragma mark - Clear All

+ (BOOL)clearAll {
    BOOL identityResult = [self deleteIdentitySecret];
    BOOL networkResult = [self deleteNetworkKey];
    BOOL countResult = [self deleteDataForKey:kMessageCountKey];
    return identityResult && networkResult && countResult;
}

+ (nullable NSString *)publicIDFromSecret:(NSData *)secret {
    if (secret.length < 64) return nil;
    NSData *pkData = [secret subdataWithRange:NSMakeRange(32, 32)];
    return [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
}

@end
