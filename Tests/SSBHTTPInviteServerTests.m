#import <XCTest/XCTest.h>
#import <SSBNetwork/SSBHTTPInviteServer.h>
#import <SSBNetwork/SSBEnvironment.h>

#pragma mark - FakeInviteEnv

@interface FakeInviteEnv : NSObject <SSBEnvironmentProtocol>
@property (nonatomic, strong) NSDate *fixedDate;
@end

@implementation FakeInviteEnv
- (NSDate *)now { return self.fixedDate ?: [NSDate date]; }
- (uint32_t)randomUInt32 { return arc4random(); }
- (void)randomBytes:(void *)buffer length:(NSUInteger)length { arc4random_buf(buffer, length); }
- (NSURLSession *)URLSession { return [NSURLSession sharedSession]; }
- (NSURLSession *)URLSessionWithConfiguration:(NSURLSessionConfiguration *)c {
    return [NSURLSession sessionWithConfiguration:c];
}
- (NSFileManager *)fileManager { return [NSFileManager defaultManager]; }
- (NSString *)scuttleDataDirectory { return NSTemporaryDirectory(); }
- (void)dispatchAfter:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block {
    block();
}
@end

#pragma mark - MockInviteDelegate

@interface MockInviteDelegate : NSObject <SSBHTTPInviteServerDelegate>
@property (nonatomic, copy) NSString *lastGeneratedCode;
@property (nonatomic, copy) NSString *lastClaimedCode;
@property (nonatomic, copy) NSString *lastClaimedFeedId;
@property (nonatomic, copy) NSString *lastExpiredCode;
@end

@implementation MockInviteDelegate
- (void)inviteServer:(SSBHTTPInviteServer *)server didGenerateInviteCode:(NSString *)code {
    self.lastGeneratedCode = code;
}
- (void)inviteServer:(SSBHTTPInviteServer *)server didClaimInviteCode:(NSString *)code forFeedId:(NSString *)feedId {
    self.lastClaimedCode = code;
    self.lastClaimedFeedId = feedId;
}
- (void)inviteServer:(SSBHTTPInviteServer *)server inviteCodeExpired:(NSString *)code {
    self.lastExpiredCode = code;
}
@end

#pragma mark - SSBHTTPInviteServerTests

@interface SSBHTTPInviteServerTests : XCTestCase
@property (nonatomic, strong) SSBHTTPInviteServer *server;
@property (nonatomic, strong) NSData *pubKey;
@property (nonatomic, strong) id<SSBEnvironmentProtocol> savedEnv;
@end

@implementation SSBHTTPInviteServerTests

- (void)setUp {
    [super setUp];
    self.savedEnv = [SSBEnvironment shared];
    self.pubKey = [NSMutableData dataWithLength:32];
    self.server = [[SSBHTTPInviteServer alloc] initWithHost:@"example.com"
                                                       port:8008
                                                     pubKey:self.pubKey
                                                privacyMode:SSBHTTPInvitePrivacyModeOpen];
}

- (void)tearDown {
    [SSBEnvironment setShared:self.savedEnv];
    [super tearDown];
}

#pragma mark - Init

- (void)testInit_basic_setsProperties {
    XCTAssertEqualObjects(self.server.host, @"example.com");
    XCTAssertEqual(self.server.port, 8008);
    XCTAssertEqual(self.server.privacyMode, SSBHTTPInvitePrivacyModeOpen);
    XCTAssertNotNil(self.server.multiserverAddress);
    XCTAssertNotNil(self.server.httpSession);
}

- (void)testInit_withExplicitMultiserverAddress_usesProvided {
    SSBHTTPInviteServer *s = [[SSBHTTPInviteServer alloc] initWithHost:@"example.com"
                                                                  port:8008
                                                                pubKey:self.pubKey
                                                           privacyMode:SSBHTTPInvitePrivacyModeOpen
                                                    multiserverAddress:@"net:example.com:8008~shs:custom"];
    XCTAssertEqualObjects(s.multiserverAddress, @"net:example.com:8008~shs:custom");
}

