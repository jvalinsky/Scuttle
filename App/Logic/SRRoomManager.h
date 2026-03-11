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

/**
 * Resolves the display name for a given author by querying the feed store for About messages.
 */
- (void)resolveDisplayNameForAuthor:(NSString *)author completion:(void(^)(NSString *name))completion;

@end

NS_ASSUME_NONNULL_END