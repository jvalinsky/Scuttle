#import <Foundation/Foundation.h>
#import "SRModel.h"
#import "SRMsg.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRCmd : NSObject
@property (nonatomic, readonly) NSString *type;
+ (instancetype)cmdWithType:(NSString *)type;
@end

@interface SRUpdateResult : NSObject
@property (nonatomic, readonly) SRModel *model;
@property (nonatomic, readonly) NSArray<SRCmd *> *commands;

- (instancetype)initWithModel:(SRModel *)model commands:(NSArray<SRCmd *> *)commands;
@end

@interface SRUpdate : NSObject

+ (SRUpdateResult *)updateWithModel:(SRModel *)model msg:(SRMsg *)msg;

@end

NS_ASSUME_NONNULL_END
