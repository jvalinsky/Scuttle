#import <Foundation/Foundation.h>
#import "../../Sources/SSBNetwork.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SRRoomManagerDidUpdateRoomsNotification;
extern NSString * const SRRoomManagerDidUpdateEndpointsNotification;
extern NSString * const SRRoomManagerConnectionStatusChangedNotification;

@interface SRRoomManager : NSObject

@property (nonatomic, readonly) NSArray<RoomConfig *> *rooms;
@property (nonatomic, readonly) NSDictionary<NSString *, SSBRoomClient *> *clients;
@property (nonatomic, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *roomEndpoints;

+ (instancetype)sharedManager;

- (void)joinRoomWithInvite:(NSString *)invite completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)connectToRoom:(RoomConfig *)config;
- (void)disconnectFromRoom:(NSString *)host;
- (void)removeRoom:(RoomConfig *)config;
- (void)resetAccount;

- (nullable SSBRoomClient *)clientForHost:(NSString *)host;

/// Publishes a metafeed/tombstone message revoking the given sub-feed key.
- (void)revokeSubfeed:(NSString *)feedID reason:(nullable NSString *)reason;

/// Derives a new sub-feed key, publishes an add/derived announcement, then tombstones
/// the old feed. Calls completion on the main queue with the new feed ID or an error.
- (void)replaceSubfeed:(NSString *)oldFeedID
            completion:(void(^)(NSString * _Nullable newFeedID, NSError * _Nullable error))completion;

/**
 * Resolves the display name for a given author by querying the feed store for About messages.
 */
- (void)resolveDisplayNameForAuthor:(NSString *)author completion:(void(^)(NSString *name))completion;

@end

NS_ASSUME_NONNULL_END