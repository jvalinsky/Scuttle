#import <Foundation/Foundation.h>
#import <SSBNetwork/SSBRoomClient.h>
#import <SSBNetwork/SSBFeedStore.h>
#import <SSBNetwork/SSBBlobStore.h>
#import <SSBNetwork/SSBSecretStore.h>
#import <SSBNetwork/SSBTransport.h>
#import "tweetnacl.h"

typedef void (^SSBRoomClientTraceSink)(NSDictionary<NSString *, id> *event);

@interface SSBRoomClient (RoomSmokeInternal)
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSData *)serverPubKey
               localIdentity:(nullable NSData *)localIdentitySecret
                   feedStore:(nullable SSBFeedStore *)feedStore
                   blobStore:(nullable SSBBlobStore *)blobStore
            transportBackend:(nullable id<SSBTransportBackend>)transportBackend
                   traceSink:(nullable SSBRoomClientTraceSink)traceSink;
@end

static NSData *RoomSmokeGenerateSecret(void) {
    unsigned char publicKey[32];
    unsigned char secretKey[64];
    crypto_sign_ed25519_keypair(publicKey, secretKey);
    return [NSData dataWithBytes:secretKey length:sizeof(secretKey)];
}

static NSString *RoomSmokeNormalizeServerKey(NSString *input) {
    if (![input isKindOfClass:[NSString class]] || input.length == 0) {
        return nil;
    }

    NSString *normalized = [input copy];
    if ([normalized hasPrefix:@"@"]) {
        normalized = [normalized substringFromIndex:1];
    }
    if ([normalized hasSuffix:@".ed25519"]) {
        normalized = [normalized substringToIndex:normalized.length - 8];
    }
    return normalized;
}

static NSData *RoomSmokeDecodeServerKey(NSString *input) {
    NSString *normalized = RoomSmokeNormalizeServerKey(input);
    if (normalized.length == 0) {
        return nil;
    }
    return [[NSData alloc] initWithBase64EncodedString:normalized
                                               options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

static id RoomSmokeJSONSafeObject(id object) {
    if (!object || object == [NSNull null]) {
        return [NSNull null];
    }
    if ([object isKindOfClass:[NSString class]] ||
        [object isKindOfClass:[NSNumber class]] ||
        [object isKindOfClass:[NSNull class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSData class]]) {
        return [(NSData *)object base64EncodedStringWithOptions:0];
    }
    if ([object isKindOfClass:[NSDate class]]) {
        return @([(NSDate *)object timeIntervalSince1970]);
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in (NSArray *)object) {
            [array addObject:RoomSmokeJSONSafeObject(item)];
        }
        return array;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
        for (id key in [(NSDictionary *)object allKeys]) {
            NSString *jsonKey = [key isKindOfClass:[NSString class]] ? key : [key description];
            dict[jsonKey] = RoomSmokeJSONSafeObject([(NSDictionary *)object objectForKey:key]);
        }
        return dict;
    }
    return [object description];
}

@interface RoomSmokeWriter : NSObject
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, strong) dispatch_queue_t queue;
- (instancetype)initWithPath:(NSString *)path;
- (void)appendEvent:(NSDictionary<NSString *, id> *)event;
- (void)close;
@end

@implementation RoomSmokeWriter

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.scuttle.roomsmoke.writer", DISPATCH_QUEUE_SERIAL);
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        _handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    return self;
}

