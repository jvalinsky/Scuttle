#import "SRGitRemoteHelperServer.h"
#import "../../Sources/SSBGitRepo.h"
#import "../../Sources/SSBBlobStore.h"
#import "../../Sources/SSBFeedStore.h"
#import "../Logic/SRRoomManager.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import "SRPlatformLog.h"

static os_log_t server_log;

static NSString *SRScuttleSocketDirectory(void) {
    NSString *xdgState = NSProcessInfo.processInfo.environment[@"XDG_STATE_HOME"];
    if (xdgState.length > 0) {
        return [xdgState stringByAppendingPathComponent:@"scuttle"];
    }

    NSString *xdgData = NSProcessInfo.processInfo.environment[@"XDG_DATA_HOME"];
    if (xdgData.length > 0) {
        return [xdgData stringByAppendingPathComponent:@"scuttle"];
    }

    return [NSHomeDirectory() stringByAppendingPathComponent:@".local/state/scuttle"];
}

static NSString *SRScuttleSocketPath(void) {
    return [SRScuttleSocketDirectory() stringByAppendingPathComponent:@"scuttle_helper.sock"];
}

@interface SRGitRemoteClient : NSObject
@property (nonatomic, assign) int fd;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) NSUInteger expectedPackBytes;
@property (nonatomic, assign) NSUInteger expectedIdxBytes;
@property (nonatomic, strong) NSString *pendingRepoID;
@property (nonatomic, strong) NSString *pendingRef;
@property (nonatomic, strong) NSString *pendingSHA;
@end

@implementation SRGitRemoteClient
@end

@interface SRGitRemoteHelperServer () {
    int _serverSocket;
    dispatch_source_t _listenSource;
}
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SRGitRemoteClient *> *clients;
@end

@implementation SRGitRemoteHelperServer

+ (instancetype)sharedServer {
    static SRGitRemoteHelperServer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRGitRemoteHelperServer alloc] init];
        server_log = os_log_create("com.scuttle.app", "GitHelperServer");
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _serverSocket = -1;
        _clients = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)start {
    NSString *socketDir = SRScuttleSocketDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:socketDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *socketPath = SRScuttleSocketPath();
    unlink([socketPath UTF8String]);
    
    _serverSocket = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_serverSocket == -1) {
        os_log_error(server_log, "Failed to create socket");
        return NO;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [socketPath UTF8String], sizeof(addr.sun_path) - 1);
    
    if (bind(_serverSocket, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        os_log_error(server_log, "Failed to bind socket: %{public}s", strerror(errno));
        close(_serverSocket);
        return NO;
    }
    
    if (listen(_serverSocket, 5) == -1) {
        os_log_error(server_log, "Failed to listen on socket");
        close(_serverSocket);
        return NO;
    }
    
    _listenSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _serverSocket, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(_listenSource, ^{
        int clientSocket = accept(self->_serverSocket, NULL, NULL);
        if (clientSocket != -1) {
            [self handleClient:clientSocket];
        }
    });
    dispatch_resume(_listenSource);
    
    os_log_info(server_log, "Started Git helper server at %{public}@", socketPath);
    return YES;
}

- (void)stop {
    if (_listenSource) {
        dispatch_source_cancel(_listenSource);
        _listenSource = nil;
    }
    if (_serverSocket != -1) {
        close(_serverSocket);
        _serverSocket = -1;
    }
    NSString *socketPath = SRScuttleSocketPath();
    unlink([socketPath UTF8String]);
}

- (void)handleClient:(int)fd {
    SRGitRemoteClient *client = [[SRGitRemoteClient alloc] init];
    client.fd = fd;
    client.buffer = [NSMutableData data];
    self.clients[@(fd)] = client;
    
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
    
    dispatch_source_set_event_handler(source, ^{
        char readBuf[4096];
        ssize_t bytesRead = read(fd, readBuf, sizeof(readBuf));
        if (bytesRead <= 0) {
            dispatch_source_cancel(source);
            return;
        }
        
        [client.buffer appendBytes:readBuf length:bytesRead];
        [self processClientData:client];
    });
    
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
        [self.clients removeObjectForKey:@(fd)];
    });
    
    dispatch_resume(source);
}

- (void)processClientData:(SRGitRemoteClient *)client {
    NSUInteger totalExpected = client.expectedPackBytes + client.expectedIdxBytes;
    if (totalExpected > 0) {
        if (client.buffer.length >= totalExpected) {
            NSData *packData = [client.buffer subdataWithRange:NSMakeRange(0, client.expectedPackBytes)];
            NSData *idxData = [client.buffer subdataWithRange:NSMakeRange(client.expectedPackBytes, client.expectedIdxBytes)];
            [client.buffer replaceBytesInRange:NSMakeRange(0, totalExpected) withBytes:NULL length:0];
            client.expectedPackBytes = 0;
            client.expectedIdxBytes = 0;
            [self handlePushPackData:packData idxData:idxData forClient:client];
        }
        return;
    }
    
    // Line-based command processing
    uint8_t *p = (uint8_t *)client.buffer.bytes;
    for (NSUInteger i = 0; i < client.buffer.length; i++) {
        if (p[i] == '\n') {
            NSData *lineData = [client.buffer subdataWithRange:NSMakeRange(0, i)];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            [client.buffer replaceBytesInRange:NSMakeRange(0, i + 1) withBytes:NULL length:0];
            
            [self processCommand:line forClient:client];
            // Restart loop since buffer changed
            [self processClientData:client];
            return;
        }
    }
}

