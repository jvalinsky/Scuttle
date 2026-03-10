#import "SRRoomManager.h"
#import "RoomStorage.h"
#import "RoomInviteHandler.h"
#import <os/log.h>

NSString * const SRRoomManagerDidUpdateRoomsNotification = @"SRRoomManagerDidUpdateRoomsNotification";
NSString * const SRRoomManagerDidUpdateEndpointsNotification = @"SRRoomManagerDidUpdateEndpointsNotification";
NSString * const SRRoomManagerConnectionStatusChangedNotification = @"SRRoomManagerConnectionStatusChangedNotification";

@interface SRRoomManager () <SSBRoomClientDelegate>
@property (nonatomic, strong) NSMutableArray<RoomConfig *> *internalRooms;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SSBRoomClient *> *internalClients;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *internalRoomEndpoints;
@end

@implementation SRRoomManager

+ (instancetype)sharedManager {
    static SRRoomManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRRoomManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _internalRooms = [[RoomStorage listRooms] mutableCopy];
        _internalClients = [NSMutableDictionary dictionary];
        _internalRoomEndpoints = [NSMutableDictionary dictionary];
        
        // Auto-connect to saved rooms
        for (RoomConfig *config in _internalRooms) {
            [self connectToRoom:config];
        }
        
        // Notify after a short delay to allow UI to setup and listen
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[RoomManager] Delayed notification of rooms: %lu", (unsigned long)self.internalRooms.count);
            [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
            if (self.internalRooms.count > 0) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SRRoomSelectedNotification" object:self.internalRooms.firstObject];
            }
        });
    }
    return self;
}

- (NSArray<RoomConfig *> *)rooms {
    return [self.internalRooms copy];
}

- (NSDictionary<NSString *, SSBRoomClient *> *)clients {
    return [self.internalClients copy];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)roomEndpoints {
    return [self.internalRoomEndpoints copy];
}

- (void)joinRoomWithInvite:(NSString *)invite completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if ([invite hasPrefix:@"http"]) {
        NSData *savedIdentity = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
        NSString *myId;
        if (savedIdentity && savedIdentity.length >= 64) {
            NSData *pkData = [savedIdentity subdataWithRange:NSMakeRange(32, 32)];
            myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
        } else {
            return;
        }
        
        [RoomInviteHandler resolveHTTPSInvite:invite localId:myId completion:^(RoomConfig * _Nullable config, NSError * _Nullable error) {
            if (config) {
                [self handleJoinWithConfig:config];
                if (completion) completion(YES, nil);
            } else {
                if (completion) completion(NO, error);
            }
        }];
    } else {
        RoomConfig *config = [RoomInviteHandler parseInviteCode:invite];
        if (config) {
            [self handleJoinWithConfig:config];
            if (completion) completion(YES, nil);
        } else {
            if (completion) completion(NO, [NSError errorWithDomain:@"SRRoomManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid invite code"}]);
        }
    }
}

- (void)handleJoinWithConfig:(RoomConfig *)config {
    [RoomStorage saveRoom:config];
    [self.internalRooms addObject:config];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
    });
    [self connectToRoom:config];
}

- (void)connectToRoom:(RoomConfig *)config {
    if (self.internalClients[config.host]) {
        NSLog(@"[RoomManager] Already have a client for %@", config.host);
        return;
    }
    
    NSData *savedIdentity = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
    NSLog(@"[RoomManager] Creating client for %@ (identity present: %d)", config.host, savedIdentity != nil);
    
    SSBRoomClient *client = [[SSBRoomClient alloc] initWithConfig:config localIdentity:savedIdentity];
    client.delegate = self;
    client.autoReconnect = YES;
    self.internalClients[config.host] = client;
    [client connect];
}

#pragma mark - SSBRoomClientDelegate

- (void)roomClientDidConnect:(SSBRoomClient *)client {
    NSLog(@"[RoomManager] SUCCESS: Client connected to %@", client.host);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification object:client];
    });
}

- (void)roomClient:(SSBRoomClient *)client didUpdateEndpoints:(NSArray<NSString *> *)endpoints {
    NSLog(@"[RoomManager] Client %@ updated endpoints: %lu peers", client.host, (unsigned long)endpoints.count);
    self.internalRoomEndpoints[client.host] = endpoints;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateEndpointsNotification object:client];
        NSLog(@"[RoomManager] DEBUG: Sent notification for %@", client.host);
    });
}

- (void)roomClient:(SSBRoomClient *)client didEncounterError:(NSError *)error {
    NSLog(@"[RoomManager] ERROR: Client %@ encountered error: %@", client.host, error.localizedDescription);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerConnectionStatusChangedNotification object:client];
    });
}

- (void)disconnectFromRoom:(NSString *)host {
    SSBRoomClient *client = self.internalClients[host];
    [client disconnect];
}

- (void)removeRoom:(RoomConfig *)config {
    [RoomStorage removeRoom:config];
    [self disconnectFromRoom:config.host];
    [self.internalClients removeObjectForKey:config.host];
    [self.internalRooms removeObject:config];
    [self.internalRoomEndpoints removeObjectForKey:config.host];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
    });
}

- (nullable SSBRoomClient *)clientForHost:(NSString *)host {
    return self.internalClients[host];
}

@end