#import "RoomInviteHandler.h"
#import "RoomStorage.h"
#import <os/log.h>

static os_log_t invite_log;

@implementation RoomConfig

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port pubKey:(NSData *)pubKey {
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _serverPubKey = pubKey;
        _name = host; // Default name
        _usedHTTPInvite = NO; // Default to NO
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_host forKey:@"host"];
    [coder encodeInteger:_port forKey:@"port"];
    [coder encodeObject:_serverPubKey forKey:@"serverPubKey"];
    [coder encodeObject:_inviteToken forKey:@"inviteToken"];
    [coder encodeBool:_usedHTTPInvite forKey:@"usedHTTPInvite"];
    [coder encodeObject:_httpInviteClaimIdentity forKey:@"httpInviteClaimIdentity"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _host = [coder decodeObjectOfClass:[NSString class] forKey:@"host"];
        _port = [coder decodeIntegerForKey:@"port"];
        _serverPubKey = [coder decodeObjectOfClass:[NSData class] forKey:@"serverPubKey"];
        _inviteToken = [coder decodeObjectOfClass:[NSString class] forKey:@"inviteToken"];
        _usedHTTPInvite = [coder decodeBoolForKey:@"usedHTTPInvite"];
        _httpInviteClaimIdentity = [coder decodeObjectOfClass:[NSString class] forKey:@"httpInviteClaimIdentity"];
    }
    return self;
}

@end

@implementation RoomInviteHandler

+ (nullable RoomConfig *)parseInviteCode:(NSString *)inviteString {
    // Basic support for host:port:pubkey:token
    // Also support ssb:room-invite:token@host:port:pubkey
    
    NSString *trimmed = [inviteString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Pattern 1: host:port:pubkey:token
    NSArray *parts = [trimmed componentsSeparatedByString:@":"];
    if (parts.count >= 4) {
        NSString *host = parts[0];
        NSInteger port = [parts[1] integerValue];
        NSString *pubKeyStr = parts[2];
        NSString *token = parts[3];
        
        // Clean pubkey string (remove @ and .ed25519 if present)
        pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@"@" withString:@""];
        pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
        
        NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
        if (pubKeyData && host.length > 0 && port > 0) {
            RoomConfig *config = [[RoomConfig alloc] initWithHost:host port:port pubKey:pubKeyData];
            config.inviteToken = token;
            return config;
        }
    }
    
    // Pattern 2: ssb:room-invite:token@host:port:pubkey
    if ([trimmed hasPrefix:@"ssb:room-invite:"]) {
        NSString *body = [trimmed substringFromIndex:16];
        NSArray *atParts = [body componentsSeparatedByString:@"@"];
        if (atParts.count == 2) {
            NSString *token = atParts[0];
            NSArray *hostParts = [atParts[1] componentsSeparatedByString:@":"];
            if (hostParts.count >= 3) {
                NSString *host = hostParts[0];
                NSInteger port = [hostParts[1] integerValue];
                NSString *pubKeyStr = hostParts[2];
                
                pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@"@" withString:@""];
                pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
                
                NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
                if (pubKeyData) {
                    RoomConfig *config = [[RoomConfig alloc] initWithHost:host port:port pubKey:pubKeyData];
                    config.inviteToken = token;
                    return config;
                }
            }
        }
    }
    
    return nil;
}

+ (void)initialize {
    invite_log = os_log_create("SSB", "Invite");
}

/**
 * Resolves an HTTP invite URL (SIP 5) by fetching the join page, extracting the claim link,
 * and POSTing the user's SSB ID to the claim endpoint.
 *
 * IMPORTANT: The localId parameter MUST be the same SSB identity that will be used for the
 * subsequent SSB connection to the room server. If a different identity is used for the
 * SSB connection, the room server will reject it as unauthorized per SIP 5 step 7.
 *
 * @param url The HTTPS invite URL (e.g., https://room.example.com/join?invite=abc123)
 * @param localId The SSB ID (e.g., @base64key.ed25519) that will be used for both the HTTP claim
 *                and the subsequent SSB connection. This identity MUST match the identity used
 *                when initializing SSBRoomClient.
 * @param completion Called with a RoomConfig (with usedHTTPInvite=YES) on success, or an error on failure.
 */
