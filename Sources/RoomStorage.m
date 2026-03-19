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
    
    NSData *data;
#if __has_include(<os/log.h>)
    // macOS: use secure coding APIs
    NSError *error;
    data = [NSKeyedArchiver archivedDataWithRootObject:rooms requiringSecureCoding:YES error:&error];
#else
    // GNUstep: fall back to non-secure archiver
    data = [NSKeyedArchiver archivedDataWithRootObject:rooms];
#endif
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
        NSData *data;
#if __has_include(<os/log.h>)
        NSError *error;
        data = [NSKeyedArchiver archivedDataWithRootObject:rooms requiringSecureCoding:YES error:&error];
#else
        data = [NSKeyedArchiver archivedDataWithRootObject:rooms];
#endif
        if (data) {
            [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"JoinedRooms"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

+ (NSArray<RoomConfig *> *)listRooms {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"JoinedRooms"];
    if (!data) return @[];
    
    NSArray *rooms;
#if __has_include(<os/log.h>)
    NSError *error;
    rooms = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [RoomConfig class]]] fromData:data error:&error];
#else
    rooms = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#endif
    return rooms ?: @[];
}

+ (void)clearAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"JoinedRooms"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
