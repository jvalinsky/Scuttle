#import "SSBTangle.h"
#import "SSBMessageCodec.h"
#import "SSBFeedStore.h"
#import <os/log.h>

static os_log_t tangleLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.scuttlebutt.tangle", "Tangle");
    });
    return log;
}

@implementation SSBTangleData

- (instancetype)initWithRoot:(nullable NSString *)root
                    previous:(nullable NSArray<NSString *> *)previous {
    self = [super init];
    if (self) {
        _root = [root copy];
        _previous = [previous copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SSBTangleData: root=%@, previous=%@>",
            self.root, self.previous];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SSBTangleData class]]) return NO;
    SSBTangleData *other = (SSBTangleData *)object;
    
    BOOL rootsEqual = (self.root == nil && other.root == nil) ||
                      [self.root isEqualToString:other.root];
    BOOL previousEqual = (self.previous == nil && other.previous == nil) ||
                         [self.previous isEqualToArray:other.previous];
    return rootsEqual && previousEqual;
}

- (NSUInteger)hash {
    return self.root.hash ^ self.previous.hash;
}

@end

@implementation SSBTangle

#pragma mark - Creation & Parsing

+ (nullable SSBTangleData *)tangleDataWithRoot:(nullable NSString *)root
                                       previous:(nullable NSArray<NSString *> *)previous {
    if (!root && !previous) {
        os_log(tangleLog(), "Creating tangle data with null root and null previous");
    }
    
    NSArray<NSString *> *filteredPrevious = nil;
    if (previous) {
        filteredPrevious = [self filterValidMessageIds:previous allMessages:@{}];
        if (filteredPrevious.count == 0) {
            filteredPrevious = nil;
        }
    }
    
    return [[SSBTangleData alloc] initWithRoot:root previous:filteredPrevious];
}

