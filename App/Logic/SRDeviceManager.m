#import "SRDeviceManager.h"
#import "SRRoomManager.h"
#import "../../Sources/SSBFeedStore.h"
#import "../../Sources/SSBRoomClient.h"
#import <SSBNetwork/SSBKeychain.h>
#import <os/log.h>

static os_log_t device_log;

/// NSUserDefaults key for the local device's sub-feed ID once registered.
static NSString * const kDeviceFeedIDKey = @"com.scuttlebutt.deviceFeedID";

@implementation SRDeviceManager

+ (void)initialize {
    if (self == [SRDeviceManager class]) {
        device_log = os_log_create("com.scuttlebutt.app", "DeviceManager");
    }
}

+ (instancetype)sharedManager {
    static SRDeviceManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SRDeviceManager alloc] init];
    });
    return shared;
}

- (void)registerThisDeviceIfNeeded {
    // Already registered in a previous session.
    NSString *existing = [[NSUserDefaults standardUserDefaults] stringForKey:kDeviceFeedIDKey];
    if (existing.length > 0) {
        os_log_info(device_log, "Device feed already registered: %{public}@", existing);
        return;
    }

    NSData *seed = [SSBKeychain loadMetafeedSeed];
    NSString *metafeedRootID = [SSBKeychain loadMetafeedRootID];
    if (!seed || !metafeedRootID) {
        os_log_error(device_log, "registerThisDevice: no metafeed seed; skipping");
        return;
    }

    SSBMetafeed *rootMetafeed = [SSBMetafeed createRootMetafeedFromSeed:seed];
    if (!rootMetafeed) return;

    // Build a deterministic nonce from host name + a stable per-install UUID.
    // The install UUID is generated once and stored in NSUserDefaults.
    static NSString * const kInstallUUIDKey = @"com.scuttlebutt.installUUID";
    NSString *deviceID = [[NSUserDefaults standardUserDefaults] stringForKey:kInstallUUIDKey];
    if (!deviceID) {
        deviceID = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:deviceID forKey:kInstallUUIDKey];
    }
    NSString *deviceName = [[NSProcessInfo processInfo] hostName];
    NSString *nonceSource = [NSString stringWithFormat:@"%@:%@", deviceName, deviceID];
    NSData *nonce = [[nonceSource dataUsingEncoding:NSUTF8StringEncoding]
                     subdataWithRange:NSMakeRange(0, MIN(32, nonceSource.length))];
    // Pad to 32 bytes.
    if (nonce.length < 32) {
        NSMutableData *padded = [nonce mutableCopy];
        [padded increaseLengthBy:32 - nonce.length];
        nonce = padded;
    }

    NSDictionary *content = [rootMetafeed addDerivedFeedMessage:deviceName
                                                        purpose:SSBMetafeedPurposeV1
                                                          nonce:nonce];
    if (!content) {
        os_log_error(device_log, "registerThisDevice: failed to create add/derived message");
        return;
    }

    SSBRoomClient *client = [SRRoomManager sharedManager].clients.allValues.firstObject;
    if (!client) {
        os_log_error(device_log, "registerThisDevice: no connected client; deferring");
        return;
    }

    NSError *error;
    SSBMessage *published = [client publishLocalMessageWithContent:content error:&error];
    if (published) {
        NSString *subfeedID = content[@"subfeed"];
        [[NSUserDefaults standardUserDefaults] setObject:subfeedID forKey:kDeviceFeedIDKey];
        os_log_info(device_log, "Registered device subfeed: %{public}@", subfeedID);
    } else {
        os_log_error(device_log, "registerThisDevice publish failed: %{public}@",
                     error.localizedDescription);
    }
}

- (NSArray<NSString *> *)registeredDeviceFeedIDs {
    NSString *metafeedRootID = [SSBKeychain loadMetafeedRootID];
    if (!metafeedRootID) return @[];
    return [[SSBFeedStore sharedStore] deviceFeedIDsForMetafeedID:metafeedRootID];
}

- (void)deregisterDeviceWithFeedID:(NSString *)feedID {
    [[SRRoomManager sharedManager] revokeSubfeed:feedID reason:@"device deregistered"];

    // Clear the local cache if this is our own device feed.
    NSString *localFeedID = [[NSUserDefaults standardUserDefaults] stringForKey:kDeviceFeedIDKey];
    if ([localFeedID isEqualToString:feedID]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDeviceFeedIDKey];
    }
    os_log_info(device_log, "Deregistered device feed: %{public}@", feedID);
}

@end