- (void)appendEvent:(NSDictionary<NSString *, id> *)event {
    if (!self.handle || ![event isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSMutableDictionary<NSString *, id> *line = [NSMutableDictionary dictionary];
    line[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    [line addEntriesFromDictionary:(NSDictionary<NSString *, id> *)RoomSmokeJSONSafeObject(event)];

    dispatch_async(self.queue, ^{
        NSData *json = [NSJSONSerialization dataWithJSONObject:line options:0 error:nil];
        if (!json) {
            return;
        }
        NSMutableData *payload = [json mutableCopy];
        [payload appendBytes:"\n" length:1];
        @try {
            [self.handle writeData:payload];
        } @catch (__unused NSException *exception) {
        }
    });
}

- (void)close {
    if (!self.handle) {
        return;
    }

    dispatch_sync(self.queue, ^{
        @try {
            [self.handle synchronizeFile];
            [self.handle closeFile];
        } @catch (__unused NSException *exception) {
        }
    });
    self.handle = nil;
}

@end

@class RoomSmokeHarness;

@interface RoomSmokePeerDelegate : NSObject <SSBRoomClientDelegate>
@property (nonatomic, weak) RoomSmokeHarness *harness;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *peerID;
@property (nonatomic, copy) NSString *expectedPeerID;
@property (nonatomic, weak) SSBRoomClient *client;
@end

@interface RoomSmokeHarness : NSObject
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy) NSString *serverPubKey;
@property (nonatomic, strong) NSData *serverPubKeyData;
@property (nonatomic, copy) NSString *workDir;
@property (nonatomic, copy) NSString *traceFile;
@property (nonatomic, copy) NSString *summaryFile;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, strong) RoomSmokeWriter *writer;
@property (nonatomic, strong) SSBRoomClient *clientA;
@property (nonatomic, strong) SSBRoomClient *clientB;
@property (nonatomic, strong) RoomSmokePeerDelegate *delegateA;
@property (nonatomic, strong) RoomSmokePeerDelegate *delegateB;
@property (nonatomic, strong) NSMutableArray<NSString *> *errors;
@property (nonatomic, strong) NSMutableSet<NSString *> *connectedLabels;
@property (nonatomic, strong) NSMutableSet<NSString *> *discoveredLabels;
@property (nonatomic, strong) NSMutableSet<NSString *> *tunnelPeers;
@property (nonatomic, strong) NSMutableSet<NSString *> *syncedLabels;
@property (nonatomic, assign) BOOL tunnelRequested;
@property (nonatomic, assign) BOOL ebtStarted;
@property (nonatomic, assign) BOOL historyRequested;
@property (nonatomic, assign) BOOL finished;
- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSString *)serverPubKey
                     workDir:(NSString *)workDir
                   traceFile:(NSString *)traceFile
                 summaryFile:(NSString *)summaryFile
                     timeout:(NSTimeInterval)timeout;
- (void)start;
- (void)recordTraceEvent:(NSDictionary<NSString *, id> *)event;
- (void)peerDidConnect:(RoomSmokePeerDelegate *)delegate;
- (void)peer:(RoomSmokePeerDelegate *)delegate didUpdateEndpoints:(NSArray<NSString *> *)endpoints;
- (void)peer:(RoomSmokePeerDelegate *)delegate didEstablishTunnelWithPeer:(NSString *)peerID;
- (void)peerDidSyncLocalFeed:(RoomSmokePeerDelegate *)delegate;
- (void)peer:(RoomSmokePeerDelegate *)delegate didEncounterError:(NSError *)error;
- (void)peer:(RoomSmokePeerDelegate *)delegate didLogMessage:(NSString *)message;
- (void)peer:(RoomSmokePeerDelegate *)delegate didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(nullable NSString *)author;
- (void)peer:(RoomSmokePeerDelegate *)delegate didReplicateMessagesFromPeer:(NSString *)peerID count:(NSInteger)count;
@end

@implementation RoomSmokePeerDelegate

- (void)roomClientDidConnect:(SSBRoomClient *)client {
    self.client = client;
    [self.harness peerDidConnect:self];
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    self.client = client;
    [self.harness peer:self didUpdateEndpoints:endpoints];
}

- (void)roomClient:(SSBRoomClient *)client didEstablishTunnelWithPeer:(NSString *)peerId {
    self.client = client;
    [self.harness peer:self didEstablishTunnelWithPeer:peerId];
}

- (void)roomClientDidSyncLocalFeed:(SSBRoomClient *)client {
    self.client = client;
    [self.harness peerDidSyncLocalFeed:self];
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    self.client = client;
    [self.harness peer:self didEncounterError:error];
}

- (void)roomClient:(SSBRoomClient *)client didLogMessage:(NSString *)message {
    self.client = client;
    [self.harness peer:self didLogMessage:message];
}

- (void)roomClient:(SSBRoomClient *)client didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(NSString *)author {
    self.client = client;
    [self.harness peer:self didUpdateSyncStatus:status progress:progress author:author];
}

- (void)roomClient:(SSBRoomClient *)client didReplicateMessagesFromPeer:(NSString *)peerId count:(NSInteger)count {
    self.client = client;
    [self.harness peer:self didReplicateMessagesFromPeer:peerId count:count];
}

@end

@implementation RoomSmokeHarness

- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
                serverPubKey:(NSString *)serverPubKey
                     workDir:(NSString *)workDir
                   traceFile:(NSString *)traceFile
                 summaryFile:(NSString *)summaryFile
                     timeout:(NSTimeInterval)timeout {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _serverPubKey = [RoomSmokeNormalizeServerKey(serverPubKey) copy];
        _serverPubKeyData = RoomSmokeDecodeServerKey(serverPubKey);
        _workDir = [workDir copy];
        _traceFile = [traceFile copy];
        _summaryFile = [summaryFile copy];
        _timeout = timeout;
        _errors = [NSMutableArray array];
        _connectedLabels = [NSMutableSet set];
        _discoveredLabels = [NSMutableSet set];
        _tunnelPeers = [NSMutableSet set];
        _syncedLabels = [NSMutableSet set];
    }
    return self;
}

