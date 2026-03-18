#import "SSBHTTPInviteServer.h"
#import "SSBURI.h"
#import <os/log.h>
#import <CommonCrypto/CommonCrypto.h>

static os_log_t server_log;

@interface SSBHTTPInviteServer ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *inviteCodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *claimedInvites;
@property (nonatomic, strong) dispatch_queue_t inviteQueue;
@property (nonatomic, strong) NSURLSession *httpSession;
@property (nonatomic, readwrite) SSBHTTPInvitePrivacyMode privacyMode;
@property (nonatomic, readwrite, copy) NSString *host;
@property (nonatomic, readwrite) NSInteger port;
@property (nonatomic, readwrite, copy, nullable) NSString *multiserverAddress;
@property (nonatomic, readwrite, copy, nullable) NSData *serverPubKey;
@property (nonatomic, strong) NSMutableSet<NSString *> *restrictedFeedIdsSet;
@property (nonatomic, strong) NSMutableSet<NSString *> *communityMemberFeedIdsSet;
@end

@implementation SSBHTTPInviteServer

+ (void)initialize {
    if (self == [SSBHTTPInviteServer class]) {
        server_log = os_log_create("SSB", "HTTPInviteServer");
    }
}

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                       pubKey:(NSData *)pubKey
                 privacyMode:(SSBHTTPInvitePrivacyMode)privacyMode {
    return [self initWithHost:host port:port pubKey:pubKey privacyMode:privacyMode multiserverAddress:nil];
}

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                       pubKey:(NSData *)pubKey
                 privacyMode:(SSBHTTPInvitePrivacyMode)privacyMode
            multiserverAddress:(nullable NSString *)multiserverAddress {
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _serverPubKey = pubKey;
        _privacyMode = privacyMode;
        _multiserverAddress = multiserverAddress;
        _inviteExpirationInterval = 24 * 60 * 60;
        _maxClaimsPerInvite = 1;
        _inviteCodes = [NSMutableDictionary dictionary];
        _claimedInvites = [NSMutableDictionary dictionary];
        _restrictedFeedIdsSet = [NSMutableSet set];
        _communityMemberFeedIdsSet = [NSMutableSet set];
        _inviteQueue = dispatch_queue_create("com.ssb.httpinvite.server", DISPATCH_QUEUE_SERIAL);
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        _httpSession = [NSURLSession sessionWithConfiguration:config];
        
        if (!_multiserverAddress && host && pubKey) {
            NSString *pubKeyBase64 = [pubKey base64EncodedStringWithOptions:0];
            _multiserverAddress = [NSString stringWithFormat:@"net:%@:%ld~shs:%@", host, (long)port, pubKeyBase64];
        }
        
        os_log_info(server_log, "HTTP Invite Server initialized: host=%{public}@, port=%ld, privacy=%d",
                    host, (long)port, (int)privacyMode);
    }
    return self;
}

#pragma mark - Invite Code Generation

- (NSString *)generateInviteCode {
    return [self generateInviteCodeWithMaxClaims:self.maxClaimsPerInvite];
}

- (NSString *)generateInviteCodeWithMaxClaims:(NSInteger)maxClaims {
    NSMutableString *code = [NSMutableString string];
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSUInteger length = alphabet.length;
    
    for (int i = 0; i < 32; i++) {
        uint32_t randomIndex;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomIndex), &randomIndex) != errSecSuccess) {
            randomIndex = arc4random();
        }
        unichar c = [alphabet characterAtIndex:randomIndex % length];
        [code appendFormat:@"%C", c];
    }
    
    NSDate *now = [NSDate date];
    NSDate *expires = [now dateByAddingTimeInterval:self.inviteExpirationInterval];
    
    NSDictionary *inviteInfo = @{
        @"code": code,
        @"createdAt": now,
        @"expiresAt": expires,
        @"maxClaims": @(maxClaims),
        @"claimedCount": @0,
        @"privacyMode": @(self.privacyMode)
    };
    
    dispatch_sync(self.inviteQueue, ^{
        self.inviteCodes[code] = inviteInfo;
        self.claimedInvites[code] = [NSMutableSet set];
    });
    
    os_log_info(server_log, "Generated invite code: %{public}@ (maxClaims: %ld)", code, (long)maxClaims);
    
    if ([self.delegate respondsToSelector:@selector(inviteServer:didGenerateInviteCode:)]) {
        [self.delegate inviteServer:self didGenerateInviteCode:code];
    }
    
    return code;
}

