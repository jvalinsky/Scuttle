#import "SSBSecretStore.h"
#import <dispatch/dispatch.h>

#if defined(__APPLE__) && __has_include(<Security/Security.h>)
#import <Security/Security.h>
#endif

static NSString * const kSSBSecretStoreServiceName = @"com.scuttlekit.identity";
static NSString * const kIdentityKey = @"ssb_identity_secret";
static NSString * const kPublishedMessageCountKey = @"ssb_published_count";
static NSString * const kMetafeedSeedKey = @"ssb_metafeed_seed";
static NSString * const kMetafeedRootIDKey = @"ssb_metafeed_root_id";
static NSString * const kMetafeedAnnouncedKey = @"ssb_metafeed_announced";

@implementation SSBAppleKeychainSecretStore

- (NSMutableDictionary *)baseQuery {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = kSSBSecretStoreServiceName;
    return query;
#else
    return [NSMutableDictionary dictionary];
#endif
}

- (NSData *)loadDataForKey:(NSString *)key {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result != NULL) {
        return (__bridge_transfer NSData *)result;
    }
#endif
    return nil;
}

- (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    [self deleteDataForKey:key];

    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
#else
    (void)data;
    (void)key;
    return NO;
#endif
}

- (BOOL)deleteDataForKey:(NSString *)key {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecAttrAccount] = key;

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
#else
    (void)key;
    return NO;
#endif
}

- (BOOL)clearAll {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    NSMutableDictionary *query = [self baseQuery];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
#else
    return NO;
#endif
}

@end

@implementation SSBFileSecretStore

- (instancetype)initWithBaseDirectory:(nullable NSString *)baseDirectory {
    self = [super init];
    if (self) {
        NSString *resolved = baseDirectory;
        if (resolved.length == 0) {
            NSString *xdgConfig = NSProcessInfo.processInfo.environment[@"XDG_CONFIG_HOME"];
            if (xdgConfig.length > 0) {
                resolved = [xdgConfig stringByAppendingPathComponent:@"scuttle"];
            } else {
                resolved = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scuttle"];
            }
        }
        _baseDirectory = [resolved copy];
        [[NSFileManager defaultManager] createDirectoryAtPath:_baseDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:@{ NSFilePosixPermissions: @(0700) }
                                                        error:nil];
    }
    return self;
}

- (NSString *)pathForKey:(NSString *)key {
    return [self.baseDirectory stringByAppendingPathComponent:key];
}

- (NSData *)loadDataForKey:(NSString *)key {
    return [NSData dataWithContentsOfFile:[self pathForKey:key]];
}

- (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    NSString *path = [self pathForKey:key];
    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:nil];
    if (success) {
        [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(0600) }
                                         ofItemAtPath:path
                                                error:nil];
    }
    return success;
}

- (BOOL)deleteDataForKey:(NSString *)key {
    NSString *path = [self pathForKey:key];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return YES;
    }
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (BOOL)clearAll {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.baseDirectory]) {
        return YES;
    }
    return [[NSFileManager defaultManager] removeItemAtPath:self.baseDirectory error:nil];
}

@end

id<SSBSecretStore> SSBCreateDefaultSecretStore(void) {
#if defined(__APPLE__) && __has_include(<Security/Security.h>)
    return [[SSBAppleKeychainSecretStore alloc] init];
#else
    return [[SSBFileSecretStore alloc] initWithBaseDirectory:nil];
#endif
}

id<SSBSecretStore> SSBSharedSecretStore(void) {
    static id<SSBSecretStore> store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = SSBCreateDefaultSecretStore();
    });
    return store;
}

NSString *SSBPublicIDFromSecret(NSData *secret) {
    if (secret.length < 64) {
        return nil;
    }
    NSData *pkData = [secret subdataWithRange:NSMakeRange(32, 32)];
    return [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
}

NSData *SSBLoadIdentitySecret(void) {
    return [SSBSharedSecretStore() loadDataForKey:kIdentityKey];
}

BOOL SSBSaveIdentitySecret(NSData *secret) {
    return [SSBSharedSecretStore() saveData:secret forKey:kIdentityKey];
}

BOOL SSBDeleteIdentitySecret(void) {
    return [SSBSharedSecretStore() deleteDataForKey:kIdentityKey];
}

NSInteger SSBLoadPublishedMessageCount(void) {
    NSData *data = [SSBSharedSecretStore() loadDataForKey:kPublishedMessageCountKey];
    if (data.length >= sizeof(NSInteger)) {
        NSInteger count = 0;
        [data getBytes:&count length:sizeof(NSInteger)];
        return count;
    }

    NSString *stringValue = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    return stringValue.integerValue;
}

BOOL SSBSavePublishedMessageCount(NSInteger count) {
    NSData *data = [NSData dataWithBytes:&count length:sizeof(NSInteger)];
    return [SSBSharedSecretStore() saveData:data forKey:kPublishedMessageCountKey];
}

NSData *SSBLoadMetafeedSeed(void) {
    return [SSBSharedSecretStore() loadDataForKey:kMetafeedSeedKey];
}

BOOL SSBSaveMetafeedSeed(NSData *seed) {
    return [SSBSharedSecretStore() saveData:seed forKey:kMetafeedSeedKey];
}

BOOL SSBDeleteMetafeedSeed(void) {
    return [SSBSharedSecretStore() deleteDataForKey:kMetafeedSeedKey];
}

NSString *SSBLoadMetafeedRootID(void) {
    NSData *data = [SSBSharedSecretStore() loadDataForKey:kMetafeedRootIDKey];
    if (!data) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

BOOL SSBSaveMetafeedRootID(NSString *rootID) {
    NSData *data = [rootID dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [SSBSharedSecretStore() saveData:data forKey:kMetafeedRootIDKey] : NO;
}

BOOL SSBDeleteMetafeedRootID(void) {
    return [SSBSharedSecretStore() deleteDataForKey:kMetafeedRootIDKey];
}

BOOL SSBLoadMetafeedAnnounced(void) {
    NSData *data = [SSBSharedSecretStore() loadDataForKey:kMetafeedAnnouncedKey];
    if (!data) {
        return NO;
    }
    if (data.length >= 1) {
        uint8_t value = 0;
        [data getBytes:&value length:1];
        return value != 0;
    }
    NSString *stringValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return stringValue.boolValue;
}

BOOL SSBSaveMetafeedAnnounced(BOOL announced) {
    uint8_t value = announced ? 1 : 0;
    return [SSBSharedSecretStore() saveData:[NSData dataWithBytes:&value length:1] forKey:kMetafeedAnnouncedKey];
}

BOOL SSBDeleteMetafeedAnnounced(void) {
    return [SSBSharedSecretStore() deleteDataForKey:kMetafeedAnnouncedKey];
}
