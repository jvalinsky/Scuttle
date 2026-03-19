#import "SSBKeychain.h"
#import "tweetnacl.h"

@implementation SSBKeychain

+ (NSString *)baseConfigPath {
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/scuttle"];
    [[NSFileManager defaultManager] createDirectoryAtPath:configPath 
                              withIntermediateDirectories:YES 
                                               attributes:@{NSFilePosixPermissions: @(0700)} 
                                                    error:nil];
    return configPath;
}

+ (BOOL)saveData:(NSData *)data toFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:nil];
    if (success) {
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} 
                                         ofItemAtPath:path 
                                                error:nil];
    }
    return success;
}

+ (nullable NSData *)loadDataFromFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    return [NSData dataWithContentsOfFile:path];
}

+ (BOOL)deleteFile:(NSString *)filename {
    NSString *path = [[self baseConfigPath] stringByAppendingPathComponent:filename];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

#pragma mark - Identity

+ (nullable NSData *)loadIdentitySecret {
    return [self loadDataFromFile:@"identity.secret"];
}

+ (BOOL)saveIdentitySecret:(NSData *)secret {
    return [self saveData:secret toFile:@"identity.secret"];
}

+ (BOOL)deleteIdentitySecret {
    return [self deleteFile:@"identity.secret"];
}

#pragma mark - Network Key

+ (nullable NSData *)loadNetworkKey {
    return [self loadDataFromFile:@"network.key"];
}

+ (BOOL)saveNetworkKey:(NSData *)key {
    return [self saveData:key toFile:@"network.key"];
}

+ (BOOL)deleteNetworkKey {
    return [self deleteFile:@"network.key"];
}

#pragma mark - Message Count

+ (NSInteger)loadPublishedMessageCount {
    NSData *data = [self loadDataFromFile:@"msg_count"];
    if (!data) return 0;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [str integerValue];
}

+ (BOOL)savePublishedMessageCount:(NSInteger)count {
    NSString *str = [NSString stringWithFormat:@"%ld", (long)count];
    return [self saveData:[str dataUsingEncoding:NSUTF8StringEncoding] toFile:@"msg_count"];
}

#pragma mark - Utils

+ (BOOL)clearAll {
    return [[NSFileManager defaultManager] removeItemAtPath:[self baseConfigPath] error:nil];
}

+ (nullable NSString *)publicIDFromSecret:(NSData *)secret {
    if (secret.length < 64) return nil;
    uint8_t pk[32];
    // tweetnacl Ed25519 secret is [sk, pk] concatenated
    memcpy(pk, (const uint8_t *)secret.bytes + 32, 32);
    
    NSString *base64 = [[NSData dataWithBytes:pk length:32] base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"@%@.ed25519", base64];
}

#pragma mark - Metafeed

+ (nullable NSData *)loadMetafeedSeed {
    return [self loadDataFromFile:@"metafeed.seed"];
}

+ (BOOL)saveMetafeedSeed:(NSData *)seed {
    return [self saveData:seed toFile:@"metafeed.seed"];
}

+ (BOOL)deleteMetafeedSeed {
    return [self deleteFile:@"metafeed.seed"];
}

+ (nullable NSString *)loadMetafeedRootID {
    NSData *data = [self loadDataFromFile:@"metafeed.root_id"];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)saveMetafeedRootID:(NSString *)rootID {
    return [self saveData:[rootID dataUsingEncoding:NSUTF8StringEncoding] toFile:@"metafeed.root_id"];
}

+ (BOOL)deleteMetafeedRootID {
    return [self deleteFile:@"metafeed.root_id"];
}

+ (BOOL)loadMetafeedAnnounced {
    NSData *data = [self loadDataFromFile:@"metafeed.announced"];
    if (!data) return NO;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [str boolValue];
}

+ (BOOL)saveMetafeedAnnounced:(BOOL)announced {
    NSString *str = announced ? @"YES" : @"NO";
    return [self saveData:[str dataUsingEncoding:NSUTF8StringEncoding] toFile:@"metafeed.announced"];
}

+ (BOOL)deleteMetafeedAnnounced {
    return [self deleteFile:@"metafeed.announced"];
}

@end
