#import <Foundation/Foundation.h>
#import <SSBNetwork/RoomInviteHandler.h>

@interface RoomStorage : NSObject
+ (void)saveRoom:(RoomConfig *)config;
+ (void)removeRoom:(RoomConfig *)config;
+ (NSArray<RoomConfig *> *)listRooms;
+ (void)clearAll;
@end