#pragma mark - Invite Code Validation

- (BOOL)validateInviteCode:(NSString *)code {
    if (!code || code.length == 0) {
        return NO;
    }
    
    __block BOOL isValid = NO;
    
    dispatch_sync(self.inviteQueue, ^{
        NSDictionary *info = self.inviteCodes[code];
        if (!info) {
            return;
        }
        
        if ([self isInviteCodeExpired:code]) {
            os_log_info(server_log, "Invite code expired: %{public}@", code);
            return;
        }
        
        if ([self isInviteCodeClaimed:code]) {
            NSInteger maxClaims = [info[@"maxClaims"] integerValue];
            NSInteger claimedCount = [info[@"claimedCount"] integerValue];
            if (claimedCount >= maxClaims) {
                os_log_info(server_log, "Invite code fully claimed: %{public}@", code);
                return;
            }
        }
        
        SSBHTTPInvitePrivacyMode mode = [info[@"privacyMode"] integerValue];
        
        if (mode == SSBHTTPInvitePrivacyModeRestricted) {
            os_log_info(server_log, "Restricted mode - additional validation needed");
            return;
        }
        
        isValid = YES;
    });
    
    return isValid;
}

- (BOOL)isInviteCodeExpired:(NSString *)code {
    __block BOOL isExpired = YES;
    
    dispatch_sync(self.inviteQueue, ^{
        NSDictionary *info = self.inviteCodes[code];
        if (!info) {
            return;
        }
        
        NSDate *expiresAt = info[@"expiresAt"];
        isExpired = [[NSDate date] compare:expiresAt] == NSOrderedDescending;
        
        if (isExpired && [self.delegate respondsToSelector:@selector(inviteServer:inviteCodeExpired:)]) {
            [self.delegate inviteServer:self inviteCodeExpired:code];
        }
    });
    
    return isExpired;
}

- (BOOL)isInviteCodeClaimed:(NSString *)code {
    __block BOOL isClaimed = NO;
    
    dispatch_sync(self.inviteQueue, ^{
        NSDictionary *info = self.inviteCodes[code];
        if (!info) {
            return;
        }
        
        NSInteger maxClaims = [info[@"maxClaims"] integerValue];
        NSInteger claimedCount = [info[@"claimedCount"] integerValue];
        isClaimed = claimedCount >= maxClaims && maxClaims > 0;
    });
    
    return isClaimed;
}

#pragma mark - Invite Claiming

