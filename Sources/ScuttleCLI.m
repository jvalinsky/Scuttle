#import <Foundation/Foundation.h>
#import "SSBLogCompat.h"
#import "SSBSecretStore.h"
#import "SSBFeedStore.h"
#import "SSBRoomClient.h"
#import "SSBMessageCodec.h"
#import "SSBMetafeed.h"
#import "RoomInviteHandler.h"
#import "RoomStorage.h"
#import "SSBBlobStore.h"
#import "SSBBIPF.h"

@interface ScuttleCLI : NSObject
@property (strong) SSBFeedStore *feedStore;
@property (strong) SSBBlobStore *blobStore;
@property (strong) SSBRoomClient *client;
@property (assign) BOOL shouldExit;
@end

@implementation ScuttleCLI

static NSString *ScuttleDataDirectory(void) {
    NSString *xdgData = NSProcessInfo.processInfo.environment[@"XDG_DATA_HOME"];
    if (xdgData.length > 0) {
        return [xdgData stringByAppendingPathComponent:@"scuttle"];
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/scuttle"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *scuttleDir = ScuttleDataDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:scuttleDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSString *dbPath = [scuttleDir stringByAppendingPathComponent:@"ssb.db"];
        self.feedStore = [[SSBFeedStore alloc] initWithPath:dbPath];

        NSString *blobPath = [scuttleDir stringByAppendingPathComponent:@"blobs"];
        self.blobStore = [[SSBBlobStore alloc] initWithPath:blobPath];
    }
    return self;
}

- (void)printUsage {
    printf("Scuttle CLI — Secure Scuttlebutt for Linux/GNUstep\n\n");
    printf("Usage: scuttle-cli <command> [args]\n\n");
    printf("Identity:\n");
    printf("  init             Generate a new SSB identity and metafeed seed\n");
    printf("  whoami           Display your public ID and metafeed root\n");
    printf("\n");
    printf("Social:\n");
    printf("  follow <id>      Follow a feed by ID\n");
    printf("  unfollow <id>    Unfollow a feed by ID\n");
    printf("  following        List feeds you follow\n");
    printf("  publish <text>   Publish a post to your feed\n");
    printf("  feed            Show your own messages\n");
    printf("  timeline         Show messages from followed feeds\n");
    printf("\n");
    printf("Rooms:\n");
    printf("  invite <code>    Parse/resolve a room invite\n");
    printf("  connect <host>   Connect to a saved room\n");
    printf("  rooms            List saved rooms\n");
    printf("  peers            List peers from last connection\n");
    printf("\n");
    printf("Info:\n");
    printf("  status           Show local database status\n");
}

#pragma mark - Identity

- (void)cmdInit {
    NSData *existing = SSBLoadIdentitySecret();
    if (existing) {
        NSString *publicID = SSBPublicIDFromSecret(existing);
        printf("Identity already exists: %s\n", [publicID UTF8String]);
        printf("Use 'whoami' to view details.\n");
        self.shouldExit = YES;
        return;
    }

    // Generate Ed25519 keypair
    NSData *secret = [SSBRoomClient generateLocalIdentity];
    if (!secret) {
        printf("Error: Failed to generate identity.\n");
        self.shouldExit = YES;
        return;
    }

    NSString *publicID = SSBPublicIDFromSecret(secret);
    printf("Generated identity: %s\n", [publicID UTF8String]);

    // Bootstrap metafeed
    NSData *existingSeed = SSBLoadMetafeedSeed();
    if (!existingSeed) {
        NSData *seed = [SSBMetafeed generateSeed];
        if (seed) {
            SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
            if (rootMetafeed) {
                SSBSaveMetafeedSeed(seed);
                SSBSaveMetafeedRootID(rootMetafeed.ID);
                printf("Metafeed root:     %s\n", [rootMetafeed.ID UTF8String]);
            }
        }
    }

    printf("\nIdentity stored in secure local storage. Ready to connect to rooms.\n");
    self.shouldExit = YES;
}

- (void)cmdWhoami {
    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) {
        printf("No identity found. Run 'scuttle-cli init' to create one.\n");
        self.shouldExit = YES;
        return;
    }
    NSString *publicID = SSBPublicIDFromSecret(secret);
    printf("Public ID:     %s\n", [publicID UTF8String]);

    NSString *rootID = SSBLoadMetafeedRootID();
    if (rootID) {
        printf("Metafeed root: %s\n", [rootID UTF8String]);
    } else {
        printf("Metafeed root: (not bootstrapped)\n");
    }

    SSBFeedState *state = [self.feedStore feedStateForAuthor:publicID];
    if (state) {
        printf("Feed sequence: %ld\n", (long)state.maxSequence);
    } else {
        printf("Feed sequence: 0 (no messages)\n");
    }
    self.shouldExit = YES;
}

