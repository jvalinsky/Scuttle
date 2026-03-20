#import <Foundation/Foundation.h>
#import "Sources/SSBNetwork.h"
#import "Sources/tweetnacl.h"

@interface TestDelegate : NSObject <SSBRoomClientDelegate>
@end

@implementation TestDelegate
- (void)roomClientDidConnect:(SSBRoomClient *)client {
    NSLog(@"[Test] Connection established, sending ping...");
    [client ping];
    [client announce];
    [client subscribeToEndpoints];
    
    [client listAliasesWithCompletion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        NSLog(@"[Test] Aliases: %@ (Error: %@)", response, error);
    }];
    
    // Test following a dummy user
    NSString *dummyUser = @"@abc.ed25519";
    [client publishContact:dummyUser following:YES completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        NSLog(@"[Test] Follow dummy user result: %@ (Error: %@)", response, error);
    }];
    
    // Test self-follow validation
    NSData *pkData = [client.localIdentitySecret subdataWithRange:NSMakeRange(32, 32)];
    NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
    [client publishContact:myId following:YES completion:^(id  _Nullable response, BOOL isEndOrError, NSError * _Nullable error) {
        NSLog(@"[Test] Self-follow validation (expected error): %@", error.localizedDescription);
    }];
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    NSLog(@"[Test] Endpoints updated: %@", endpoints);
}

- (void)roomClientDidPingSuccessfully:(SSBRoomClient *)client {
    NSLog(@"[Test] Ping sent through BoxStream!");
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    NSLog(@"[Test] Error: %@", error.localizedDescription);
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            NSLog(@"Usage: TestClient <server_pubkey_base64>");
            return 1;
        }
        
        NSString *b64Key = [NSString stringWithUTF8String:argv[1]];
        if ([b64Key hasSuffix:@".ed25519"]) {
            b64Key = [b64Key substringToIndex:b64Key.length - 8];
            if ([b64Key hasPrefix:@"@"]) {
                b64Key = [b64Key substringFromIndex:1];
            }
        }
        
        NSData *serverPubKey = [[NSData alloc] initWithBase64EncodedString:b64Key options:NSDataBase64DecodingIgnoreUnknownCharacters];
        
        unsigned char pk[32];
        unsigned char sk[64];
        crypto_sign_keypair(pk, sk);
        NSData *localId = [NSData dataWithBytes:sk length:64];
        NSData *localPkData = [NSData dataWithBytes:pk length:32];
        NSString *localB64 = [localPkData base64EncodedStringWithOptions:0];
        NSLog(@"Local Client PubKey: @%@.ed25519", localB64);
        
        if (!serverPubKey) {
            NSLog(@"Error: Failed to decode server public key from base64: '%@'", b64Key);
            return 1;
        }
        if (serverPubKey.length != 32) {
            NSLog(@"Error: Decoded server public key has wrong length: %lu (expected 32)", (unsigned long)serverPubKey.length);
            return 1;
        }
        
        NSLog(@"Connecting to localhost:8008 with Server PubKey: %@", b64Key);
        
        static TestDelegate *delegate;
        delegate = [[TestDelegate alloc] init];
        static SSBRoomClient *client;
        client = [[SSBRoomClient alloc] initWithHost:@"127.0.0.1" port:8008 serverPubKey:serverPubKey localIdentity:localId];
        client.delegate = delegate;
        [client connect];
        
        // Let it run for 10 seconds to observe RPC traffic
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Finished test. Final Client State: %d, Delegate: %@", client.isConnected, client.delegate);
            exit(0);
        });
        
    }
    dispatch_main();
    return 0;
}
