#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "RoomInviteHandler.h"

// ── Private method exposure ──────────────────────────────────────────────────
@interface RoomInviteHandler (NetworkTest)
+ (void)performClaim:(NSString *)invite
               postTo:(NSString *)postTo
              localId:(NSString *)localId
            targetURL:(NSURL *)targetURL
      fallbackAddress:(nullable NSString *)fallbackAddress
       fallbackPubKey:(nullable NSString *)fallbackPubKey
           completion:(void (^)(RoomConfig * _Nullable, NSError * _Nullable))completion;
@end

// ── Mock NSURLProtocol ───────────────────────────────────────────────────────
typedef void (^SSBMockNetBlock)(NSURLRequest *request, id<NSURLProtocolClient> client, NSURLProtocol *protocol);
static NSMutableArray<SSBMockNetBlock> *sMockQueue;

@interface SSBInviteMockURLProtocol : NSURLProtocol
@end
@implementation SSBInviteMockURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return sMockQueue.count > 0; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b { return NO; }
- (void)startLoading {
    if (sMockQueue.count > 0) {
        SSBMockNetBlock block = sMockQueue.firstObject;
        [sMockQueue removeObjectAtIndex:0];
        block(self.request, self.client, self);
    }
}
- (void)stopLoading {}
@end

// ── Session swizzle ──────────────────────────────────────────────────────────
static NSURLSession *sMockURLSession;
@interface NSURLSession (SSBInviteMock)
+ (NSURLSession *)ssb_inviteMockSharedSession;
@end
@implementation NSURLSession (SSBInviteMock)
+ (NSURLSession *)ssb_inviteMockSharedSession { return sMockURLSession; }
@end

static void installInviteMock(void) {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.protocolClasses = @[[SSBInviteMockURLProtocol class]];
    sMockURLSession = [NSURLSession sessionWithConfiguration:cfg];
    Method orig = class_getClassMethod([NSURLSession class], @selector(sharedSession));
    Method mock = class_getClassMethod([NSURLSession class], @selector(ssb_inviteMockSharedSession));
    method_exchangeImplementations(orig, mock);
}

static void uninstallInviteMock(void) {
    Method orig = class_getClassMethod([NSURLSession class], @selector(sharedSession));
    Method mock = class_getClassMethod([NSURLSession class], @selector(ssb_inviteMockSharedSession));
    method_exchangeImplementations(orig, mock);
    sMockURLSession = nil;
}

