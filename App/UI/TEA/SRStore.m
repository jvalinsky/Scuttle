#import "SRStore.h"
#import "../../../Sources/SSBFeedStore.h"
#import "../../Logic/SRRoomManager.h"

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
    if ([cmd.type isEqualToString:@"FetchGitRepos"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *repos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
            [self dispatch:[SRMsg gitReposLoaded:repos]];
        });
    } else if ([cmd.type isEqualToString:@"FetchRooms"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *rooms = [[SRRoomManager sharedManager] rooms];
            [self dispatch:[SRMsg roomsLoaded:rooms]];
        });
    }
}

@end