#pragma mark - Social

- (void)cmdFollowWithArgs:(NSArray *)args {
    if (args.count < 3) {
        printf("Usage: scuttle-cli follow <feedId>\n");
        self.shouldExit = YES;
        return;
    }
    NSString *feedId = args[2];
    if (![feedId hasPrefix:@"@"]) {
        printf("Error: Feed ID must start with '@'\n");
        self.shouldExit = YES;
        return;
    }
    [self.feedStore setFollowing:YES forAuthor:feedId atSequence:0];
    printf("Now following %s\n", [feedId UTF8String]);
    self.shouldExit = YES;
}

- (void)cmdUnfollowWithArgs:(NSArray *)args {
    if (args.count < 3) {
        printf("Usage: scuttle-cli unfollow <feedId>\n");
        self.shouldExit = YES;
        return;
    }
    NSString *feedId = args[2];
    [self.feedStore setFollowing:NO forAuthor:feedId atSequence:0];
    printf("Unfollowed %s\n", [feedId UTF8String]);
    self.shouldExit = YES;
}

- (void)cmdFollowing {
    NSArray<NSString *> *followed = [self.feedStore followedAuthors];
    if (followed.count == 0) {
        printf("Not following anyone.\n");
    } else {
        printf("Following %lu feeds:\n", (unsigned long)followed.count);
        for (NSString *author in followed) {
            NSString *name = [self.feedStore displayNameForAuthor:author];
            if (name.length > 0) {
                printf("  %s  (%s)\n", [author UTF8String], [name UTF8String]);
            } else {
                printf("  %s\n", [author UTF8String]);
            }
        }
    }
    self.shouldExit = YES;
}

- (void)cmdPublishWithArgs:(NSArray *)args {
    if (args.count < 3) {
        printf("Usage: scuttle-cli publish <text>\n");
        self.shouldExit = YES;
        return;
    }
    // Join all remaining args as the text (allows unquoted multi-word posts)
    NSArray *textParts = [args subarrayWithRange:NSMakeRange(2, args.count - 2)];
    NSString *text = [textParts componentsJoinedByString:@" "];

    NSData *secret = SSBLoadIdentitySecret();
    if (!secret || secret.length < 64) {
        printf("Error: No identity. Run 'scuttle-cli init' first.\n");
        self.shouldExit = YES;
        return;
    }

    NSString *author = SSBPublicIDFromSecret(secret);
    SSBFeedState *state = [self.feedStore feedStateForAuthor:author];
    NSInteger nextSeq = state ? state.maxSequence + 1 : 1;
    NSString *previousKey = state.maxKey;

    NSDictionary *content = [SSBMessageCodec postContentWithText:text];
    NSDictionary *signedValue = [SSBMessageCodec createSignedMessageWithContent:content
                                                                         author:author
                                                                       sequence:nextSeq
                                                                    previousKey:previousKey
                                                                      secretKey:secret];
    if (!signedValue) {
        printf("Error: Failed to create signed message.\n");
        self.shouldExit = YES;
        return;
    }

    NSString *msgKey = [SSBMessageCodec computeMessageKey:signedValue];

    SSBMessage *msg = [[SSBMessage alloc] init];
    msg.key = msgKey;
    msg.author = author;
    msg.sequence = nextSeq;
    msg.previousKey = previousKey;
    msg.claimedTimestamp = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    msg.receivedAt = msg.claimedTimestamp;
    msg.content = content;
    msg.contentType = content[@"type"];
    msg.valueJSON = [SSBMessageCodec encodeLegacyValue:signedValue includeSignature:YES];

    NSError *error = nil;
    BOOL success = [self.feedStore appendMessage:msg error:&error];
    if (success) {
        printf("Published: %s\n", [msgKey UTF8String]);
    } else {
        printf("Failed: %s\n", [error.localizedDescription UTF8String]);
    }
    self.shouldExit = YES;
}

- (void)cmdTimeline {
    NSArray<SSBMessage *> *messages = [self.feedStore timelineWithLimit:20];
    if (messages.count == 0) {
        printf("Timeline is empty.\n");
        self.shouldExit = YES;
        return;
    }
    for (SSBMessage *msg in messages) {
        NSString *author = msg.author ?: @"?";
        NSString *shortAuthor = author.length > 10 ? [author substringToIndex:10] : author;
        NSString *name = [self.feedStore displayNameForAuthor:author];
        NSString *displayAuthor = name.length > 0 ? name : shortAuthor;

        NSString *contentStr = @"";
        NSDictionary *content = msg.content;
        if (content) {
            contentStr = content[@"text"] ?: content[@"type"] ?: @"";
        }

        // Format timestamp
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:msg.claimedTimestamp / 1000.0];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm";
        NSString *dateStr = [fmt stringFromDate:date];

        printf("[%s] %s: %s\n",
               [dateStr UTF8String],
               [displayAuthor UTF8String],
               [contentStr UTF8String]);
    }
    self.shouldExit = YES;
}

