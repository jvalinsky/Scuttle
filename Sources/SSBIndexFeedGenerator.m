#import "SSBIndexFeedGenerator.h"
#import "SSBIndexFeed.h"

@interface SSBIndexFeedGenerator ()
@property (nonatomic, strong) SSBFeedStore *feedStore;
@end

@implementation SSBIndexFeedGenerator

- (instancetype)initWithFeedStore:(SSBFeedStore *)feedStore {
    self = [super init];
    if (self) {
        _feedStore = feedStore;
    }
    return self;
}

- (NSArray<NSDictionary<NSString *, id> *> *)generateIndexForContentType:(NSString *)contentType
                                                                   limit:(NSInteger)limit {
    NSArray<SSBMessage *> *messages = [self.feedStore messagesOfType:contentType limit:limit];
    NSMutableArray *indexMessages = [NSMutableArray arrayWithCapacity:messages.count];
    
    for (SSBMessage *msg in messages) {
        NSDictionary *indexContent = [SSBIndexFeed createIndexMessageWithKey:msg.key
                                                                    sequence:msg.sequence];
        if (indexContent) {
            [indexMessages addObject:indexContent];
        }
    }
    
    return [indexMessages copy];
}

- (NSArray<NSDictionary<NSString *, id> *> *)generateIndexForAuthor:(NSString *)author
                                                              limit:(NSInteger)limit {
    NSArray<SSBMessage *> *messages = [self.feedStore feedForAuthor:author limit:limit];
    NSMutableArray *indexMessages = [NSMutableArray arrayWithCapacity:messages.count];
    
    for (SSBMessage *msg in messages) {
        NSDictionary *indexContent = [SSBIndexFeed createIndexMessageWithKey:msg.key
                                                                    sequence:msg.sequence];
        if (indexContent) {
            [indexMessages addObject:indexContent];
        }
    }
    
    return [indexMessages copy];
}

@end