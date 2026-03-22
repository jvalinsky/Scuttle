#import "SRSidebarItem.h"

@implementation SRSidebarItem

+ (instancetype)sectionItemWithTitle:(NSString *)title {
    SRSidebarItem *item = [[SRSidebarItem alloc] init];
    item.type = SRSidebarItemTypeSection;
    item.title = title;
    item.expandable = YES;
    item.children = [NSMutableArray array];
    return item;
}

+ (instancetype)roomItemWithTitle:(NSString *)title representedObject:(nullable id)obj {
    SRSidebarItem *item = [[SRSidebarItem alloc] init];
    item.type = SRSidebarItemTypeRoom;
    item.title = title;
    item.representedObject = obj;
    item.expandable = NO;
    item.children = [NSMutableArray array];
    return item;
}

+ (instancetype)channelItemWithTitle:(NSString *)title {
    SRSidebarItem *item = [[SRSidebarItem alloc] init];
    item.type = SRSidebarItemTypeChannel;
    item.title = title;
    item.expandable = NO;
    item.children = [NSMutableArray array];
    return item;
}

+ (instancetype)repoItemWithTitle:(NSString *)title representedObject:(nullable id)obj {
    SRSidebarItem *item = [[SRSidebarItem alloc] init];
    item.type = SRSidebarItemTypeRepo;
    item.title = title;
    item.representedObject = obj;
    item.expandable = NO;
    item.children = [NSMutableArray array];
    return item;
}

+ (instancetype)peerItemWithTitle:(NSString *)title representedObject:(nullable id)obj {
    SRSidebarItem *item = [[SRSidebarItem alloc] init];
    item.type = SRSidebarItemTypePeer;
    item.title = title;
    item.representedObject = obj;
    item.expandable = NO;
    item.children = [NSMutableArray array];
    return item;
}

@end
