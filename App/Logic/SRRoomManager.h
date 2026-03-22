#import <Foundation/Foundation.h>
#import "../../Sources/SSBNetwork.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SRRoomManagerDidUpdateRoomsNotification;
extern NSString * const SRRoomManagerDidUpdateEndpointsNotification;
extern NSString * const SRRoomManagerConnectionStatusChangedNotification;
extern NSString * const SRRoomManagerEndpointsHostKey;
extern NSString * const SRRoomManagerEndpointsListKey;
extern NSString * const SRRoomManagerErrorDomain;

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

/// Returns any currently connected room client, or nil if none are connected.
- (nullable SSBRoomClient *)anyConnectedClient;

/// Publishes a metafeed/tombstone message revoking the given sub-feed key.
- (void)revokeSubfeed:(NSString *)feedID reason:(nullable NSString *)reason;

/// Derives a new sub-feed key, publishes an add/derived announcement, then tombstones
/// the old feed. Calls completion on the main queue with the new feed ID or an error.
- (void)replaceSubfeed:(NSString *)oldFeedID
            completion:(void(^)(NSString * _Nullable newFeedID, NSError * _Nullable error))completion;

/// Returns the cached display name for an author, or the author ID if none is stored yet.
- (NSString *)displayNameForAuthor:(NSString *)author;

- (NSDictionary<NSString *, NSString *> *)peerSyncStatesForHost:(NSString *)host;
- (NSDictionary<NSString *, NSNumber *> *)peerSyncProgressForHost:(NSString *)host;
- (nullable NSString *)syncStatusForHost:(NSString *)host;
- (float)syncProgressForHost:(NSString *)host;

/**
 * Resolves the display name for a given author by querying the feed store for About messages.
 */
- (void)resolveDisplayNameForAuthor:(NSString *)author completion:(void(^)(NSString *name))completion;

@end

NS_ASSUME_NONNULL_END
