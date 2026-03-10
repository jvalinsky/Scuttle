#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SSBHTTPInvitePrivacyMode) {
    SSBHTTPInvitePrivacyModeOpen,
    SSBHTTPInvitePrivacyModeCommunity,
    SSBHTTPInvitePrivacyModeRestricted
};

@class SSBHTTPInviteServer;

@protocol SSBHTTPInviteServerDelegate <NSObject>
@optional
- (void)inviteServer:(SSBHTTPInviteServer *)server didGenerateInviteCode:(NSString *)code;
- (void)inviteServer:(SSBHTTPInviteServer *)server didClaimInviteCode:(NSString *)code forFeedId:(NSString *)feedId;
- (void)inviteServer:(SSBHTTPInviteServer *)server inviteCodeExpired:(NSString *)code;
@end

@interface SSBHTTPInviteServer : NSObject

@property (nonatomic, weak, nullable) id<SSBHTTPInviteServerDelegate> delegate;
@property (nonatomic, readonly) SSBHTTPInvitePrivacyMode privacyMode;
@property (nonatomic, readonly, copy) NSString *host;
@property (nonatomic, readonly) NSInteger port;
@property (nonatomic, readonly, copy, nullable) NSString *multiserverAddress;
@property (nonatomic, readonly, copy, nullable) NSData *serverPubKey;
@property (nonatomic, readonly) NSTimeInterval inviteExpirationInterval;
@property (nonatomic, readonly) NSInteger maxClaimsPerInvite;

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                  pubKey:(NSData *)pubKey
             privacyMode:(SSBHTTPInvitePrivacyMode)privacyMode;

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                  pubKey:(NSData *)pubKey
             privacyMode:(SSBHTTPInvitePrivacyMode)privacyMode
  multiserverAddress:(nullable NSString *)multiserverAddress;

- (NSString *)generateInviteCode;
- (NSString *)generateInviteCodeWithMaxClaims:(NSInteger)maxClaims;

- (BOOL)validateInviteCode:(NSString *)code;
- (BOOL)isInviteCodeExpired:(NSString *)code;
- (BOOL)isInviteCodeClaimed:(NSString *)code;

- (nullable NSDictionary<NSString *, id> *)claimInvite:(NSString *)code forFeedId:(NSString *)feedId error:(NSError **)error;

- (nullable NSString *)getMultiserverAddressForCode:(NSString *)code;

- (void)setRestrictedFeedIds:(NSArray<NSString *> *)feedIds;
- (BOOL)isFeedIdAllowed:(NSString *)feedId;

- (void)setCommunityMemberFeedIds:(NSArray<NSString *> *)feedIds;
- (BOOL)isFeedIdInCommunity:(NSString *)feedId;

- (NSDictionary<NSString *, id> *)getInviteInfo:(NSString *)code;

- (void)revokeInviteCode:(NSString *)code;

- (NSArray<NSString *> *)listActiveInviteCodes;
- (NSDictionary<NSString *, NSNumber *> *)getClaimCountsForAllCodes;

@property (nonatomic, readonly) NSURLSession *httpSession;

- (NSDictionary<NSString *, id> *)handleGetJoinWithInviteCode:(NSString *)code
                             acceptJSON:(BOOL)acceptJSON
                            submissionURL:(NSString *)submissionURL;

- (NSDictionary<NSString *, id> *)handlePostClaimWithBody:(NSDictionary<NSString *, id> *)body;

- (NSString *)renderHTMLForValidInvite:(NSString *)code
                        submissionURL:(NSString *)submissionURL;

- (NSString *)renderHTMLForInvalidInvite:(NSString *)code
                                  error:(nullable NSString *)errorMessage;

@end

NS_ASSUME_NONNULL_END
