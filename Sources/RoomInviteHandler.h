#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RoomConfig : NSObject <NSSecureCoding>
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *host;
@property (nonatomic) NSInteger port;
@property (strong, nonatomic) NSData *serverPubKey;
@property (strong, nonatomic, nullable) NSString *inviteToken;
/// Set to YES when this config was created via HTTP invite (SIP 5) redemption.
/// When YES, the client should skip tunnel.announce if the room supports "httpInvite" feature.
@property (nonatomic) BOOL usedHTTPInvite;
/// The SSB ID (e.g., @base64key.ed25519) that was used to claim the HTTP invite.
/// This MUST match the identity used when initializing SSBRoomClient.
@property (strong, nonatomic, nullable) NSString *httpInviteClaimIdentity;

- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port pubKey:(NSData *)pubKey;
@end

@interface RoomInviteHandler : NSObject
+ (nullable RoomConfig *)parseInviteCode:(NSString *)inviteString;
+ (void)resolveHTTPSInvite:(NSString *)url 
                   localId:(NSString *)localId 
                completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
