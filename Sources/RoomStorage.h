#import <Foundation/Foundation.h>
#import "RoomInviteHandler.h"

@interface RoomStorage : NSObject
+ (void)saveRoom:(RoomConfig *)config;
+ (void)removeRoom:(RoomConfig *)config;
+ (NSArray<RoomConfig *> *)listRooms;
+ (void)clearAll;
@end