- (nullable NSDictionary *)claimInvite:(NSString *)code forFeedId:(NSString *)feedId error:(NSError **)error {
    __block NSDictionary *result = nil;
    __block NSError *localError = nil;
    
    dispatch_sync(self.inviteQueue, ^{
        NSDictionary *info = self.inviteCodes[code];
        if (!info) {
            localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid invite code"}];
            return;
        }
        
        if ([self isInviteCodeExpired:code]) {
            localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invite code has expired"}];
            return;
        }
        
        SSBHTTPInvitePrivacyMode mode = [info[@"privacyMode"] integerValue];
        
        if (mode == SSBHTTPInvitePrivacyModeRestricted) {
            if (![self isFeedIdAllowed:feedId]) {
                localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                                 code:3
                                             userInfo:@{NSLocalizedDescriptionKey: @"Feed ID not allowed for this invite"}];
                return;
            }
        } else if (mode == SSBHTTPInvitePrivacyModeCommunity) {
            if (![self isFeedIdInCommunity:feedId]) {
                localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                                 code:4
                                             userInfo:@{NSLocalizedDescriptionKey: @"Feed ID must be a community member"}];
                return;
            }
        }
        
        NSMutableSet *claimedFeeds = self.claimedInvites[code];
        if ([claimedFeeds containsObject:feedId]) {
            localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"This invite has already been claimed by this feed ID"}];
            return;
        }
        
        NSInteger maxClaims = [info[@"maxClaims"] integerValue];
        NSInteger claimedCount = [info[@"claimedCount"] integerValue];
        
        if (claimedCount >= maxClaims && maxClaims > 0) {
            localError = [NSError errorWithDomain:@"SSBHTTPInvite"
                                             code:6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invite code has already been used"}];
            return;
        }
        
        [claimedFeeds addObject:feedId];
        
        NSMutableDictionary *updatedInfo = [info mutableCopy];
        updatedInfo[@"claimedCount"] = @(claimedCount + 1);
        updatedInfo[@"lastClaimedAt"] = [NSDate date];
        updatedInfo[@"lastClaimedBy"] = feedId;
        self.inviteCodes[code] = updatedInfo;
        
        os_log_info(server_log, "Invite code %{public}@ claimed by %{public}@", code, feedId);
        
        if ([self.delegate respondsToSelector:@selector(inviteServer:didClaimInviteCode:forFeedId:)]) {
            [self.delegate inviteServer:self didClaimInviteCode:code forFeedId:feedId];
        }
        
        NSString *msaddr = [self getMultiserverAddressForCode:code];
        result = @{
            @"status": @"successful",
            @"multiserverAddress": msaddr ?: @""
        };
    });
    
    if (localError) {
        if (error) {
            *error = localError;
        }
        return nil;
    }
    
    return result;
}

#pragma mark - Multiserver Address

- (nullable NSString *)getMultiserverAddressForCode:(NSString *)code {
    if (self.multiserverAddress) {
        return self.multiserverAddress;
    }
    
    if (self.host && self.serverPubKey) {
        NSString *pubKeyBase64 = [self.serverPubKey base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"net:%@:%ld~shs:%@", self.host, (long)self.port, pubKeyBase64];
    }
    
    return nil;
}

#pragma mark - Privacy Mode Management

- (void)setRestrictedFeedIds:(NSArray<NSString *> *)feedIds {
    dispatch_sync(self.inviteQueue, ^{
        [self.restrictedFeedIdsSet removeAllObjects];
        [self.restrictedFeedIdsSet addObjectsFromArray:feedIds];
    });
}

- (BOOL)isFeedIdAllowed:(NSString *)feedId {
    if (!feedId) {
        return NO;
    }
    
    __block BOOL isAllowed = NO;
    
    dispatch_sync(self.inviteQueue, ^{
        NSString *normalizedId = [self normalizeFeedId:feedId];
        for (NSString *allowedId in self.restrictedFeedIdsSet) {
            if ([[self normalizeFeedId:allowedId] isEqualToString:normalizedId]) {
                isAllowed = YES;
                break;
            }
        }
    });
    
    return isAllowed;
}

- (void)setCommunityMemberFeedIds:(NSArray<NSString *> *)feedIds {
    dispatch_sync(self.inviteQueue, ^{
        [self.communityMemberFeedIdsSet removeAllObjects];
        [self.communityMemberFeedIdsSet addObjectsFromArray:feedIds];
    });
}

- (BOOL)isFeedIdInCommunity:(NSString *)feedId {
    if (!feedId) {
        return NO;
    }
    
    __block BOOL isMember = NO;
    
    dispatch_sync(self.inviteQueue, ^{
        NSString *normalizedId = [self normalizeFeedId:feedId];
        for (NSString *memberId in self.communityMemberFeedIdsSet) {
            if ([[self normalizeFeedId:memberId] isEqualToString:normalizedId]) {
                isMember = YES;
                break;
            }
        }
    });
    
    return isMember;
}

