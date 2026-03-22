#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SRSidebarItemType) {
    SRSidebarItemTypeSection,
    SRSidebarItemTypeRoom,
    SRSidebarItemTypeChannel,
    SRSidebarItemTypeRepo
};

NS_ASSUME_NONNULL_BEGIN

@interface SRSidebarItem : NSObject
@property (nonatomic) SRSidebarItemType type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) id representedObject;
@property (nonatomic, strong) NSMutableArray<SRSidebarItem *> *children;
@property (nonatomic) BOOL expandable;

+ (instancetype)sectionItemWithTitle:(NSString *)title;
+ (instancetype)roomItemWithTitle:(NSString *)title representedObject:(nullable id)obj;
+ (instancetype)channelItemWithTitle:(NSString *)title;
+ (instancetype)repoItemWithTitle:(NSString *)title representedObject:(nullable id)obj;
@end

NS_ASSUME_NONNULL_END
