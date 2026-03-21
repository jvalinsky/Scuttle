#import <XCTest/XCTest.h>
#import "../Sources/SSBSecurityFramer.h"
#import "../Sources/tweetnacl.h"

#ifdef __APPLE__
#import <Network/Network.h>
#else
#import "SSBNetworkCompat.h"
#endif

// Private C API used by the framework
extern void nw_framer_options_set_object_value(nw_protocol_options_t options, const char *key, id value);
extern id nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key);

@interface SSBSecurityFramerTests : XCTestCase
@end

@implementation SSBSecurityFramerTests

- (void)testCreateDefinitionReturnsNonnull {
    nw_protocol_definition_t def = [SSBSecurityFramer createDefinition];
    XCTAssertNotNil(def);
}

- (void)testOptionsCreationWithValidKeys {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    NSData *localSK = [NSData dataWithBytes:sk length:64];
    NSData *remotePK = [NSData dataWithBytes:pk length:32];

    nw_protocol_options_t options = [SSBSecurityFramer createOptionsWithLocalSecretKey:localSK
                                                                       remotePublicKey:remotePK
                                                                              asClient:YES];
    XCTAssertNotNil(options);
    
    NSData *extractedLocal = nw_framer_options_copy_object_value(options, "LocalKey");
    NSData *extractedRemote = nw_framer_options_copy_object_value(options, "RemoteKey");
    NSNumber *extractedClient = nw_framer_options_copy_object_value(options, "AsClient");

    XCTAssertEqualObjects(extractedLocal, localSK);
    XCTAssertEqualObjects(extractedRemote, remotePK);
    XCTAssertEqual([extractedClient boolValue], YES);
}

- (void)testOptionsCreationAsServer {
    unsigned char pk[32], sk[64];
    crypto_sign_ed25519_keypair(pk, sk);
    NSData *localSK = [NSData dataWithBytes:sk length:64];

    // Servers don't know remote PK upfront
    nw_protocol_options_t options = [SSBSecurityFramer createOptionsWithLocalSecretKey:localSK
                                                                       remotePublicKey:(id _Nonnull)nil
                                                                              asClient:NO];
    XCTAssertNotNil(options);
    
    NSData *extractedLocal = nw_framer_options_copy_object_value(options, "LocalKey");
    NSData *extractedRemote = nw_framer_options_copy_object_value(options, "RemoteKey");
    NSNumber *extractedClient = nw_framer_options_copy_object_value(options, "AsClient");

    XCTAssertEqualObjects(extractedLocal, localSK);
    XCTAssertNil(extractedRemote);
    XCTAssertEqual([extractedClient boolValue], NO);
}

- (void)testOptionsWithNilKeysSafelyHandlesDefaults {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    nw_protocol_options_t options = [SSBSecurityFramer createOptionsWithLocalSecretKey:(id)nil
                                                                       remotePublicKey:(id)nil
                                                                              asClient:YES];
#pragma clang diagnostic pop
    
    XCTAssertNotNil(options);
    NSData *extractedLocal = nw_framer_options_copy_object_value(options, "LocalKey");
    XCTAssertNil(extractedLocal);
    
    NSNumber *extractedClient = nw_framer_options_copy_object_value(options, "AsClient");
    XCTAssertEqual([extractedClient boolValue], YES);
}

@end
