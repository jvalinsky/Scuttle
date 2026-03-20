#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SSBSecretStore <NSObject>
- (nullable NSData *)loadDataForKey:(NSString *)key;
- (BOOL)saveData:(NSData *)data forKey:(NSString *)key;
- (BOOL)deleteDataForKey:(NSString *)key;
- (BOOL)clearAll;
@end

@interface SSBAppleKeychainSecretStore : NSObject <SSBSecretStore>
@end

@interface SSBFileSecretStore : NSObject <SSBSecretStore>
- (instancetype)initWithBaseDirectory:(nullable NSString *)baseDirectory;
@property (nonatomic, readonly, copy) NSString *baseDirectory;
@end

FOUNDATION_EXPORT id<SSBSecretStore> SSBCreateDefaultSecretStore(void);
FOUNDATION_EXPORT id<SSBSecretStore> SSBSharedSecretStore(void);

FOUNDATION_EXPORT NSString * _Nullable SSBPublicIDFromSecret(NSData *secret);
FOUNDATION_EXPORT NSData * _Nullable SSBLoadIdentitySecret(void);
FOUNDATION_EXPORT BOOL SSBSaveIdentitySecret(NSData *secret);
FOUNDATION_EXPORT BOOL SSBDeleteIdentitySecret(void);
FOUNDATION_EXPORT NSInteger SSBLoadPublishedMessageCount(void);
FOUNDATION_EXPORT BOOL SSBSavePublishedMessageCount(NSInteger count);
FOUNDATION_EXPORT NSData * _Nullable SSBLoadMetafeedSeed(void);
FOUNDATION_EXPORT BOOL SSBSaveMetafeedSeed(NSData *seed);
FOUNDATION_EXPORT BOOL SSBDeleteMetafeedSeed(void);
FOUNDATION_EXPORT NSString * _Nullable SSBLoadMetafeedRootID(void);
FOUNDATION_EXPORT BOOL SSBSaveMetafeedRootID(NSString *rootID);
FOUNDATION_EXPORT BOOL SSBDeleteMetafeedRootID(void);
FOUNDATION_EXPORT BOOL SSBLoadMetafeedAnnounced(void);
FOUNDATION_EXPORT BOOL SSBSaveMetafeedAnnounced(BOOL announced);
FOUNDATION_EXPORT BOOL SSBDeleteMetafeedAnnounced(void);

NS_ASSUME_NONNULL_END
