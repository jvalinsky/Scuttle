#import "SSBKeychain.h"
#import "SSBSecretStore.h"
static NSString * const kNetworkKey = @"ssb_network_key";

@implementation SSBKeychain

+ (id<SSBSecretStore>)secretStore {
    return SSBSharedSecretStore();
}

+ (nullable NSData *)loadDataForKey:(NSString *)key {
    return [[self secretStore] loadDataForKey:key];
}

+ (BOOL)saveData:(NSData *)data forKey:(NSString *)key {
    return [[self secretStore] saveData:data forKey:key];
}

+ (BOOL)deleteDataForKey:(NSString *)key {
    return [[self secretStore] deleteDataForKey:key];
}

+ (nullable NSData *)loadIdentitySecret {
    return SSBLoadIdentitySecret();
}

+ (BOOL)saveIdentitySecret:(NSData *)secret {
    return SSBSaveIdentitySecret(secret);
}

+ (BOOL)deleteIdentitySecret {
    return SSBDeleteIdentitySecret();
}

+ (nullable NSData *)loadNetworkKey {
    return [self loadDataForKey:kNetworkKey];
}

+ (BOOL)saveNetworkKey:(NSData *)key {
    return [self saveData:key forKey:kNetworkKey];
}

+ (BOOL)deleteNetworkKey {
    return [self deleteDataForKey:kNetworkKey];
}

+ (NSInteger)loadPublishedMessageCount {
    return SSBLoadPublishedMessageCount();
}

+ (BOOL)savePublishedMessageCount:(NSInteger)count {
    return SSBSavePublishedMessageCount(count);
}

+ (BOOL)clearAll {
    return [[self secretStore] clearAll];
}

+ (nullable NSData *)loadMetafeedSeed {
    return SSBLoadMetafeedSeed();
}

+ (BOOL)saveMetafeedSeed:(NSData *)seed {
    return SSBSaveMetafeedSeed(seed);
}

+ (BOOL)deleteMetafeedSeed {
    return SSBDeleteMetafeedSeed();
}

+ (nullable NSString *)loadMetafeedRootID {
    return SSBLoadMetafeedRootID();
}

+ (BOOL)saveMetafeedRootID:(NSString *)rootID {
    return SSBSaveMetafeedRootID(rootID);
}

+ (BOOL)deleteMetafeedRootID {
    return SSBDeleteMetafeedRootID();
}

+ (BOOL)loadMetafeedAnnounced {
    return SSBLoadMetafeedAnnounced();
}

+ (BOOL)saveMetafeedAnnounced:(BOOL)announced {
    return SSBSaveMetafeedAnnounced(announced);
}

+ (BOOL)deleteMetafeedAnnounced {
    return SSBDeleteMetafeedAnnounced();
}

+ (nullable NSString *)publicIDFromSecret:(NSData *)secret {
    return SSBPublicIDFromSecret(secret);
}

@end