- (NSString *)normalizeFeedId:(NSString *)feedId {
    NSString *normalized = feedId;
    normalized = [normalized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized hasPrefix:@"@"]) {
        normalized = [normalized substringFromIndex:1];
    }
    if ([normalized hasSuffix:@".ed25519"]) {
        normalized = [normalized substringToIndex:normalized.length - 8];
    }
    return normalized;
}

#pragma mark - Invite Info

- (NSDictionary *)getInviteInfo:(NSString *)code {
    __block NSDictionary *info = nil;
    
    dispatch_sync(self.inviteQueue, ^{
        info = [self.inviteCodes[code] copy];
    });
    
    return info;
}

- (void)revokeInviteCode:(NSString *)code {
    dispatch_sync(self.inviteQueue, ^{
        [self.inviteCodes removeObjectForKey:code];
        [self.claimedInvites removeObjectForKey:code];
    });
    
    os_log_info(server_log, "Revoked invite code: %{public}@", code);
}

#pragma mark - Listing

- (NSArray<NSString *> *)listActiveInviteCodes {
    __block NSMutableArray<NSString *> *activeCodes = [NSMutableArray array];
    
    dispatch_sync(self.inviteQueue, ^{
        NSDate *now = [NSDate date];
        for (NSString *code in self.inviteCodes) {
            NSDictionary *info = self.inviteCodes[code];
            NSDate *expiresAt = info[@"expiresAt"];
            NSInteger claimedCount = [info[@"claimedCount"] integerValue];
            NSInteger maxClaims = [info[@"maxClaims"] integerValue];
            
            if ([now compare:expiresAt] == NSOrderedAscending && claimedCount < maxClaims) {
                [activeCodes addObject:code];
            }
        }
    });
    
    return [activeCodes copy];
}

- (NSDictionary<NSString *, NSNumber *> *)getClaimCountsForAllCodes {
    __block NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    
    dispatch_sync(self.inviteQueue, ^{
        for (NSString *code in self.inviteCodes) {
            NSDictionary *info = self.inviteCodes[code];
            counts[code] = info[@"claimedCount"];
        }
    });
    
    return [counts copy];
}

#pragma mark - HTTP Request Handling

- (NSDictionary *)handleGetJoinWithInviteCode:(NSString *)code
                              acceptJSON:(BOOL)acceptJSON
                             submissionURL:(NSString *)submissionURL {
    
    if (![self validateInviteCode:code]) {
        if (acceptJSON) {
            return @{
                @"status": @"failed",
                @"error": @"Invalid or expired invite code"
            };
        }
        
        return @{
            @"isValid": @NO,
            @"html": [self renderHTMLForInvalidInvite:code error:@"Invalid or expired invite code"]
        };
    }
    
    NSString *ssbURI = [NSString stringWithFormat:@"ssb:experimental?action=claim-http-invite&invite=%@&postTo=%@",
                        code, submissionURL];
    
    if (acceptJSON) {
        return @{
            @"status": @"successful",
            @"invite": code,
            @"postTo": submissionURL,
            @"ssbURI": ssbURI,
            @"multiserverAddress": [self getMultiserverAddressForCode:code] ?: @""
        };
    }
    
    NSString *html = [self renderHTMLForValidInvite:code submissionURL:submissionURL];
    
    return @{
        @"isValid": @YES,
        @"html": html,
        @"ssbURI": ssbURI
    };
}

- (NSDictionary *)handlePostClaimWithBody:(NSDictionary *)body {
    NSString *feedId = body[@"id"];
    NSString *inviteCode = body[@"invite"];
    
    if (!feedId || !inviteCode) {
        return @{
            @"status": @"failed",
            @"error": @"Missing required fields: id and invite"
        };
    }
    
    NSError *error = nil;
    NSDictionary *result = [self claimInvite:inviteCode forFeedId:feedId error:&error];
    
    if (error) {
        return @{
            @"status": @"failed",
            @"error": error.localizedDescription
        };
    }
    
    return result;
}

#pragma mark - HTML Rendering