- (void)processCommand:(NSString *)command forClient:(SRGitRemoteClient *)client {
    NSArray *parts = [command componentsSeparatedByString:@" "];
    if (parts.count == 0) return;
    
    NSString *cmd = parts[0];
    int fd = client.fd;
    
    if ([cmd isEqualToString:@"LIST"] && parts.count >= 2) {
        NSString *repoID = parts[1];
        SSBGitRepo *repo = [[SSBGitRepo alloc] initWithRepoID:repoID feedStore:[SSBFeedStore sharedStore] objectStore:[[SSBGitObjectStore alloc] initWithBlobStore:[SSBBlobStore sharedStore]]];
        NSDictionary *refs = [repo currentRefs];
        
        NSMutableString *response = [NSMutableString string];
        for (NSString *ref in refs) {
            [response appendFormat:@"%@ %@\n", ref, refs[ref]];
        }
        [response appendString:@"END\n"];
        
        NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
        write(fd, data.bytes, data.length);
    } else if ([cmd isEqualToString:@"FETCH_BLOB"] && parts.count >= 2) {
        NSString *blobID = parts[1];
        NSString *path = [[SSBBlobStore sharedStore] localPathForBlobID:blobID];
        
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSString *header = [NSString stringWithFormat:@"SEND_BLOB %lu\n", (unsigned long)data.length];
            write(fd, [header UTF8String], header.length);
            write(fd, data.bytes, data.length);
        } else {
            write(fd, "ERROR Blob not found\n", 21);
        }
    } else if ([cmd isEqualToString:@"FETCH_SHA"] && parts.count >= 3) {
        NSString *repoID = parts[1];
        NSString *sha = parts[2];
        SSBGitObjectStore *objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:[SSBBlobStore sharedStore]];
        SSBGitRepo *repo = [[SSBGitRepo alloc] initWithRepoID:repoID feedStore:[SSBFeedStore sharedStore] objectStore:objectStore];
        
        // Populate the object store with packs from the repo history
        [repo currentRefs]; 
        
        NSString *packBlobID = [objectStore packBlobIDForSHA1:sha];
        if (packBlobID) {
            NSString *path = [[SSBBlobStore sharedStore] localPathForBlobID:packBlobID];
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSString *header = [NSString stringWithFormat:@"SEND_PACK %lu\n", (unsigned long)data.length];
            write(fd, [header UTF8String], header.length);
            write(fd, data.bytes, data.length);
        } else {
            write(fd, "ERROR SHA not found\n", 20);
        }
    } else if ([cmd isEqualToString:@"PUSH"] && parts.count >= 6) {
        // PUSH <repoID> <ref> <sha> <pack_size> <idx_size>
        client.pendingRepoID = parts[1];
        client.pendingRef = parts[2];
        client.pendingSHA = parts[3];
        client.expectedPackBytes = [parts[4] integerValue];
        client.expectedIdxBytes = [parts[5] integerValue];
    }
}

- (void)handlePushPackData:(NSData *)packData idxData:(NSData *)idxData forClient:(SRGitRemoteClient *)client {
    NSString *tempPackPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *tempIdxPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    
    [packData writeToFile:tempPackPath atomically:YES];
    [idxData writeToFile:tempIdxPath atomically:YES];
    
    [SSBGitRepo uploadBlobAtURL:[NSURL fileURLWithPath:tempPackPath] completion:^(NSString * _Nullable packBlobID, NSError * _Nullable error) {
        if (!packBlobID) {
            write(client.fd, "ERROR Pack upload failed\n", 25);
            [[NSFileManager defaultManager] removeItemAtPath:tempPackPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempIdxPath error:nil];
            return;
        }
        
        [SSBGitRepo uploadBlobAtURL:[NSURL fileURLWithPath:tempIdxPath] completion:^(NSString * _Nullable idxBlobID, NSError * _Nullable error) {
            [[NSFileManager defaultManager] removeItemAtPath:tempPackPath error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tempIdxPath error:nil];
            
            if (!idxBlobID) {
                write(client.fd, "ERROR Idx upload failed\n", 24);
                return;
            }
            
            SSBGitObjectStore *objectStore = [[SSBGitObjectStore alloc] initWithBlobStore:[SSBBlobStore sharedStore]];
            SSBGitRepo *repo = [[SSBGitRepo alloc] initWithRepoID:client.pendingRepoID
                                                        feedStore:[SSBFeedStore sharedStore]
                                                       objectStore:objectStore];
            [repo publishUpdateWithRefs:@{client.pendingRef: client.pendingSHA}
                                  packs:@[packBlobID]
                                indexes:@[idxBlobID]
                                 client:[[SRRoomManager sharedManager] anyConnectedClient]
                             completion:^(NSString * _Nullable msgID, NSError * _Nullable error) {
                if (msgID) {
                    write(client.fd, "OK\n", 3);
                } else {
                    write(client.fd, "ERROR Publish failed\n", 21);
                }
            }];
        }];
    }];
}

@end
