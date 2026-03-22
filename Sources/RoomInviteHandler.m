#import "RoomInviteHandler.h"
#import "RoomStorage.h"
#import "SSBURLSessionCompat.h"
#import "SSBLogCompat.h"

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
    os_log_info(invite_log, "Parsing invite code: %{public}@", inviteString);
    NSString *trimmed = [inviteString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Pattern 1: host:port:pubkey:token
    NSArray *parts = [trimmed componentsSeparatedByString:@":"];
    if (parts.count >= 4) {
        NSString *host = parts[0];
        NSInteger port = [parts[1] integerValue];
        NSString *pubKeyStr = parts[2];
        NSString *token = parts[3];
        
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
    
    // Pattern 3: Legacy multiserver invite: net:host:port~shs:pubkey:token
    if ([trimmed containsString:@"~shs:"]) {
        NSArray *shsParts = [trimmed componentsSeparatedByString:@"~shs:"];
        if (shsParts.count == 2) {
            NSString *netPart = shsParts[0];
            NSString *shsAndToken = shsParts[1];
            NSArray *netComponents = [netPart componentsSeparatedByString:@":"];
            NSArray *stComponents = [shsAndToken componentsSeparatedByString:@":"];
            
            if (netComponents.count >= 3 && stComponents.count >= 2) {
                NSString *host = netComponents[1];
                NSInteger port = [netComponents[2] integerValue];
                NSString *pubKeyStr = stComponents[0];
                NSString *token = stComponents[1];
                
                pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@"@" withString:@""];
                pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
                
                NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
                if (pubKeyData && host.length > 0 && port > 0) {
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
    if (self == [RoomInviteHandler class]) {
        invite_log = os_log_create("SSB", "Invite");
    }
}

+ (void)resolveHTTPSInvite:(NSString *)url 
                   localId:(NSString *)localId 
                completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion {
    os_log_info(invite_log, "Resolving HTTPS invite: %{public}@", url);
    NSURL *targetURL = [NSURL URLWithString:url];
    if (!targetURL) {
        completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }
    
    NSArray<RoomConfig *> *existingRooms = [RoomStorage listRooms];
    for (RoomConfig *rc in existingRooms) {
        if ([rc.host isEqualToString:targetURL.host]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(rc, nil);
            });
            return;
        }
    }
    
    NSURLComponents *jsonURLComponents = [NSURLComponents componentsWithURL:targetURL resolvingAgainstBaseURL:NO];
    NSMutableArray *queryItems = [jsonURLComponents.queryItems mutableCopy] ?: [NSMutableArray array];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"encoding" value:@"json"]];
    jsonURLComponents.queryItems = queryItems;
    
    [[[NSURLSession sharedSession] dataTaskWithURL:jsonURLComponents.URL completionHandler:^(NSData *jsonData, NSURLResponse *jsonRes, NSError *jsonErr) {
        if (!jsonErr && jsonData) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && (json[@"invite"] || json[@"token"]) && json[@"postTo"]) {
                [self performClaim:json[@"invite"] ?: json[@"token"] 
                            postTo:json[@"postTo"] 
                           localId:localId 
                         targetURL:targetURL 
                fallbackAddress:json[@"multiserverAddress"] 
                 fallbackPubKey:json[@"pubkey"] ?: json[@"publicKey"] 
                        completion:completion];
                return;
            }
        }
        
        [[[NSURLSession sharedSession] dataTaskWithURL:targetURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
                return;
            }
            
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *uri = nil;
            NSArray *patterns = @[@"ssb:experimental\\?action=claim-http-invite[^\"']+", @"ssb://experimental\\?action=claim-http-invite[^\"']+"];
            
            for (NSString *pattern in patterns) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
                if (match) { uri = [html substringWithRange:match.range]; break; }
            }
            
            if (!uri) {
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
                if ([item.name isEqualToString:@"invite"] || [item.name isEqualToString:@"token"]) invite = item.value;
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
            
            NSString *scrapedMsa = nil;
            NSRegularExpression *regexMsa = [NSRegularExpression regularExpressionWithPattern:@"net:[^: \t\n\r\"']+:[0-9]+~shs:[A-Za-z0-9+/=]+" options:0 error:nil];
            NSTextCheckingResult *matchMsa = [regexMsa firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            if (matchMsa) scrapedMsa = [html substringWithRange:matchMsa.range];
            
            NSString *scrapedPk = nil;
            NSRegularExpression *regexPk = [NSRegularExpression regularExpressionWithPattern:@"@[A-Za-z0-9+/=]{43,44}\\.ed25519" options:0 error:nil];
            NSTextCheckingResult *matchPk = [regexPk firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            if (matchPk) {
                scrapedPk = [html substringWithRange:matchPk.range];
                scrapedPk = [[scrapedPk stringByReplacingOccurrencesOfString:@"@" withString:@""] stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
            }

            [self performClaim:invite postTo:postTo localId:localId targetURL:targetURL fallbackAddress:msaFromUrl ?: scrapedMsa fallbackPubKey:pkFromUrl ?: scrapedPk completion:completion];
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
    NSURL *postURL = [NSURL URLWithString:postTo];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:postURL];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"invite": invite, @"id": localId};
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *resData, NSURLResponse *res, NSError *resErr) {
            NSDictionary *json = resData ? [NSJSONSerialization JSONObjectWithData:resData options:0 error:nil] : nil;
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)res;
            BOOL isSuccess = (resErr == nil && httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
            
            if (!isSuccess) {
                NSString *serverError = [json isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
                BOOL isAlreadyRegistered = (serverError && ([serverError containsString:@"already on the list"] || [serverError containsString:@"already registered"]));

                if (isAlreadyRegistered) {
                    NSString *msa = [json isKindOfClass:[NSDictionary class]] ? json[@"multiserverAddress"] : nil;
                    if (!msa || msa.length == 0) msa = fallbackAddress;
                    if (!msa || msa.length == 0) {
                        NSString *pk = [json isKindOfClass:[NSDictionary class]] ? (json[@"pubkey"] ?: json[@"publicKey"]) : fallbackPubKey;
                        if (pk && targetURL.host) msa = [NSString stringWithFormat:@"net:%@:%ld~shs:%@", targetURL.host, (long)(targetURL.port ? [targetURL.port integerValue] : 8008), pk];
                    }
                    if (msa) { [self parseAndCompleteWithMSA:msa invite:invite localId:localId completion:completion]; return; }
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, resErr ?: [NSError errorWithDomain:@"SSBInvite" code:-5 userInfo:@{NSLocalizedDescriptionKey: serverError ?: @"Claim failed"}]);
                });
                return;
            }
            
            NSString *msa = [json isKindOfClass:[NSDictionary class]] ? json[@"multiserverAddress"] : fallbackAddress;
            if (!msa || msa.length == 0) {
                NSString *pk = [json isKindOfClass:[NSDictionary class]] ? (json[@"pubkey"] ?: json[@"publicKey"]) : fallbackPubKey;
                if (pk && targetURL.host) msa = [NSString stringWithFormat:@"net:%@:%ld~shs:%@", targetURL.host, (long)(targetURL.port ? [targetURL.port integerValue] : 8008), pk];
            }
            if (msa) [self parseAndCompleteWithMSA:msa invite:invite localId:localId completion:completion];
            else dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"No multiserver address found"}]); });
        }] resume];
}

