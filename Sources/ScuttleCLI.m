#import <Foundation/Foundation.h>
#import "SSBLogCompat.h"
#import "SSBKeychain.h"
#import "SSBFeedStore.h"
#import "SSBRoomClient.h"
#import "RoomInviteHandler.h"
#import "SSBBlobStore.h"
#import "SSBBIPF.h"

@interface ScuttleCLI : NSObject
@property (strong) SSBFeedStore *feedStore;
@property (strong) SSBBlobStore *blobStore;
@property (assign) BOOL shouldExit;
@end

@implementation ScuttleCLI

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *scuttleDir = [NSHomeDirectory() stringByAppendingPathComponent: @".local/share/scuttle"];
        [[NSFileManager defaultManager] createDirectoryAtPath:scuttleDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *dbPath = [scuttleDir stringByAppendingPathComponent:@"ssb.db"];
        self.feedStore = [[SSBFeedStore alloc] initWithPath:dbPath];
        
        NSString *blobPath = [scuttleDir stringByAppendingPathComponent:@"blobs"];
        self.blobStore = [[SSBBlobStore alloc] initWithPath:blobPath];
    }
    return self;
}

- (void)printUsage {
    printf("Scuttle CLI (GNUstep/Linux)\n");
    printf("Usage: scuttle-cli <command> [args]\n\n");
    printf("Commands:\n");
    printf("  invite <code>    Accept an invite to a room server\n");
    printf("  peers            List peers from connected rooms\n");
    printf("  follow <id>      Follow a feed ID\n");
    printf("  publish <text>   Publish a new post\n");
    printf("  timeline         List your timeline\n");
    printf("  whoami           Display your public ID\n");
}

- (void)runWithArguments:(NSArray<NSString *> *)args {
    if (args.count < 2) {
        [self printUsage];
        self.shouldExit = YES;
        return;
    }
    
    NSString *command = args[1];
    
    if ([command isEqualToString:@"whoami"]) {
        NSData *secret = [SSBKeychain loadIdentitySecret];
        if (!secret) {
            printf("No identity found.\n");
        } else {
            NSString *publicID = [SSBKeychain publicIDFromSecret:secret];
            printf("Your ID: %s\n", [publicID UTF8String]);
        }
        self.shouldExit = YES;
    } 
    else if ([command isEqualToString:@"invite"]) {
        if (args.count < 3) {
            printf("Usage: scuttle-cli invite <code|url>\n");
            self.shouldExit = YES;
            return;
        }
        NSString *input = args[2];
        printf("Processing invite: %s\n", [input UTF8String]);
        
        if ([input hasPrefix:@"http"]) {
            NSData *secret = [SSBKeychain loadIdentitySecret];
            NSString *localId = [SSBKeychain publicIDFromSecret:secret] ?: @"";
            [RoomInviteHandler resolveHTTPSInvite:input localId:localId completion:^(RoomConfig *config, NSError *error) {
                if (config) {
                    printf("Invite resolved! Room: %s:%ld\n", [config.host UTF8String], (long)config.port);
                } else {
                    printf("Error: %s\n", [error.localizedDescription UTF8String]);
                }
                self.shouldExit = YES;
            }];
        } else {
            RoomConfig *config = [RoomInviteHandler parseInviteCode:input];
            if (config) {
                printf("Invite parsed! Room: %s:%ld\n", [config.host UTF8String], (long)config.port);
            } else {
                printf("Failed to parse invite code.\n");
            }
            self.shouldExit = YES;
        }
    }
    else if ([command isEqualToString:@"follow"]) {
        if (args.count < 3) {
            printf("Usage: scuttle-cli follow <feedId>\n");
            self.shouldExit = YES;
            return;
        }
        NSString *feedId = args[2];
        printf("Following feed: %s\n", [feedId UTF8String]);
        
        // Record that we follow this author
        [self.feedStore setFollowing:YES forAuthor:feedId atSequence:0];
        
        printf("Now following %s\n", [feedId UTF8String]);
        self.shouldExit = YES;
    }
    else if ([command isEqualToString:@"publish"]) {
        if (args.count < 3) {
            printf("Usage: scuttle-cli publish <text>\n");
            self.shouldExit = YES;
            return;
        }
        NSString *text = args[2];
        printf("Publishing: %s\n", [text UTF8String]);
        
        // Get our identity
        NSData *secret = [SSBKeychain loadIdentitySecret];
        if (!secret) {
            printf("Error: No identity found. Please create an identity first.\n");
            self.shouldExit = YES;
            return;
        }
        
        // Create a post message
        NSDictionary *content = @{@"text": text};
        NSData *jsonData = [SSBBIPF encode:content];
        
        SSBMessage *msg = [[SSBMessage alloc] initWithAuthor:[SSBKeychain publicIDFromSecret:secret]
                                                     content:jsonData];
        
        // Append to our feed
        NSError *error = nil;
        BOOL success = [self.feedStore appendMessage:msg error:&error];
        if (success) {
            printf("Published successfully!\n");
        } else {
            printf("Failed to publish: %s\n", [error.localizedDescription UTF8String]);
        }
        self.shouldExit = YES;
    }
    else if ([command isEqualToString:@"timeline"]) {
        NSArray<SSBMessage *> *messages = [self.feedStore timelineWithLimit:20];
        if (messages.count == 0) {
            printf("Timeline is empty.\n");
        } else {
            for (SSBMessage *msg in messages) {
                NSString *author = msg.author;
                NSString *contentStr = @"";
                id content = msg.content;
                
                if ([content isKindOfClass:[NSData class]]) {
                    content = [SSBBIPF decode:content consumed:NULL];
                }
                
                if ([content isKindOfClass:[NSDictionary class]]) {
                    contentStr = content[@"text"] ?: content[@"type"];
                }
                
                printf("[%lld] %s: %s\n", 
                       (long long)msg.claimedTimestamp,
                       [[author substringToIndex:MIN(10, author.length)] UTF8String],
                       [contentStr UTF8String]);
            }
        }
        self.shouldExit = YES;
    }
    else {
        printf("Unknown command: %s\n", [command UTF8String]);
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
        
        // Wait for async tasks if needed
        while (!cli.shouldExit && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]) {
            // Processing...
        }
    }
    return 0;
}