- (NSString *)renderHTMLForValidInvite:(NSString *)code
                        submissionURL:(NSString *)submissionURL {
    NSString *ssbURI = [NSString stringWithFormat:@"ssb:experimental?action=claim-http-invite&invite=%@&postTo=%@",
                        code, submissionURL];
    
    NSString *escapedURI = [ssbURI stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *msaddr = [self getMultiserverAddressForCode:code] ?: @"";
    
    return [NSString stringWithFormat:@"<!DOCTYPE html>\n"
            "<html lang=\"en\">\n"
            "<head>\n"
            "    <meta charset=\"UTF-8\">\n"
            "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
            "    <title>Join Scuttlebutt</title>\n"
            "    <style>\n"
            "        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; "
            "               max-width: 600px; margin: 50px auto; padding: 20px; text-align: center; }\n"
            "        .container { background: #f5f5f5; border-radius: 12px; padding: 30px; }\n"
            "        h1 { color: #333; }\n"
            "        .btn { display: inline-block; background: #007AFF; color: white; padding: 15px 30px; "
            "               border-radius: 8px; text-decoration: none; font-size: 18px; margin: 20px 0; }\n"
            "        .btn:hover { background: #0056b3; }\n"
            "        .info { color: #666; margin-top: 20px; font-size: 14px; }\n"
            "        code { background: #e0e0e0; padding: 2px 6px; border-radius: 4px; }\n"
            "    </style>\n"
            "</head>\n"
            "<body>\n"
            "    <div class=\"container\">\n"
            "        <h1>Welcome to Scuttlebutt!</h1>\n"
            "        <p>Click the button below to claim your invite and connect to the network.</p>\n"
            "        <a href=\"%@\" class=\"btn\">Join Scuttlebutt</a>\n"
            "        <div class=\"info\">\n"
            "            <p>Or use this SSB URI:</p>\n"
            "            <code>%@</code>\n"
            "        </div>\n"
            "        <div class=\"info\">\n"
            "            <p>Server address:</p>\n"
            "            <code>%@</code>\n"
            "        </div>\n"
            "    </div>\n"
            "</body>\n"
            "</html>", escapedURI, ssbURI, msaddr];
}

- (NSString *)renderHTMLForInvalidInvite:(NSString *)code
                                  error:(nullable NSString *)errorMessage {
    return [NSString stringWithFormat:@"<html><body><h1>Invalid Invite</h1><p>The code %@ is invalid or expired.</p><p>%@</p></body></html>",
            code, errorMessage ?: @""];
}

#pragma mark - Alias Resolution (SIP 7)

- (NSString *)renderHTMLForAlias:(NSString *)alias
              multiserverAddress:(NSString *)msAddr
                          userId:(NSString *)userId
                       signature:(NSString *)signature
                          roomId:(NSString *)roomId {
    NSString *ssbUri = [NSString stringWithFormat:@"ssb:experimental?action=consume-alias&alias=%@&userId=%@&signature=%@&roomId=%@&multiserverAddress=%@",
                        [alias stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                        [userId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                        [signature stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                        [roomId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                        [msAddr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    return [NSString stringWithFormat:
            @"<html><head>"
            "<meta name=\"ssb-address\" content=\"%@\">"
            "</head><body>"
            "<h1>SSB Alias: %@</h1>"
            "<p>To consume this alias, open this page in an SSB-compatible client.</p>"
            "<p><a href=\"%@\">Open in SSB Client</a></p>"
            "</body></html>",
            ssbUri, alias, ssbUri];
}

- (NSDictionary<NSString *, id> *)jsonForAlias:(NSString *)alias
                            multiserverAddress:(NSString *)msAddr
                                        userId:(NSString *)userId
                                     signature:(NSString *)signature
                                        roomId:(NSString *)roomId {
    return @{
        @"action": @"consume-alias",
        @"alias": alias,
        @"userId": userId,
        @"signature": signature,
        @"roomId": roomId,
        @"multiserverAddress": msAddr
    };
}

@end