+ (void)parseAndCompleteWithMSA:(NSString *)msa 
                          invite:(NSString *)invite 
                         localId:(NSString *)localId 
                      completion:(void (^)(RoomConfig * _Nullable config, NSError * _Nullable error))completion {
    NSArray *parts = [msa componentsSeparatedByString:@"~"];
    if (parts.count < 2) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Malformed MSA"}]); });
        return;
    }
    
    NSArray *netComponents = [parts[0] componentsSeparatedByString:@":"];
    if (netComponents.count < 3) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Invalid network part"}]); });
        return;
    }
    
    NSString *pubKeyStr = [[parts[1] stringByReplacingOccurrencesOfString:@"shs:" withString:@""] stringByReplacingOccurrencesOfString:@"@" withString:@""];
    pubKeyStr = [pubKeyStr stringByReplacingOccurrencesOfString:@".ed25519" withString:@""];
    NSData *pubKeyData = [[NSData alloc] initWithBase64EncodedString:pubKeyStr options:0];
    
    if (netComponents[1] && [netComponents[2] integerValue] > 0 && pubKeyData) {
        RoomConfig *config = [[RoomConfig alloc] initWithHost:netComponents[1] port:[netComponents[2] integerValue] pubKey:pubKeyData];
        config.inviteToken = invite;
        config.usedHTTPInvite = YES;
        config.httpInviteClaimIdentity = localId;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(config, nil); });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"SSBInvite" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse MSA"}]); });
    }
}

@end