- (void)cmdFeed {
    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) {
        printf("Error: No identity. Run 'scuttle-cli init' first.\n");
        self.shouldExit = YES;
        return;
    }
    NSString *localId = SSBPublicIDFromSecret(secret);
    NSArray<SSBMessage *> *messages = [self.feedStore messagesForAuthor:localId fromSequence:1 limit:50];
    if (messages.count == 0) {
        printf("No messages yet. Run 'scuttle-cli publish \"Hello\"' to post.\n");
        self.shouldExit = YES;
        return;
    }
    for (SSBMessage *msg in [messages reverseObjectEnumerator]) {
        NSString *contentStr = @"";
        NSDictionary *content = msg.content;
        if (content) {
            contentStr = content[@"text"] ?: content[@"type"] ?: @"";
        }
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:msg.claimedTimestamp / 1000.0];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *dateStr = [fmt stringFromDate:date];
        printf("[%s] seq=%ld: %s\n",
               [dateStr UTF8String],
               (long)msg.sequence,
               [contentStr UTF8String]);
    }
    self.shouldExit = YES;
}

#pragma mark - Rooms

- (void)cmdInviteWithArgs:(NSArray *)args {
    if (args.count < 3) {
        printf("Usage: scuttle-cli invite <code|url>\n");
        self.shouldExit = YES;
        return;
    }
    NSString *input = args[2];
    printf("Processing invite: %s\n", [input UTF8String]);

    if ([input hasPrefix:@"http"]) {
        NSData *secret = SSBLoadIdentitySecret();
        if (!secret) {
            printf("Error: No identity. Run 'scuttle-cli init' first.\n");
            self.shouldExit = YES;
            return;
        }
        NSString *localId = SSBPublicIDFromSecret(secret);
        __weak typeof(self) weakSelf = self;
        [RoomInviteHandler resolveHTTPSInvite:input localId:localId completion:^(RoomConfig *config, NSError *error) {
            if (config) {
                [RoomStorage saveRoom:config];
                printf("Room saved: %s:%ld\n", [config.host UTF8String], (long)config.port);
                printf("Run 'scuttle-cli connect %s' to connect.\n", [config.host UTF8String]);
            } else {
                printf("Error: %s\n", [error.localizedDescription UTF8String]);
            }
            weakSelf.shouldExit = YES;
        }];
    } else {
        RoomConfig *config = [RoomInviteHandler parseInviteCode:input];
        if (config) {
            [RoomStorage saveRoom:config];
            printf("Room saved: %s:%ld\n", [config.host UTF8String], (long)config.port);
            printf("Run 'scuttle-cli connect %s' to connect.\n", [config.host UTF8String]);
        } else {
            printf("Failed to parse invite code.\n");
        }
        self.shouldExit = YES;
    }
}

- (void)cmdRooms {
    NSArray<RoomConfig *> *rooms = [RoomStorage listRooms];
    if (rooms.count == 0) {
        printf("No saved rooms. Use 'scuttle-cli invite <code>' to add one.\n");
    } else {
        printf("Saved rooms:\n");
        for (RoomConfig *room in rooms) {
            printf("  %s:%ld\n", [room.host UTF8String], (long)room.port);
        }
    }
    self.shouldExit = YES;
}

- (void)cmdConnectWithArgs:(NSArray *)args {
    if (args.count < 3) {
        printf("Usage: scuttle-cli connect <host>\n");
        self.shouldExit = YES;
        return;
    }
    NSString *host = args[2];

    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) {
        printf("Error: No identity. Run 'scuttle-cli init' first.\n");
        self.shouldExit = YES;
        return;
    }

    // Find the saved room config
    NSArray<RoomConfig *> *rooms = [RoomStorage listRooms];
    RoomConfig *target = nil;
    for (RoomConfig *room in rooms) {
        if ([room.host isEqualToString:host]) {
            target = room;
            break;
        }
    }
    if (!target) {
        printf("No saved room for host '%s'. Use 'invite' first.\n", [host UTF8String]);
        self.shouldExit = YES;
        return;
    }

    printf("Connecting to %s:%ld...\n", [target.host UTF8String], (long)target.port);

    self.client = [[SSBRoomClient alloc] initWithConfig:target localIdentity:secret];
    __weak typeof(self) weakSelf = self;

    // Set up a timeout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf.shouldExit) {
            printf("Connection timed out after 30 seconds.\n");
            [weakSelf.client disconnect];
            weakSelf.shouldExit = YES;
        }
    });

    [self.client connect];

    // Monitor connection state via KVO-like polling (simple approach for CLI)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.client.isConnected) {
            printf("Connected to %s\n", [host UTF8String]);
            printf("Replicating... (press Ctrl+C to stop)\n");
        } else {
            printf("Still connecting...\n");
        }
    });
}

