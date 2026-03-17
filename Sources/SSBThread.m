#import "SSBThread.h"
#import "SSBTangle.h"
#import "SSBMessageCodec.h"

@interface SSBThread ()
@property (nonatomic, strong) SSBMessage *root;
@property (nonatomic, copy) NSArray<SSBMessage *> *messages;
@end

@implementation SSBThread

- (instancetype)initWithRoot:(SSBMessage *)root messages:(NSArray<SSBMessage *> *)messages {
    self = [super init];
    if (self) {
        _root = root;
        _messages = [messages copy];
    }
    return self;
}

- (NSArray<SSBMessage *> *)linearize {
    return [self linearizeFilteredByBlockedAuthors:[NSSet set]];
}

- (NSArray<SSBMessage *> *)linearizeFilteredByBlockedAuthors:(NSSet<NSString *> *)blockedAuthors {
    if (!self.root) return @[];
    
    NSMutableArray<SSBMessage *> *validMessages = [NSMutableArray array];
    if (![blockedAuthors containsObject:self.root.author]) {
        [validMessages addObject:self.root];
    }
    
    for (SSBMessage *msg in self.messages) {
        if (![msg.key isEqualToString:self.root.key] && ![blockedAuthors containsObject:msg.author]) {
            [validMessages addObject:msg];
        }
    }
    
    NSMutableDictionary<NSString *, SSBTangleData *> *tangleDataMap = [NSMutableDictionary dictionary];
    for (SSBMessage *msg in validMessages) {
        SSBTangleData *data = [SSBTangle parseTangleData:self.root.key fromContent:msg.content];
        
        if (!data && msg.content) {
            NSString *rootKey = msg.content[@"root"];
            id branchObj = msg.content[@"branch"];
            
            if (rootKey && [rootKey isEqualToString:self.root.key]) {
                NSArray<NSString *> *branches = nil;
                if ([branchObj isKindOfClass:[NSString class]]) {
                    branches = @[branchObj];
                } else if ([branchObj isKindOfClass:[NSArray class]]) {
                    branches = branchObj;
                }
                data = [SSBTangle tangleDataWithRoot:rootKey previous:branches];
            }
        }
        
        if (data) {
            tangleDataMap[msg.key] = data;
        } else if ([msg.key isEqualToString:self.root.key]) {
            // Root message has no previous
            tangleDataMap[msg.key] = [SSBTangle tangleDataWithRoot:nil previous:nil];
        }
    }
    
    NSArray<SSBMessage *> *sorted = [SSBTangle topologicalSort:validMessages tangleName:self.root.key tangleDataMap:tangleDataMap];
    
    return sorted;
}

@end