// ── Queue helpers ────────────────────────────────────────────────────────────
static void enqueueJSON(NSInteger status, id _Nullable body) {
    [sMockQueue addObject:^(NSURLRequest *req, id<NSURLProtocolClient> client, NSURLProtocol *proto) {
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:status
            HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        [client URLProtocol:proto didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (body) [client URLProtocol:proto didLoadData:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
        [client URLProtocolDidFinishLoading:proto];
    }];
}

static void enqueueHTML(NSInteger status, NSString * _Nullable html) {
    [sMockQueue addObject:^(NSURLRequest *req, id<NSURLProtocolClient> client, NSURLProtocol *proto) {
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:status
            HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"text/html"}];
        [client URLProtocol:proto didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (html) [client URLProtocol:proto didLoadData:[html dataUsingEncoding:NSUTF8StringEncoding]];
        [client URLProtocolDidFinishLoading:proto];
    }];
}

static void enqueueNonJSON(NSInteger status) {
    [sMockQueue addObject:^(NSURLRequest *req, id<NSURLProtocolClient> client, NSURLProtocol *proto) {
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:status
            HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [client URLProtocol:proto didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [client URLProtocol:proto didLoadData:[@"ok" dataUsingEncoding:NSUTF8StringEncoding]];
        [client URLProtocolDidFinishLoading:proto];
    }];
}

static void enqueueNetworkError(void) {
    [sMockQueue addObject:^(NSURLRequest *req, id<NSURLProtocolClient> client, NSURLProtocol *proto) {
        [client URLProtocol:proto didFailWithError:
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
    }];
}

// ── Constants ────────────────────────────────────────────────────────────────
static NSString * const kNetPubKey  = @"LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
static NSString * const kNetMSA     = @"net:room.example.com:8008~shs:LN7fGMNy+cUu2ZxFY2MP6rra3SM2WnaZiOV2LDXHoGU=";
static NSString * const kClaimURL   = @"https://room.example.com/invite";
static NSString * const kPostTo     = @"https://room.example.com/claim";
static NSString * const kPostToEnc  = @"https%3A%2F%2Froom.example.com%2Fclaim";

// ── Tests ────────────────────────────────────────────────────────────────────
@interface RoomInviteHandlerNetworkTests : XCTestCase
@end

@implementation RoomInviteHandlerNetworkTests

- (void)setUp {
    [super setUp];
    sMockQueue = [NSMutableArray array];
    installInviteMock();
}

- (void)tearDown {
    uninstallInviteMock();
    sMockQueue = nil;
    [super tearDown];
}

// MARK: - resolveHTTPSInvite: invalid URL

- (void)testResolveHTTPSInvite_invalidURL_returnsError {
    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:@"not a url \n\r" localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertNotNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

// MARK: - resolveHTTPSInvite: JSON path

- (void)testResolveHTTPSInvite_jsonPath_inviteKey_success {
    enqueueJSON(200, @{@"invite": @"tok", @"postTo": kPostTo});
    enqueueJSON(200, @{@"multiserverAddress": kNetMSA});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            XCTAssertEqualObjects(config.host, @"room.example.com");
            XCTAssertEqual(config.port, 8008);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_jsonPath_tokenKey_success {
    // Some servers use "token" instead of "invite"
    enqueueJSON(200, @{@"token": @"tok", @"postTo": kPostTo});
    enqueueJSON(200, @{@"multiserverAddress": kNetMSA});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

// MARK: - resolveHTTPSInvite: HTML fallback path

- (void)testResolveHTTPSInvite_htmlPath_noClaimLink_returnsError {
    enqueueHTML(200, @"<html>not json</html>");          // JSON req: non-JSON falls through
    enqueueHTML(200, @"<html><body>nothing</body></html>"); // HTML req: no claim link

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertEqual(error.code, -2);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_htmlPath_jsonNetworkError_noLink_returnsError {
    enqueueNetworkError();                               // JSON req fails
    enqueueHTML(200, @"<html><body>nothing</body></html>"); // HTML req: no claim link

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertEqual(error.code, -2);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_htmlPath_htmlNetworkError_returnsError {
    enqueueHTML(200, @"<html></html>"); // JSON falls through
    enqueueNetworkError();              // HTML req fails

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertNotNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_htmlPath_claimLinkMissingInviteAndPostTo_returnsError {
    NSString *html = @"<html><body>"
        "<a href=\"ssb:experimental?action=claim-http-invite&amp;noinvite=x\">claim</a>"
        "</body></html>";
    enqueueHTML(200, @"<html></html>"); // JSON falls through
    enqueueHTML(200, html);

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertEqual(error.code, -4);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_htmlPath_ssbScheme_withScrapedMSA_success {
    NSString *html = [NSString stringWithFormat:
        @"<html><body>"
        "<a href=\"ssb:experimental?action=claim-http-invite&amp;invite=tok&amp;postTo=%@\">claim</a>"
        "net:room.example.com:8008~shs:%@"
        "</body></html>", kPostToEnc, kNetPubKey];
    enqueueHTML(200, @"<html></html>"); // JSON falls through
    enqueueHTML(200, html);
    enqueueJSON(200, @{@"multiserverAddress": kNetMSA}); // POST response

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            XCTAssertEqualObjects(config.host, @"room.example.com");
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testResolveHTTPSInvite_htmlPath_ssbDoubleSlashScheme_success {
    // Second regex pattern: ssb://experimental?...
    NSString *html = [NSString stringWithFormat:
        @"<html><body>"
        "<a href=\"ssb://experimental?action=claim-http-invite&amp;invite=tok&amp;postTo=%@\">claim</a>"
        "net:room.example.com:8008~shs:%@"
        "</body></html>", kPostToEnc, kNetPubKey];
    enqueueHTML(200, @"<html></html>");
    enqueueHTML(200, html);
    enqueueJSON(200, @{@"multiserverAddress": kNetMSA});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler resolveHTTPSInvite:kClaimURL localId:@"@me"
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

// MARK: - performClaim: success paths

- (void)testPerformClaim_success_withMultiserverAddress {
    enqueueJSON(200, @{@"multiserverAddress": kNetMSA});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            XCTAssertEqualObjects(config.host, @"room.example.com");
            XCTAssertEqual(config.port, 8008);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_success_withPubKeyField_constructsMSA {
    enqueueJSON(200, @{@"pubkey": kNetPubKey});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            XCTAssertEqualObjects(config.host, @"room.example.com");
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_success_withPublicKeyField_constructsMSA {
    enqueueJSON(200, @{@"publicKey": kNetPubKey});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_success_fallbackAddress_whenResponseNotJSON {
    // Non-JSON body → json=nil → fallbackAddress used
    enqueueNonJSON(200);

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:kNetMSA fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_success_fallbackPubKey_whenResponseNotJSON {
    // Non-JSON body → json=nil → fallbackPubKey used to construct MSA
    enqueueNonJSON(200);

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:kNetPubKey
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_success_noMSANoPubKey_returnsError {
    enqueueJSON(200, @{@"status": @"ok"});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertEqual(error.code, -6);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_networkError_returnsError {
    enqueueNetworkError();

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertNotNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

// MARK: - performClaim: failure / already-registered paths

- (void)testPerformClaim_serverError_returnsError {
    enqueueJSON(403, @{@"error": @"not authorized"});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertEqual(error.code, -5);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_alreadyRegistered_msaInResponse_returnsConfig {
    enqueueJSON(400, @{@"error": @"already on the list", @"multiserverAddress": kNetMSA});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            XCTAssertEqualObjects(config.host, @"room.example.com");
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_alreadyRegistered_fallbackAddress_returnsConfig {
    enqueueJSON(400, @{@"error": @"already registered"});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:kNetMSA fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_alreadyRegistered_pubKeyInResponse_returnsConfig {
    enqueueJSON(400, @{@"error": @"already on the list", @"pubkey": kNetPubKey});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNotNil(config);
            XCTAssertNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testPerformClaim_alreadyRegistered_noMSANoPubKey_returnsError {
    enqueueJSON(400, @{@"error": @"already on the list"});

    XCTestExpectation *exp = [self expectationWithDescription:@"done"];
    [RoomInviteHandler performClaim:@"tok" postTo:kPostTo localId:@"@me"
        targetURL:[NSURL URLWithString:kClaimURL] fallbackAddress:nil fallbackPubKey:nil
        completion:^(RoomConfig *config, NSError *error) {
            XCTAssertNil(config);
            XCTAssertNotNil(error);
            [exp fulfill];
        }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

@end