- (void)testInit_multiserverAddress_derivedFromHostAndKey {
    NSString *msAddr = self.server.multiserverAddress;
    XCTAssertTrue([msAddr hasPrefix:@"net:example.com:8008~shs:"]);
}

#pragma mark - generateInviteCode

- (void)testGenerateInviteCode_returnsNonEmpty {
    NSString *code = [self.server generateInviteCode];
    XCTAssertNotNil(code);
    XCTAssertEqual(code.length, 32U);
}

- (void)testGenerateInviteCode_twoCalls_differ {
    NSString *c1 = [self.server generateInviteCode];
    NSString *c2 = [self.server generateInviteCode];
    XCTAssertNotEqualObjects(c1, c2);
}

- (void)testGenerateInviteCodeWithMaxClaims_storesMaxClaims {
    NSString *code = [self.server generateInviteCodeWithMaxClaims:5];
    NSDictionary *info = [self.server getInviteInfo:code];
    XCTAssertEqualObjects(info[@"maxClaims"], @5);
}

- (void)testGenerateInviteCode_callsDelegate {
    MockInviteDelegate *delegate = [[MockInviteDelegate alloc] init];
    self.server.delegate = delegate;
    NSString *code = [self.server generateInviteCode];
    XCTAssertEqualObjects(delegate.lastGeneratedCode, code);
}

- (void)testGenerateInviteCode_privacyModeStoredInInfo {
    SSBHTTPInviteServer *restricted = [[SSBHTTPInviteServer alloc] initWithHost:@"h"
                                                                           port:8008
                                                                         pubKey:self.pubKey
                                                                    privacyMode:SSBHTTPInvitePrivacyModeRestricted];
    NSString *code = [restricted generateInviteCode];
    NSDictionary *info = [restricted getInviteInfo:code];
    XCTAssertEqualObjects(info[@"privacyMode"], @(SSBHTTPInvitePrivacyModeRestricted));
}

#pragma mark - isInviteCodeExpired (called directly, not from within queue)

- (void)testIsInviteCodeExpired_unknownCode_returnsTrue {
    // Unknown code: no info → isExpired = YES (default)
    XCTAssertTrue([self.server isInviteCodeExpired:@"unknown-code"]);
}

- (void)testIsInviteCodeExpired_freshCode_returnsFalse {
    NSString *code = [self.server generateInviteCode];
    // Fresh code: expires in 24h, so not expired yet
    XCTAssertFalse([self.server isInviteCodeExpired:code]);
}

