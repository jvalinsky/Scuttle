#import "SRStore.h"

@interface SRStore ()
@property (nonatomic, strong) SRModel *state;
@property (nonatomic, strong) NSMutableArray<void(^)(SRModel *)> *subscribers;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SRStore

- (instancetype)initWithInitialModel:(SRModel *)model {
    if (self = [super init]) {
        _state = model;
        _subscribers = [NSMutableArray array];
        _queue = dispatch_queue_create("com.scuttle.store", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)subscribe:(void(^)(SRModel *))callback {
    dispatch_async(self.queue, ^{
        [self.subscribers addObject:[callback copy]];
        // Immediately notify with current state
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(self.state);
        });
    });
}

- (void)dispatch:(SRMsg *)msg {
    dispatch_async(self.queue, ^{
        SRUpdateResult *result = [SRUpdate updateWithModel:self.state msg:msg];
        self.state = result.model;

        // Execute commands (Cmd)
        for (SRCmd *cmd in result.commands) {
            [self _executeCommand:cmd];
        }

        // Notify subscribers on main queue
        NSArray *subs = [self.subscribers copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void(^sub)(SRModel *) in subs) {
                sub(self.state);
            }
        });
    });
}

- (void)_executeCommand:(SRCmd *)cmd {
    // To be implemented as side effects grow.
    // E.g., network fetches, DB queries.
}

@end