+ (void)resolveHTTPSInvite:(NSString *)url 
                   localId:(NSString *)localId 
                completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion {
    os_log_info(invite_log, "Resolving HTTPS invite: %{public}@", url);
    NSURL *targetURL = [NSURL URLWithString:url];
    if (!targetURL) {
        completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }
    
    // 0. Check if we already have this room registered
    NSArray<RoomConfig *> *existingRooms = [RoomStorage listRooms];
    for (RoomConfig *rc in existingRooms) {
        if ([rc.host isEqualToString:targetURL.host]) {
            os_log_info(invite_log, "Found existing local config for %{public}@", targetURL.host);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(rc, nil);
            });
            return;
        }
    }
    
    // 1. Try fetching with encoding=json first (SIP 005 programmatic façade)
    NSURLComponents *jsonURLComponents = [NSURLComponents componentsWithURL:targetURL resolvingAgainstBaseURL:NO];
    NSMutableArray *queryItems = [jsonURLComponents.queryItems mutableCopy] ?: [NSMutableArray array];
    BOOL hasEncoding = NO;
    for (NSURLQueryItem *item in queryItems) {
        if ([item.name isEqualToString:@"encoding"]) {
            hasEncoding = YES;
            break;
        }
    }
    if (!hasEncoding) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"encoding" value:@"json"]];
        jsonURLComponents.queryItems = queryItems;
    }
    
    [[[NSURLSession sharedSession] dataTaskWithURL:jsonURLComponents.URL completionHandler:^(NSData *jsonData, NSURLResponse *jsonRes, NSError *jsonErr) {
        if (!jsonErr && jsonData) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"invite"] && json[@"postTo"]) {
                os_log_info(invite_log, "Successfully resolved invite via JSON façade");
                // Extract possible multiserver address or pubkey from facade for fallback reconstruction
                NSString *msa = json[@"multiserverAddress"];
                NSString *pk = json[@"pubkey"] ?: json[@"publicKey"];
                [self performClaim:json[@"invite"] 
                            postTo:json[@"postTo"] 
                           localId:localId 
                         targetURL:targetURL 
                fallbackAddress:msa 
                 fallbackPubKey:pk 
                        completion:completion];
                return;
            }
        }
        
        // 2. Fall back to HTML parsing if JSON fails
        os_log_info(invite_log, "JSON façade failed or not supported, falling back to HTML parsing");
    
        [[[NSURLSession sharedSession] dataTaskWithURL:targetURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }
            
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            // Robust check for the experimental claim link
            NSString *uri = nil;
            NSArray *patterns = @[
                @"ssb:experimental\\?action=claim-http-invite[^\"']+",
                @"ssb://experimental\\?action=claim-http-invite[^\"']+"
            ];
            
            for (NSString *pattern in patterns) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
                if (match) {
                    uri = [html substringWithRange:match.range];
                    break;
                }
            }
            
            if (!uri) {
                os_log_error(invite_log, "Could not find claim link in HTML. HTML sample: %{public}@", [html substringToIndex:MIN(html.length, 500)]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Could not find claim link in HTML"}]);
                });
                return;
            }
            
            uri = [uri stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
            NSURLComponents *components = [NSURLComponents componentsWithString:uri];
            NSString *invite = nil;
            NSString *postTo = nil;
            NSString *msaFromUrl = nil;
            NSString *pkFromUrl = nil;
            for (NSURLQueryItem *item in components.queryItems) {
                if ([item.name isEqualToString:@"invite"]) invite = item.value;
                if ([item.name isEqualToString:@"postTo"]) postTo = item.value;
                if ([item.name isEqualToString:@"multiserverAddress"]) msaFromUrl = item.value;
                if ([item.name isEqualToString:@"pubkey"] || [item.name isEqualToString:@"publicKey"]) pkFromUrl = item.value;
            }
            
            if (!invite || !postTo) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"Missing parameters in claim link"}]);
                });
                return;
            }
            
            // Scrape multiserver address from HTML as a fallback for recovery (e.g. net:host:port~shs:pubkey)
            NSString *patternMsa = @"net:[^: \t\n\r\"']+:[0-9]+~shs:[A-Za-z0-9+/=]+";
            NSRegularExpression *regexMsa = [NSRegularExpression regularExpressionWithPattern:patternMsa options:0 error:nil];
            NSTextCheckingResult *matchMsa = [regexMsa firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            NSString *scrapedMsa = nil;
            if (matchMsa) {
                scrapedMsa = [html substringWithRange:matchMsa.range];
                os_log_info(invite_log, "Scraped multiserver address from HTML: %{public}@", scrapedMsa);
            }
            
            // Scrape Scuttlebutt ID (pubkey) from HTML as a fallback
            NSString *patternPk = @"@[A-Za-z0-9+/=]{43,44}\\.ed25519";
            NSRegularExpression *regexPk = [NSRegularExpression regularExpressionWithPattern:patternPk options:0 error:nil];
            NSTextCheckingResult *matchPk = [regexPk firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            NSString *scrapedPk = nil;
            if (matchPk) {
                scrapedPk = [html substringWithRange:matchPk.range];
                os_log_info(invite_log, "Scraped pubkey from HTML: %{public}@", scrapedPk);
                // Clean it up for SHS use (remove @ and .ed25519)
                scrapedPk = [scrapedPk stringByReplacingOccurrencesOfString:@"@" withString:@""];
                scrapedPk = [scrapedPk stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
            }

            [self performClaim:invite 
                        postTo:postTo 
                       localId:localId 
                     targetURL:targetURL 
               fallbackAddress:msaFromUrl ?: scrapedMsa 
                fallbackPubKey:pkFromUrl ?: scrapedPk 
                    completion:completion];
        }] resume];
    }] resume];
}