- (void)start {
    if (self.serverPubKeyData.length != 32) {
        [self.errors addObject:@"Invalid 32-byte room public key"];
        [self finishWithSuccess:NO reason:@"invalid_server_pubkey"];
        return;
    }

    self.writer = [[RoomSmokeWriter alloc] initWithPath:self.traceFile];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.workDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    __weak typeof(self) weakSelf = self;
    SSBRoomClientTraceSink traceSink = ^(NSDictionary<NSString *,id> *event) {
        [weakSelf recordTraceEvent:event];
    };

    self.clientA = [self buildClientWithLabel:@"client-a" traceSink:traceSink];
    self.clientB = [self buildClientWithLabel:@"client-b" traceSink:traceSink];
    if (!self.clientA || !self.clientB) {
        [self.errors addObject:@"Failed to create smoke clients"];
        [self finishWithSuccess:NO reason:@"client_setup_failed"];
        return;
    }

    self.delegateA.expectedPeerID = self.delegateB.peerID;
    self.delegateB.expectedPeerID = self.delegateA.peerID;

    [self recordHarnessEvent:@{
        @"event": @"smoke.start",
        @"host": self.host,
        @"port": @(self.port),
        @"clientA": self.delegateA.peerID ?: @"",
        @"clientB": self.delegateB.peerID ?: @""
    }];

    [self.clientA connect];
    [self.clientB connect];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.finished) {
            [self.errors addObject:@"Timed out waiting for smoke milestones"];
            [self finishWithSuccess:NO reason:@"timeout"];
        }
    });
}

- (SSBRoomClient *)buildClientWithLabel:(NSString *)label traceSink:(SSBRoomClientTraceSink)traceSink {
    NSString *base = [self.workDir stringByAppendingPathComponent:label];
    NSString *blobDir = [base stringByAppendingPathComponent:@"blobs"];
    NSString *feedPath = [base stringByAppendingPathComponent:@"feeds.sqlite3"];
    [[NSFileManager defaultManager] createDirectoryAtPath:blobDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSData *secret = RoomSmokeGenerateSecret();
    SSBFeedStore *feedStore = [[SSBFeedStore alloc] initWithPath:feedPath];
    SSBBlobStore *blobStore = [[SSBBlobStore alloc] initWithPath:blobDir];
    SSBRoomClient *client = [[SSBRoomClient alloc] initWithHost:self.host
                                                           port:self.port
                                                   serverPubKey:self.serverPubKeyData
                                                  localIdentity:secret
                                                      feedStore:feedStore
                                                      blobStore:blobStore
                                               transportBackend:[SSBTransport defaultBackend]
                                                      traceSink:traceSink];
    RoomSmokePeerDelegate *delegate = [[RoomSmokePeerDelegate alloc] init];
    delegate.harness = self;
    delegate.label = label;
    delegate.peerID = SSBPublicIDFromSecret(secret) ?: @"";
    delegate.client = client;
    client.delegate = delegate;

    if ([label isEqualToString:@"client-a"]) {
        self.delegateA = delegate;
    } else {
        self.delegateB = delegate;
    }

    return client;
}

- (void)recordTraceEvent:(NSDictionary<NSString *,id> *)event {
    if (!event) {
        return;
    }

    [self.writer appendEvent:event];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *rpcName = event[@"rpcName"];
        NSString *framerState = event[@"framerState"];
        NSString *message = event[@"message"];

        if ([rpcName isEqualToString:@"ebt.replicate"] &&
            [framerState isEqualToString:@"muxrpc.send"]) {
            self.ebtStarted = YES;
            [self recordHarnessEvent:@{ @"event": @"milestone.ebt_started" }];
        }
        if ([rpcName isEqualToString:@"createHistoryStream"] &&
            [framerState isEqualToString:@"muxrpc.send"]) {
            self.historyRequested = YES;
            [self recordHarnessEvent:@{ @"event": @"milestone.history_requested" }];
        }
        if ([message isKindOfClass:[NSString class]] &&
            [message containsString:@"Room transport ready"]) {
            [self recordHarnessEvent:@{ @"event": @"milestone.transport_ready" }];
        }

        [self evaluateCompletion];
    });
}