+ (nullable SSBTangleData *)parseTangleData:(NSString *)tangleName
                                 fromContent:(NSDictionary *)content {
    if (!content || ![content isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NSDictionary *tangles = content[@"tangles"];
    if (!tangles || ![tangles isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NSDictionary *tangleData = tangles[tangleName];
    if (!tangleData || ![tangleData isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    id rootValue = tangleData[@"root"];
    NSString *root = nil;
    if (rootValue && ![rootValue isEqual:[NSNull null]]) {
        if ([rootValue isKindOfClass:[NSString class]]) {
            root = [self extractMessageIdFromKey:rootValue];
            if (!root) {
                root = rootValue;
            }
        }
    }
    
    NSArray<NSString *> *previous = nil;
    id previousValue = tangleData[@"previous"];
    if (previousValue && ![previousValue isEqual:[NSNull null]]) {
        if ([previousValue isKindOfClass:[NSArray class]]) {
            NSMutableArray<NSString *> *filtered = [NSMutableArray array];
            for (id item in previousValue) {
                if ([item isKindOfClass:[NSString class]]) {
                    NSString *msgId = [self extractMessageIdFromKey:item];
                    if (msgId) {
                        [filtered addObject:msgId];
                    } else {
                        [filtered addObject:item];
                    }
                }
            }
            if (filtered.count > 0) {
                previous = [filtered copy];
            }
        }
    }
    
    return [[SSBTangleData alloc] initWithRoot:root previous:previous];
}

#pragma mark - Validation

+ (BOOL)validateMessage:(SSBMessage *)message
                inTangle:(NSString *)tangleName
             allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages {
    
    NSDictionary *content = message.content;
    if (!content) {
        os_log(tangleLog(), "Message %@ has no content", message.key);
        return NO;
    }
    
    NSDictionary *tangles = content[@"tangles"];
    if (!tangles || ![tangles isKindOfClass:[NSDictionary class]]) {
        os_log(tangleLog(), "Message %@ has no tangles in content", message.key);
        return NO;
    }
    
    NSDictionary *tangleData = tangles[tangleName];
    if (!tangleData) {
        os_log(tangleLog(), "Message %@ has no tangle data for '%@'", message.key, tangleName);
        return NO;
    }
    
    if (![tangleData isKindOfClass:[NSDictionary class]]) {
        os_log(tangleLog(), "Tangle data for '%@' in message %@ is not a dict", tangleName, message.key);
        return NO;
    }
    
    id rootValue = tangleData[@"root"];
    id previousValue = tangleData[@"previous"];
    
    BOOL isRoot = [rootValue isEqual:[NSNull null]] || rootValue == nil;
    
    if (isRoot) {
        if (previousValue && ![previousValue isEqual:[NSNull null]]) {
            os_log(tangleLog(), "Root message %@ has non-null previous", message.key);
            return NO;
        }
    } else {
        if (!previousValue || [previousValue isEqual:[NSNull null]]) {
            os_log(tangleLog(), "Non-root message %@ has null previous", message.key);
            return NO;
        }
        
        if ([previousValue isKindOfClass:[NSArray class]]) {
            NSArray *previousArray = (NSArray *)previousValue;
            for (id prevId in previousArray) {
                if (![prevId isKindOfClass:[NSString class]]) {
                    os_log(tangleLog(), "Invalid previous entry in message %@", message.key);
                    return NO;
                }
                
                NSString *prevMsgId = [self extractMessageIdFromKey:prevId] ?: prevId;
                if (!allMessages[prevMsgId]) {
                    os_log(tangleLog(), "Previous message %@ not found for %@", prevMsgId, message.key);
                }
            }
        }
    }
    
    return YES;
}

+ (BOOL)validateClassicFeedMessage:(SSBMessage *)message
                        allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages {
    if (message.sequence == 1) {
        if (message.previousKey != nil) {
            os_log(tangleLog(), "Sequence 1 message %@ has previous key", message.key);
            return NO;
        }
    } else {
        if (!message.previousKey) {
            os_log(tangleLog(), "Non-sequence-1 message %@ missing previous key", message.key);
            return NO;
        }
        
        SSBMessage *prevMsg = allMessages[message.previousKey];
        if (!prevMsg) {
            os_log(tangleLog(), "Previous message %@ not found for %@", message.previousKey, message.key);
            return NO;
        }
        
        if (![prevMsg.author isEqualToString:message.author]) {
            os_log(tangleLog(), "Author mismatch: %@ vs %@", prevMsg.author, message.author);
            return NO;
        }
        
        if (prevMsg.sequence != message.sequence - 1) {
            os_log(tangleLog(), "Sequence gap: expected %ld, got %ld",
                   (long)(message.sequence - 1), (long)prevMsg.sequence);
            return NO;
        }
    }
    
    return YES;
}

#pragma mark - Graph Operations

+ (NSArray<SSBMessage *> *)topologicalSort:(NSArray<SSBMessage *> *)messages
                                  tangleName:(NSString *)tangleName
                                tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (messages.count == 0) {
        return @[];
    }
    
    NSMutableDictionary<NSString *, SSBMessage *> *msgMap = [NSMutableDictionary dictionary];
    for (SSBMessage *msg in messages) {
        if (msg.key) {
            msgMap[msg.key] = msg;
        }
    }
    
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *edges = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *inDegree = [NSMutableDictionary dictionary];
    
    for (SSBMessage *msg in messages) {
        NSString *msgKey = msg.key;
        inDegree[msgKey] = @0;
        
        SSBTangleData *tangleData = tangleDataMap[msgKey];
        
        if (tangleData && tangleData.previous) {
            for (NSString *prevId in tangleData.previous) {
                NSString *resolvedPrevId = [self extractMessageIdFromKey:prevId] ?: prevId;
                
                if (msgMap[resolvedPrevId]) {
                    if (!edges[resolvedPrevId]) {
                        edges[resolvedPrevId] = [NSMutableSet set];
                    }
                    [edges[resolvedPrevId] addObject:msgKey];
                    
                    NSInteger currentInDegree = [inDegree[msgKey] integerValue];
                    inDegree[msgKey] = @(currentInDegree + 1);
                }
            }
        }
    }
    
    NSMutableArray<SSBMessage *> *sorted = [NSMutableArray array];
    NSMutableArray<NSString *> *queue = [NSMutableArray array];
    
    for (NSString *msgKey in inDegree) {
        if ([inDegree[msgKey] integerValue] == 0) {
            [queue addObject:msgKey];
        }
    }
    
    [queue sortUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
        SSBMessage *m1 = msgMap[key1];
        SSBMessage *m2 = msgMap[key2];
        if (!m1 || !m2) return NSOrderedSame;
        if (m1.claimedTimestamp < m2.claimedTimestamp) return NSOrderedAscending;
        if (m1.claimedTimestamp > m2.claimedTimestamp) return NSOrderedDescending;
        return [m1.key compare:m2.key];
    }];
    
    while (queue.count > 0) {
        NSString *currentKey = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        SSBMessage *currentMsg = msgMap[currentKey];
        if (currentMsg) {
            [sorted addObject:currentMsg];
        }
        
        NSSet<NSString *> *outgoing = edges[currentKey];
        for (NSString *nextKey in outgoing) {
            NSInteger newDegree = [inDegree[nextKey] integerValue] - 1;
            inDegree[nextKey] = @(newDegree);
            
            if (newDegree == 0) {
                [queue addObject:nextKey];
                
                [queue sortUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
                    SSBMessage *m1 = msgMap[key1];
                    SSBMessage *m2 = msgMap[key2];
                    if (!m1 || !m2) return NSOrderedSame;
                    if (m1.claimedTimestamp < m2.claimedTimestamp) return NSOrderedAscending;
                    if (m1.claimedTimestamp > m2.claimedTimestamp) return NSOrderedDescending;
                    return [m1.key compare:m2.key];
                }];
            }
        }
    }
    
    if (sorted.count != messages.count) {
        os_log(tangleLog(), "Topological sort incomplete: %lu vs %lu",
               (unsigned long)sorted.count, (unsigned long)messages.count);
    }
    
    return [sorted copy];
}

+ (NSArray<NSArray<NSString *> *> *)detectForksInTangle:(NSString *)tangleName
                                               messages:(NSArray<SSBMessage *> *)messages
                                          tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    NSMutableArray<NSArray<NSString *> *> *forks = [NSMutableArray array];
    
    if (messages.count == 0) {
        return forks;
    }
    
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *children = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *parents = [NSMutableDictionary dictionary];
    
    for (SSBMessage *msg in messages) {
        NSString *msgKey = msg.key;
        children[msgKey] = [NSMutableSet set];
        parents[msgKey] = [NSMutableSet set];
    }
    
    for (SSBMessage *msg in messages) {
        NSString *msgKey = msg.key;
        SSBTangleData *tangleData = tangleDataMap[msgKey];
        
        if (tangleData && tangleData.previous) {
            for (NSString *prevId in tangleData.previous) {
                NSString *resolvedPrevId = [self extractMessageIdFromKey:prevId] ?: prevId;
                
                if (parents[msgKey] && children[resolvedPrevId]) {
                    [parents[msgKey] addObject:resolvedPrevId];
                    [children[resolvedPrevId] addObject:msgKey];
                }
            }
        }
    }
    
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    
    for (SSBMessage *msg in messages) {
        NSString *msgKey = msg.key;
        if ([visited containsObject:msgKey]) continue;
        
        NSMutableArray<NSString *> *forkBranch = [NSMutableArray array];
        NSMutableSet<NSString *> *toVisit = [NSMutableSet setWithObject:msgKey];
        
        while (toVisit.count > 0) {
            NSString *current = toVisit.anyObject;
            [toVisit removeObject:current];
            
            if ([visited containsObject:current]) continue;
            [visited addObject:current];
            
            [forkBranch addObject:current];
            
            NSSet<NSString *> *currentChildren = children[current];
            if (currentChildren.count > 1) {
                for (NSString *child in currentChildren) {
                    if (![visited containsObject:child]) {
                        [toVisit addObject:child];
                    }
                }
            } else if (currentChildren.count == 1) {
                NSString *singleChild = currentChildren.anyObject;
                if (![visited containsObject:singleChild]) {
                    [toVisit addObject:singleChild];
                }
            }
        }
        
        if (forkBranch.count > 1) {
            [forks addObject:forkBranch];
        }
    }
    
    return forks;
}

+ (NSArray<NSString *> *)findTipsInTangle:(NSString *)tangleName
                                  messages:(NSArray<SSBMessage *> *)messages
                             tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (messages.count == 0) {
        return @[];
    }
    
    NSMutableSet<NSString *> *hasParent = [NSMutableSet set];
    NSMutableSet<NSString *> *allKeys = [NSMutableSet set];
    
    for (SSBMessage *msg in messages) {
        if (msg.key) {
            [allKeys addObject:msg.key];
        }
        
        SSBTangleData *tangleData = tangleDataMap[msg.key];
        if (tangleData && tangleData.previous) {
            for (NSString *prevId in tangleData.previous) {
                NSString *resolvedPrevId = [self extractMessageIdFromKey:prevId] ?: prevId;
                if ([allKeys containsObject:resolvedPrevId]) {
                    [hasParent addObject:resolvedPrevId];
                }
            }
        }
    }
    
    NSMutableArray<NSString *> *tips = [NSMutableArray array];
    for (NSString *key in allKeys) {
        if (![hasParent containsObject:key]) {
            [tips addObject:key];
        }
    }
    
    return [tips copy];
}

+ (BOOL)isMessage:(NSString *)messageId
      connectedTo:(NSString *)targetId
          inTangle:(NSString *)tangleName
          messages:(NSArray<SSBMessage *> *)messages
     tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (!messageId || !targetId) {
        return NO;
    }
    
    if ([messageId isEqualToString:targetId]) {
        return YES;
    }
    
    NSMutableDictionary<NSString *, SSBMessage *> *msgMap = [NSMutableDictionary dictionary];
    for (SSBMessage *msg in messages) {
        if (msg.key) {
            msgMap[msg.key] = msg;
        }
    }
    
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    NSMutableArray<NSString *> *queue = [NSMutableArray arrayWithObject:messageId];
    
    while (queue.count > 0) {
        NSString *current = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        if ([visited containsObject:current]) {
            continue;
        }
        [visited addObject:current];
        
        SSBMessage *currentMsg = msgMap[current];
        if (!currentMsg) continue;
        
        SSBTangleData *tangleData = tangleDataMap[current];
        if (tangleData && tangleData.previous) {
            for (NSString *prevId in tangleData.previous) {
                NSString *resolvedPrevId = [self extractMessageIdFromKey:prevId] ?: prevId;
                
                if ([resolvedPrevId isEqualToString:targetId]) {
                    return YES;
                }
                
                if (![visited containsObject:resolvedPrevId]) {
                    [queue addObject:resolvedPrevId];
                }
            }
        }
    }
    
    return NO;
}

