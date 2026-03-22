#import <Foundation/Foundation.h>
#import "SRModel.h"
#import "SRMsg.h"
#import "SRUpdate.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRStore : NSObject

@property (nonatomic, readonly) SRModel *state;

- (instancetype)initWithInitialModel:(SRModel *)model;

// Dispatch message to trigger state transition
- (void)dispatch:(SRMsg *)msg;

// Subscribe to state changes (triggers on main queue)
- (void)subscribe:(void(^)(SRModel *model))callback;

@end

NS_ASSUME_NONNULL_END
