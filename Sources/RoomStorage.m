#import "RoomStorage.h"

@implementation RoomStorage

+ (void)saveRoom:(RoomConfig *)config {
    NSMutableArray *rooms = [[self listRooms] mutableCopy];
    // Check for duplicates
    NSInteger existingIdx = -1;
    for (NSInteger i = 0; i < rooms.count; i++) {
        RoomConfig *r = rooms[i];
        if ([r.host isEqualToString:config.host] && r.port == config.port) {
            existingIdx = i;
            break;
        }
    }
    
    if (existingIdx != -1) {
        rooms[existingIdx] = config;
    } else {
        [rooms addObject:config];
    }
    
    NSError *error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rooms requiringSecureCoding:YES error:&error];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"JoinedRooms"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

+ (void)removeRoom:(RoomConfig *)config {
    NSMutableArray *rooms = [[self listRooms] mutableCopy];
    NSInteger existingIdx = -1;
    for (NSInteger i = 0; i < rooms.count; i++) {
        RoomConfig *r = rooms[i];
        if ([r.host isEqualToString:config.host] && r.port == config.port) {
            existingIdx = i;
            break;
        }
    }
    
    if (existingIdx != -1) {
        [rooms removeObjectAtIndex:existingIdx];
        NSError *error;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rooms requiringSecureCoding:YES error:&error];
        if (data) {
            [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"JoinedRooms"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

+ (NSArray<RoomConfig *> *)listRooms {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"JoinedRooms"];
    if (!data) return @[];
    
    NSError *error;
    NSArray *rooms = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [RoomConfig class]]] fromData:data error:&error];
    return rooms ?: @[];
}

+ (void)clearAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"JoinedRooms"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