#pragma mark - Classic Feed (Single Author)

+ (SSBTangleType)tangleTypeForMessages:(NSArray<SSBMessage *> *)messages
                              tangleName:(NSString *)tangleName
                            tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (messages.count == 0) {
        return SSBTangleTypeMultiAuthor;
    }
    
    NSString *firstAuthor = nil;
    for (SSBMessage *msg in messages) {
        if (!firstAuthor) {
            firstAuthor = msg.author;
        } else if (![msg.author isEqualToString:firstAuthor]) {
            return SSBTangleTypeMultiAuthor;
        }
    }
    
    BOOL hasTangleData = NO;
    for (SSBMessage *msg in messages) {
        SSBTangleData *data = tangleDataMap[msg.key];
        if (data) {
            hasTangleData = YES;
            break;
        }
    }
    
    if (!hasTangleData) {
        return SSBTangleTypeSingleAuthor;
    }
    
    return SSBTangleTypeSingleAuthor;
}

+ (nullable NSString *)findRootForTangle:(NSString *)tangleName
                                 messages:(NSArray<SSBMessage *> *)messages
                            tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (messages.count == 0) {
        return nil;
    }
    
    for (SSBMessage *msg in messages) {
        SSBTangleData *tangleData = tangleDataMap[msg.key];
        
        if (!tangleData) {
            continue;
        }
        
        if (!tangleData.root && (!tangleData.previous || tangleData.previous.count == 0)) {
            return msg.key;
        }
        
        if (tangleData.root == nil || [tangleData.root isEqual:[NSNull null]]) {
            return msg.key;
        }
    }
    
    SSBMessage *firstMsg = messages.firstObject;
    if (firstMsg) {
        NSDictionary *content = firstMsg.content;
        if (content) {
            NSDictionary *tangles = content[@"tangles"];
            if (tangles) {
                NSDictionary *tangleData = tangles[tangleName];
                if (tangleData && [tangleData[@"root"] isEqual:[NSNull null]]) {
                    return firstMsg.key;
                }
            }
        }
    }
    
    for (SSBMessage *msg in messages) {
        BOOL isRoot = YES;
        
        for (SSBMessage *otherMsg in messages) {
            if ([msg.key isEqualToString:otherMsg.key]) continue;
            
            SSBTangleData *otherData = tangleDataMap[otherMsg.key];
            if (otherData && otherData.previous) {
                for (NSString *prevId in otherData.previous) {
                    NSString *resolved = [self extractMessageIdFromKey:prevId] ?: prevId;
                    if ([resolved isEqualToString:msg.key]) {
                        isRoot = NO;
                        break;
                    }
                }
            }
            if (!isRoot) break;
        }
        
        if (isRoot) {
            return msg.key;
        }
    }
    
    return nil;
}