+ (void)performClaim:(NSString *)invite 
              postTo:(NSString *)postTo 
             localId:(NSString *)localId 
           targetURL:(NSURL *)targetURL 
     fallbackAddress:(nullable NSString *)fallbackAddress
      fallbackPubKey:(nullable NSString *)fallbackPubKey
          completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion {
    // 3. POST to redemption URL
    NSURL *postURL = [NSURL URLWithString:postTo];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:postURL];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"invite": invite, @"id": localId};
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *resData, NSURLResponse *res, NSError *resErr) {
            NSString *responseStr = resData ? [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding] : nil;
            NSDictionary *json = nil;
            if (resData) {
                json = [NSJSONSerialization JSONObjectWithData:resData options:0 error:nil];
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)res;
            BOOL isSuccess = (resErr == nil && httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
            
            if (!isSuccess) {
                os_log_info(invite_log, "HTTP claim failed (status %ld). Checking fallbacks for %{public}@", (long)httpResponse.statusCode, targetURL.host);
                
                // Fallback 1: Check local storage
                NSArray<RoomConfig *> *existingRooms = [RoomStorage listRooms];
                for (RoomConfig *rc in existingRooms) {
                    if ([rc.host isEqualToString:targetURL.host]) {
                        os_log_info(invite_log, "Found existing local config for %{public}@", targetURL.host);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(rc, nil);
                        });
                        return;
                    }
                }
                
                // Fallback 2: Reconstruct from scraped metadata
                NSString *msa = [json isKindOfClass:[NSDictionary class]] ? json[@"multiserverAddress"] : nil;
                if (!msa || msa.length == 0) msa = fallbackAddress;
                
                if (!msa || msa.length == 0) {
                    NSString *pk = [json isKindOfClass:[NSDictionary class]] ? (json[@"pubkey"] ?: json[@"publicKey"]) : nil;
                    if (!pk) pk = fallbackPubKey;
                    
                    if (pk && targetURL.host) {
                        msa = [NSString stringWithFormat:@"net:%@:%ld~shs:%@", targetURL.host, (long)(targetURL.port ? [targetURL.port integerValue] : 8008), pk];
                        os_log_info(invite_log, "Reconstructed MSA from fallbacks: %{public}@", msa);
                    }
                }
                
                if (msa && msa.length > 0) {
                    [self parseAndCompleteWithMSA:msa invite:invite localId:localId completion:completion];
                    return;
                }
                
                // Fallback 3: Handle specific "already on the list" error even if partial reconstruction failed
                NSString *serverError = [json isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
                if (serverError && [serverError containsString:@"already on the list"]) {
                    // We already checked storage, so if we're here we don't have it and reconstruction failed.
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *msg = [NSString stringWithFormat:@"You are already registered with %@, but your local configuration is missing and could not be reconstructed.", targetURL.host];
                        completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-5 userInfo:@{NSLocalizedDescriptionKey: msg}]);
                    });
                    return;
                }
                
                // No fallbacks worked, return original error or server error
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *finalErr = resErr;
                    if (!finalErr) {
                        NSString *errMsg = serverError ?: [NSString stringWithFormat:@"Server returned status %ld", (long)httpResponse.statusCode];
                        finalErr = [NSError errorWithDomain:@"SSBInvite" code:-5 userInfo:@{NSLocalizedDescriptionKey: errMsg}];
                    }
                    completion(nil, finalErr);
                });
                return;
            }
            
            // If we're here, the claim was successful!
            NSString *msa = [json isKindOfClass:[NSDictionary class]] ? json[@"multiserverAddress"] : nil;
            if (!msa || msa.length == 0) msa = fallbackAddress;
            
            if (!msa || msa.length == 0) {
                NSString *pk = [json isKindOfClass:[NSDictionary class]] ? (json[@"pubkey"] ?: json[@"publicKey"]) : nil;
                if (!pk) pk = fallbackPubKey;
                
                if (pk && targetURL.host) {
                    msa = [NSString stringWithFormat:@"net:%@:%ld~shs:%@", targetURL.host, (long)(targetURL.port ? [targetURL.port integerValue] : 8008), pk];
                }
            }
            
            if (msa && msa.length > 0) {
                [self parseAndCompleteWithMSA:msa invite:invite localId:localId completion:completion];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Claim succeeded but no multiserver address found"}]);
                });
            }
        }] resume];
}

+ (void)parseAndCompleteWithMSA:(NSString *)msa 
                         invite:(NSString *)invite 
                        localId:(NSString *)localId 
                     completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion {
    NSArray *parts = [msa componentsSeparatedByString:@"~"];
    if (parts.count < 2) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Malformed multiserver address: %@", msa]
            }]);
        });
        return;
    }
    
    NSString *netPart = parts[0];
    NSString *shsPart = parts[1];
    
    NSArray *netComponents = [netPart componentsSeparatedByString:@":"];
    if (netComponents.count < 3) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid network part in address: %@", netPart]}]);
        });
        return;
    }
    NSString *host = netComponents[1];
    NSInteger port = [netComponents[2] integerValue];
    
    NSString *pubKeyStr = [shsPart stringByReplacingOccurrencesOfString:@"shs:" withString:@""];
    NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
    
    if (host && port > 0 && pubKeyData) {
        RoomConfig *config = [[RoomConfig alloc] initWithHost:host port:port pubKey:pubKeyData];
        config.inviteToken = invite;
        config.usedHTTPInvite = YES;
        config.httpInviteClaimIdentity = localId;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(config, nil);
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse multiserver address"}]);
        });
    }
}

@end
