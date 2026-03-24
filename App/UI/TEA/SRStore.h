#import <Foundation/Foundation.h>
#import "SRAppModel.h"
#import "SRMsg.h"
#import "SRUpdate.h"

NS_ASSUME_NONNULL_BEGIN

@interface SRStore : NSObject

@property (nonatomic, readonly) SRAppModel *state;

- (instancetype)init;

// Dispatch message to trigger state transition
- (void)dispatch:(SRMsg *)msg;

// Subscribe to state changes (triggers on main queue)
- (void)subscribe:(void(^)(SRAppModel *model))callback;

// Start the store (initialize subscriptions, load initial data)
- (void)start;

// Stop the store (cleanup subscriptions)
- (void)stop;

@end

NS_ASSUME_NONNULL_END