+ (nullable NSArray<NSString *> *)previousForNewMessageInTangle:(NSString *)tangleName
                                                        messages:(NSArray<SSBMessage *> *)messages
                                                   tangleDataMap:(NSDictionary<NSString *, SSBTangleData *> *)tangleDataMap {
    
    if (messages.count == 0) {
        return nil;
    }
    
    NSArray<NSString *> *tips = [self findTipsInTangle:tangleName
                                               messages:messages
                                          tangleDataMap:tangleDataMap];
    
    if (tips.count == 0) {
        return nil;
    }
    
    return tips;
}

#pragma mark - Helpers

+ (NSDictionary<NSString *, SSBTangleData *> *)tangleDataMapForMessages:(NSArray<SSBMessage *> *)messages {
    NSMutableDictionary<NSString *, SSBTangleData *> *map = [NSMutableDictionary dictionary];
    
    for (SSBMessage *msg in messages) {
        NSDictionary *content = msg.content;
        if (!content) continue;
        
        NSDictionary *tangles = content[@"tangles"];
        if (!tangles || ![tangles isKindOfClass:[NSDictionary class]]) continue;
        
        for (NSString *tangleName in tangles) {
            NSDictionary *tangleDataDict = tangles[tangleName];
            if (![tangleDataDict isKindOfClass:[NSDictionary class]]) continue;
            
            SSBTangleData *tangleData = [self parseTangleData:tangleName fromContent:content];
            if (tangleData && msg.key) {
                map[msg.key] = tangleData;
            }
        }
    }
    
    return [map copy];
}

+ (nullable NSString *)extractMessageIdFromKey:(NSString *)key {
    if (!key || key.length < 2) {
        return nil;
    }
    
    unichar firstChar = [key characterAtIndex:0];
    
    if (firstChar == '%') {
        return key;
    }
    
    if ([key hasPrefix:@"%"]) {
        return key;
    }
    
    if ([key containsString:@".sha256"]) {
        return [NSString stringWithFormat:@"%%%@", key];
    }
    
    return nil;
}

+ (NSArray<NSString *> *)filterValidMessageIds:(NSArray<NSString *> *)ids
                                    allMessages:(NSDictionary<NSString *, SSBMessage *> *)allMessages {
    if (!ids || ids.count == 0) {
        return @[];
    }
    
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    
    for (NSString *id in ids) {
        if (![id isKindOfClass:[NSString class]]) {
            continue;
        }
        
        NSString *msgId = [self extractMessageIdFromKey:id] ?: id;
        
        if ([SSBMessageCodec isValidMessageId:msgId]) {
            [valid addObject:msgId];
        }
    }
    
    return [valid copy];
}

@end