- (void)peerDidConnect:(RoomSmokePeerDelegate *)delegate {
    [self.connectedLabels addObject:delegate.label];
    [self recordHarnessEvent:@{
        @"event": @"milestone.client_connected",
        @"label": delegate.label ?: @"",
        @"peerID": delegate.peerID ?: @""
    }];
    [self evaluateCompletion];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    BOOL sawExpectedPeer = (delegate.expectedPeerID.length > 0 &&
                            [endpoints containsObject:delegate.expectedPeerID]);
    if (sawExpectedPeer) {
        [self.discoveredLabels addObject:delegate.label];
        [self recordHarnessEvent:@{
            @"event": @"milestone.peer_discovered",
            @"label": delegate.label ?: @"",
            @"peerID": delegate.expectedPeerID ?: @""
        }];
    } else {
        [self recordHarnessEvent:@{
            @"event": @"peer_update",
            @"label": delegate.label ?: @"",
            @"endpoints": endpoints ?: @[]
        }];
    }

    [self triggerTunnelIfReady];
    [self evaluateCompletion];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didEstablishTunnelWithPeer:(NSString *)peerID {
    if (peerID.length > 0) {
        [self.tunnelPeers addObject:peerID];
    }
    [self recordHarnessEvent:@{
        @"event": @"milestone.tunnel_ready",
        @"label": delegate.label ?: @"",
        @"peerID": peerID ?: @""
    }];
    [self evaluateCompletion];
}

- (void)peerDidSyncLocalFeed:(RoomSmokePeerDelegate *)delegate {
    [self.syncedLabels addObject:delegate.label];
    [self recordHarnessEvent:@{
        @"event": @"milestone.history_synced",
        @"label": delegate.label ?: @""
    }];
    [self evaluateCompletion];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didEncounterError:(NSError *)error {
    NSString *message = error.localizedDescription ?: @"Unknown room error";
    [self.errors addObject:[NSString stringWithFormat:@"%@: %@", delegate.label ?: @"client", message]];
    [self recordHarnessEvent:@{
        @"event": @"client_error",
        @"label": delegate.label ?: @"",
        @"message": message
    }];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didLogMessage:(NSString *)message {
    [self recordHarnessEvent:@{
        @"event": @"client_log",
        @"label": delegate.label ?: @"",
        @"message": message ?: @""
    }];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didUpdateSyncStatus:(NSString *)status progress:(float)progress author:(NSString *)author {
    [self recordHarnessEvent:@{
        @"event": @"sync_status",
        @"label": delegate.label ?: @"",
        @"status": status ?: @"",
        @"progress": @(progress),
        @"author": author ?: @""
    }];
}

- (void)peer:(RoomSmokePeerDelegate *)delegate didReplicateMessagesFromPeer:(NSString *)peerID count:(NSInteger)count {
    [self recordHarnessEvent:@{
        @"event": @"replicated_messages",
        @"label": delegate.label ?: @"",
        @"peerID": peerID ?: @"",
        @"count": @(count)
    }];
}

- (void)triggerTunnelIfReady {
    if (self.tunnelRequested || self.discoveredLabels.count < 2) {
        return;
    }
    if (self.delegateA.expectedPeerID.length == 0 || self.delegateB.expectedPeerID.length == 0) {
        return;
    }

    self.tunnelRequested = YES;
    [self recordHarnessEvent:@{
        @"event": @"action.replicate_from_peer",
        @"clientA": self.delegateA.expectedPeerID ?: @"",
        @"clientB": self.delegateB.expectedPeerID ?: @""
    }];
    [self.clientA replicateFromPeer:self.delegateA.expectedPeerID viaRoom:self.host];
    [self.clientB replicateFromPeer:self.delegateB.expectedPeerID viaRoom:self.host];
}

- (void)evaluateCompletion {
    if (self.finished) {
        return;
    }

    BOOL connected = (self.connectedLabels.count == 2);
    BOOL discovery = (self.discoveredLabels.count == 2);
    BOOL tunnel = (self.tunnelPeers.count > 0);
    BOOL synced = (self.syncedLabels.count > 0);

    if (connected && discovery && tunnel && self.ebtStarted && self.historyRequested && synced) {
        [self finishWithSuccess:YES reason:@"ok"];
    }
}

- (void)recordHarnessEvent:(NSDictionary<NSString *, id> *)event {
    NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
    payload[@"component"] = @"room.smoke";
    [payload addEntriesFromDictionary:event ?: @{}];
    [self.writer appendEvent:payload];
}

- (NSDictionary<NSString *, id> *)summaryDictionaryWithSuccess:(BOOL)success reason:(NSString *)reason {
    return @{
        @"ok": @(success),
        @"reason": reason ?: @"",
        @"host": self.host ?: @"",
        @"port": @(self.port),
        @"serverPubKey": self.serverPubKey ?: @"",
        @"traceFile": self.traceFile ?: @"",
        @"workDir": self.workDir ?: @"",
        @"milestones": @{
            @"clientAConnected": @([self.connectedLabels containsObject:@"client-a"]),
            @"clientBConnected": @([self.connectedLabels containsObject:@"client-b"]),
            @"clientADiscoveredPeer": @([self.discoveredLabels containsObject:@"client-a"]),
            @"clientBDiscoveredPeer": @([self.discoveredLabels containsObject:@"client-b"]),
            @"tunnelReady": @(self.tunnelPeers.count > 0),
            @"ebtStarted": @(self.ebtStarted),
            @"historyRequested": @(self.historyRequested),
            @"historySynced": @(self.syncedLabels.count > 0)
        },
        @"errors": [self.errors copy] ?: @[]
    };
}

- (void)finishWithSuccess:(BOOL)success reason:(NSString *)reason {
    if (self.finished) {
        return;
    }
    self.finished = YES;

    NSDictionary<NSString *, id> *summary = [self summaryDictionaryWithSuccess:success reason:reason];
    NSData *data = [NSJSONSerialization dataWithJSONObject:summary options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:self.summaryFile atomically:YES];
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (string.length > 0) {
            fprintf(success ? stdout : stderr, "%s\n", [string UTF8String]);
        }
    }

    [self recordHarnessEvent:@{
        @"event": @"smoke.finish",
        @"ok": @(success),
        @"reason": reason ?: @""
    }];

    [self.clientA disconnect];
    [self.clientB disconnect];
    [self.writer close];

    exit(success ? 0 : 1);
}

@end

static NSString *RoomSmokeArgumentValue(NSDictionary<NSString *, NSString *> *arguments,
                                        NSString *key,
                                        NSString *fallback) {
    NSString *value = arguments[key];
    if ([value isKindOfClass:[NSString class]] && value.length > 0) {
        return value;
    }
    return fallback;
}

static NSDictionary<NSString *, NSString *> *RoomSmokeParseArguments(NSArray<NSString *> *arguments) {
    NSMutableDictionary<NSString *, NSString *> *parsed = [NSMutableDictionary dictionary];
    for (NSUInteger index = 1; index < arguments.count; index++) {
        NSString *arg = arguments[index];
        if (![arg hasPrefix:@"--"]) {
            continue;
        }
        if (index + 1 >= arguments.count) {
            break;
        }
        NSString *key = [arg substringFromIndex:2];
        parsed[key] = arguments[index + 1];
        index += 1;
    }
    return parsed;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        NSDictionary<NSString *, NSString *> *parsed = RoomSmokeParseArguments(arguments);

        NSString *host = RoomSmokeArgumentValue(parsed, @"host", @"127.0.0.1");
        NSString *portString = RoomSmokeArgumentValue(parsed, @"port", @"8008");
        NSString *serverPubKey = RoomSmokeArgumentValue(parsed, @"server-pubkey", nil);
        NSString *workDir = RoomSmokeArgumentValue(parsed, @"work-dir", [NSTemporaryDirectory() stringByAppendingPathComponent:@"scuttle-room-smoke"]);
        NSString *traceFile = RoomSmokeArgumentValue(parsed, @"trace-file", [workDir stringByAppendingPathComponent:@"protocol-trace.ndjson"]);
        NSString *summaryFile = RoomSmokeArgumentValue(parsed, @"summary-file", [workDir stringByAppendingPathComponent:@"summary.json"]);
        NSString *timeoutString = RoomSmokeArgumentValue(parsed, @"timeout", @"45");

        if (serverPubKey.length == 0) {
            fprintf(stderr, "Missing required --server-pubkey argument.\n");
            return 2;
        }

        [[NSFileManager defaultManager] createDirectoryAtPath:workDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        RoomSmokeHarness *harness = [[RoomSmokeHarness alloc] initWithHost:host
                                                                      port:(uint16_t)[portString integerValue]
                                                              serverPubKey:serverPubKey
                                                                   workDir:workDir
                                                                 traceFile:traceFile
                                                               summaryFile:summaryFile
                                                                   timeout:[timeoutString doubleValue]];
        [harness start];
        dispatch_main();
    }
    return 0;
}