- (void)cmdPeers {
    // Show cached attendants from last connection if available
    NSData *secret = SSBLoadIdentitySecret();
    if (!secret) {
        printf("Error: No identity.\n");
        self.shouldExit = YES;
        return;
    }
    printf("Peer list requires an active connection.\n");
    printf("Use 'scuttle-cli connect <host>' to connect to a room.\n");
    self.shouldExit = YES;
}

#pragma mark - Info

- (void)cmdStatus {
    printf("Scuttle Status\n");
    printf("==============\n\n");

    NSData *secret = SSBLoadIdentitySecret();
    if (secret) {
        NSString *publicID = SSBPublicIDFromSecret(secret);
        printf("Identity:  %s\n", [publicID UTF8String]);
    } else {
        printf("Identity:  (none — run 'init')\n");
    }

    NSString *rootID = SSBLoadMetafeedRootID();
    printf("Metafeed:  %s\n", rootID ? [rootID UTF8String] : "(none)");

    NSInteger totalMsgs = [self.feedStore totalMessageCount];
    printf("Messages:  %ld\n", (long)totalMsgs);

    NSArray<NSString *> *followed = [self.feedStore followedAuthors];
    printf("Following: %lu feeds\n", (unsigned long)followed.count);

    NSArray<RoomConfig *> *rooms = [RoomStorage listRooms];
    printf("Rooms:     %lu saved\n", (unsigned long)rooms.count);

    NSDictionary<NSString *, NSNumber *> *stats = [self.feedStore storageStatistics];
    printf("Authors:   %lu known\n", (unsigned long)stats.count);

    NSUInteger blobSize = [self.blobStore totalStorageSize];
    if (blobSize > 1024 * 1024) {
        printf("Blobs:     %.1f MB\n", blobSize / (1024.0 * 1024.0));
    } else if (blobSize > 1024) {
        printf("Blobs:     %.1f KB\n", blobSize / 1024.0);
    } else {
        printf("Blobs:     %lu bytes\n", (unsigned long)blobSize);
    }

    self.shouldExit = YES;
}

#pragma mark - Dispatch

- (void)runWithArguments:(NSArray<NSString *> *)args {
    if (args.count < 2) {
        [self printUsage];
        self.shouldExit = YES;
        return;
    }

    NSString *command = args[1];

    if ([command isEqualToString:@"init"])           { [self cmdInit]; }
    else if ([command isEqualToString:@"whoami"])     { [self cmdWhoami]; }
    else if ([command isEqualToString:@"follow"])     { [self cmdFollowWithArgs:args]; }
    else if ([command isEqualToString:@"unfollow"])   { [self cmdUnfollowWithArgs:args]; }
    else if ([command isEqualToString:@"following"])  { [self cmdFollowing]; }
    else if ([command isEqualToString:@"publish"])    { [self cmdPublishWithArgs:args]; }
    else if ([command isEqualToString:@"feed"])        { [self cmdFeed]; }
    else if ([command isEqualToString:@"timeline"])   { [self cmdTimeline]; }
    else if ([command isEqualToString:@"invite"])     { [self cmdInviteWithArgs:args]; }
    else if ([command isEqualToString:@"rooms"])      { [self cmdRooms]; }
    else if ([command isEqualToString:@"connect"])    { [self cmdConnectWithArgs:args]; }
    else if ([command isEqualToString:@"peers"])      { [self cmdPeers]; }
    else if ([command isEqualToString:@"status"])     { [self cmdStatus]; }
    else if ([command isEqualToString:@"help"] || [command isEqualToString:@"--help"] || [command isEqualToString:@"-h"]) {
        [self printUsage];
        self.shouldExit = YES;
    }
    else {
        printf("Unknown command: %s\n\n", [command UTF8String]);
        [self printUsage];
        self.shouldExit = YES;
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        ScuttleCLI *cli = [[ScuttleCLI alloc] init];
        NSArray *args = [[NSProcessInfo processInfo] arguments];

        [cli runWithArguments:args];

        // Run the event loop for async operations (invite resolution, room connection)
        while (!cli.shouldExit && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]) {
            // Processing...
        }
    }
    return 0;
}