- (void)testIsInviteCodeExpired_withFutureEnv_returnsTrue {
    NSString *code = [self.server generateInviteCode];

    // Advance environment time past expiry (> 24h in future)
    FakeInviteEnv *fake = [[FakeInviteEnv alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSinceNow:60 * 60 * 25]; // 25 hours
    [SSBEnvironment setShared:fake];

    XCTAssertTrue([self.server isInviteCodeExpired:code]);
}

#pragma mark - isInviteCodeClaimed (called directly)

- (void)testIsInviteCodeClaimed_unknownCode_returnsFalse {
    XCTAssertFalse([self.server isInviteCodeClaimed:@"unknown"]);
}

- (void)testIsInviteCodeClaimed_freshCode_returnsFalse {
    NSString *code = [self.server generateInviteCode];
    XCTAssertFalse([self.server isInviteCodeClaimed:code]);
}

#pragma mark - validateInviteCode (safe: nil/empty/unknown only)

- (void)testValidateInviteCode_nil_returnsFalse {
    XCTAssertFalse([self.server validateInviteCode:nil]);
}

- (void)testValidateInviteCode_empty_returnsFalse {
    XCTAssertFalse([self.server validateInviteCode:@""]);
}

- (void)testValidateInviteCode_unknown_returnsFalse {
    XCTAssertFalse([self.server validateInviteCode:@"definitely-not-a-valid-code"]);
}

#pragma mark - claimInvite (safe: unknown code only)

- (void)testClaimInvite_unknownCode_returnsError {
    NSError *error = nil;
    NSDictionary *result = [self.server claimInvite:@"bad-code" forFeedId:@"@feed.ed25519" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"SSBHTTPInvite");
    XCTAssertEqual(error.code, 1);
}

#pragma mark - getMultiserverAddressForCode

- (void)testGetMultiserverAddress_withMsAddr_returnsIt {
    SSBHTTPInviteServer *s = [[SSBHTTPInviteServer alloc] initWithHost:@"h"
                                                                  port:8008
                                                                pubKey:self.pubKey
                                                           privacyMode:SSBHTTPInvitePrivacyModeOpen
                                                    multiserverAddress:@"net:h:8008~shs:abc"];
    NSString *addr = [s getMultiserverAddressForCode:@"any"];
    XCTAssertEqualObjects(addr, @"net:h:8008~shs:abc");
}

- (void)testGetMultiserverAddress_noPubKeyNoHost_returnsNil {
    SSBHTTPInviteServer *s = [[SSBHTTPInviteServer alloc] initWithHost:@"h"
                                                                  port:8008
                                                                pubKey:nil
                                                           privacyMode:SSBHTTPInvitePrivacyModeOpen
                                                    multiserverAddress:nil];
    XCTAssertNil([s getMultiserverAddressForCode:@"any"]);
}

#pragma mark - setRestrictedFeedIds / isFeedIdAllowed

- (void)testSetRestrictedFeedIds_allowsMatchingFeed {
    [self.server setRestrictedFeedIds:@[@"@alice.ed25519"]];
    XCTAssertTrue([self.server isFeedIdAllowed:@"@alice.ed25519"]);
}

- (void)testIsFeedIdAllowed_nil_returnsFalse {
    XCTAssertFalse([self.server isFeedIdAllowed:nil]);
}

- (void)testIsFeedIdAllowed_notInList_returnsFalse {
    [self.server setRestrictedFeedIds:@[@"@alice.ed25519"]];
    XCTAssertFalse([self.server isFeedIdAllowed:@"@bob.ed25519"]);
}

- (void)testIsFeedIdAllowed_normalizesPrefix {
    // Without @ prefix still matches
    [self.server setRestrictedFeedIds:@[@"@alice.ed25519"]];
    XCTAssertTrue([self.server isFeedIdAllowed:@"alice.ed25519"]);
}

- (void)testIsFeedIdAllowed_normalizesSuffix {
    // Both with and without .ed25519 suffix match
    [self.server setRestrictedFeedIds:@[@"alice"]];
    XCTAssertTrue([self.server isFeedIdAllowed:@"@alice.ed25519"]);
}

#pragma mark - setCommunityMemberFeedIds / isFeedIdInCommunity

- (void)testSetCommunityMemberFeedIds_memberReturnsTrue {
    [self.server setCommunityMemberFeedIds:@[@"@bob.ed25519"]];
    XCTAssertTrue([self.server isFeedIdInCommunity:@"@bob.ed25519"]);
}

- (void)testIsFeedIdInCommunity_nil_returnsFalse {
    XCTAssertFalse([self.server isFeedIdInCommunity:nil]);
}

- (void)testIsFeedIdInCommunity_notInList_returnsFalse {
    [self.server setCommunityMemberFeedIds:@[@"@bob.ed25519"]];
    XCTAssertFalse([self.server isFeedIdInCommunity:@"@carol.ed25519"]);
}

#pragma mark - getInviteInfo / revokeInviteCode

- (void)testGetInviteInfo_unknown_returnsNil {
    XCTAssertNil([self.server getInviteInfo:@"nonexistent"]);
}

- (void)testGetInviteInfo_known_returnsDict {
    NSString *code = [self.server generateInviteCode];
    NSDictionary *info = [self.server getInviteInfo:code];
    XCTAssertNotNil(info);
    XCTAssertEqualObjects(info[@"code"], code);
    XCTAssertNotNil(info[@"createdAt"]);
    XCTAssertNotNil(info[@"expiresAt"]);
    XCTAssertEqualObjects(info[@"claimedCount"], @0);
}

- (void)testRevokeInviteCode_removesCode {
    NSString *code = [self.server generateInviteCode];
    XCTAssertNotNil([self.server getInviteInfo:code]);
    [self.server revokeInviteCode:code];
    XCTAssertNil([self.server getInviteInfo:code]);
}

- (void)testRevokeInviteCode_invalidatesClaim {
    NSString *code = [self.server generateInviteCode];
    [self.server revokeInviteCode:code];
    // isInviteCodeExpired on unknown code returns YES
    XCTAssertTrue([self.server isInviteCodeExpired:code]);
}

- (void)testIsInviteCodeExpired_withDelegate_callsExpiredCallback {
    MockInviteDelegate *delegate = [[MockInviteDelegate alloc] init];
    self.server.delegate = delegate;

    NSString *code = [self.server generateInviteCode];

    // Advance environment time past expiry (25 hours)
    FakeInviteEnv *fake = [[FakeInviteEnv alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSinceNow:60 * 60 * 25];
    [SSBEnvironment setShared:fake];

    BOOL expired = [self.server isInviteCodeExpired:code];
    XCTAssertTrue(expired);
    // Delegate must have received the expiry notification
    XCTAssertEqualObjects(delegate.lastExpiredCode, code);
}

#pragma mark - listActiveInviteCodes

- (void)testListActiveInviteCodes_freshCode_included {
    NSString *code = [self.server generateInviteCode];
    NSArray *active = [self.server listActiveInviteCodes];
    XCTAssertTrue([active containsObject:code]);
}

- (void)testListActiveInviteCodes_revokedCode_excluded {
    NSString *code = [self.server generateInviteCode];
    [self.server revokeInviteCode:code];
    NSArray *active = [self.server listActiveInviteCodes];
    XCTAssertFalse([active containsObject:code]);
}

- (void)testListActiveInviteCodes_expiredCode_excluded {
    NSString *code = [self.server generateInviteCode];

    // Advance time past expiry
    FakeInviteEnv *fake = [[FakeInviteEnv alloc] init];
    fake.fixedDate = [NSDate dateWithTimeIntervalSinceNow:60 * 60 * 25];
    [SSBEnvironment setShared:fake];

    NSArray *active = [self.server listActiveInviteCodes];
    XCTAssertFalse([active containsObject:code]);
}

#pragma mark - getClaimCountsForAllCodes

- (void)testGetClaimCountsForAllCodes_freshCode_claimCountZero {
    NSString *code = [self.server generateInviteCode];
    NSDictionary *counts = [self.server getClaimCountsForAllCodes];
    XCTAssertEqualObjects(counts[code], @0);
}

- (void)testGetClaimCountsForAllCodes_multipleCodesTracked {
    NSString *c1 = [self.server generateInviteCode];
    NSString *c2 = [self.server generateInviteCode];
    NSDictionary *counts = [self.server getClaimCountsForAllCodes];
    XCTAssertNotNil(counts[c1]);
    XCTAssertNotNil(counts[c2]);
}

#pragma mark - handleGetJoinWithInviteCode (unknown code paths only)

- (void)testHandleGetJoin_unknownCode_acceptJSON_returnsFailed {
    NSDictionary *result = [self.server handleGetJoinWithInviteCode:@"bad-code"
                                                        acceptJSON:YES
                                                     submissionURL:@"https://example.com/claim"];
    XCTAssertEqualObjects(result[@"status"], @"failed");
}

- (void)testHandleGetJoin_unknownCode_notAcceptJSON_returnsHTML {
    NSDictionary *result = [self.server handleGetJoinWithInviteCode:@"bad-code"
                                                        acceptJSON:NO
                                                     submissionURL:@"https://example.com/claim"];
    XCTAssertEqualObjects(result[@"isValid"], @NO);
    NSString *html = result[@"html"];
    XCTAssertNotNil(html);
    XCTAssertTrue([html containsString:@"bad-code"]);
}

#pragma mark - handlePostClaimWithBody (safe paths)

- (void)testHandlePostClaim_missingFields_returnsFailed {
    NSDictionary *result = [self.server handlePostClaimWithBody:@{}];
    XCTAssertEqualObjects(result[@"status"], @"failed");
}

- (void)testHandlePostClaim_missingInvite_returnsFailed {
    NSDictionary *result = [self.server handlePostClaimWithBody:@{@"id": @"@feed.ed25519"}];
    XCTAssertEqualObjects(result[@"status"], @"failed");
}

- (void)testHandlePostClaim_unknownCode_returnsFailed {
    NSDictionary *result = [self.server handlePostClaimWithBody:@{
        @"id": @"@feed.ed25519",
        @"invite": @"unknown-code"
    }];
    XCTAssertEqualObjects(result[@"status"], @"failed");
}

#pragma mark - renderHTMLForValidInvite

- (void)testRenderHTMLForValidInvite_containsSSBURI {
    NSString *html = [self.server renderHTMLForValidInvite:@"invite123"
                                             submissionURL:@"https://example.com/claim"];
    XCTAssertTrue([html containsString:@"invite123"]);
    XCTAssertTrue([html containsString:@"ssb:experimental"]);
    XCTAssertTrue([html containsString:@"claim-http-invite"]);
}

- (void)testRenderHTMLForValidInvite_containsMultiserverAddress {
    NSString *html = [self.server renderHTMLForValidInvite:@"invite123"
                                             submissionURL:@"https://example.com/claim"];
    XCTAssertTrue([html containsString:@"example.com"]);
}

#pragma mark - renderHTMLForInvalidInvite

- (void)testRenderHTMLForInvalidInvite_containsCode {
    NSString *html = [self.server renderHTMLForInvalidInvite:@"badcode" error:@"Some error"];
    XCTAssertTrue([html containsString:@"badcode"]);
    XCTAssertTrue([html containsString:@"Some error"]);
}

- (void)testRenderHTMLForInvalidInvite_nilError_nocrash {
    NSString *html = [self.server renderHTMLForInvalidInvite:@"code" error:nil];
    XCTAssertNotNil(html);
    XCTAssertTrue([html containsString:@"code"]);
}

#pragma mark - renderHTMLForAlias

- (void)testRenderHTMLForAlias_containsAlias {
    NSString *html = [self.server renderHTMLForAlias:@"alice"
                                  multiserverAddress:@"net:example.com:8008~shs:abc"
                                              userId:@"@user.ed25519"
                                           signature:@"sigdata"
                                              roomId:@"@room.ed25519"];
    XCTAssertTrue([html containsString:@"alice"]);
    XCTAssertTrue([html containsString:@"consume-alias"]);
    XCTAssertTrue([html containsString:@"ssb:experimental"]);
}

#pragma mark - jsonForAlias

- (void)testJsonForAlias_correctFields {
    NSDictionary *json = [self.server jsonForAlias:@"alice"
                                multiserverAddress:@"net:example.com:8008~shs:abc"
                                            userId:@"@user.ed25519"
                                         signature:@"sigdata"
                                            roomId:@"@room.ed25519"];
    XCTAssertEqualObjects(json[@"action"], @"consume-alias");
    XCTAssertEqualObjects(json[@"alias"], @"alice");
    XCTAssertEqualObjects(json[@"userId"], @"@user.ed25519");
    XCTAssertEqualObjects(json[@"signature"], @"sigdata");
    XCTAssertEqualObjects(json[@"roomId"], @"@room.ed25519");
    XCTAssertEqualObjects(json[@"multiserverAddress"], @"net:example.com:8008~shs:abc");
}

@end
