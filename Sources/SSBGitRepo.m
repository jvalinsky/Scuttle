#import "SSBGitRepo.h"
#import "SSBQueryEngine.h"
#import "SSBRoomClient.h"
#import "SSBBlobStore.h"

@implementation SSBGitRepo

- (instancetype)initWithRepoID:(NSString *)repoID feedStore:(SSBFeedStore *)feedStore objectStore:(SSBGitObjectStore *)objectStore {
    if (self = [super init]) {
        _repoID = [repoID copy];
        _feedStore = feedStore;
        _objectStore = objectStore;
    }
    return self;
}

+ (void)publishRepoWithName:(NSString *)name client:(SSBRoomClient *)client completion:(SSBGitRepoCompletion)completion {
    NSDictionary *content = @{
        @"type": @"git-repo",
        @"name": name
    };
    [client publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        if (error) {
            completion(nil, error);
        } else {
            completion(msg.key, nil);
        }
    }];
}

- (void)publishUpdateWithRefs:(NSDictionary<NSString *, id> *)refs
                        packs:(NSArray<NSString *> *)packBlobIDs
                      indexes:(NSArray<NSString *> *)idxBlobIDs
                       client:(SSBRoomClient *)client
                   completion:(SSBGitRepoCompletion)completion {
    
    NSMutableArray *packs = [NSMutableArray array];
    for (NSString *blobID in packBlobIDs) {
        [packs addObject:@{@"link": blobID}];
    }
    
    NSMutableArray *indexes = [NSMutableArray array];
    for (NSString *blobID in idxBlobIDs) {
        [indexes addObject:@{@"link": blobID}];
    }
    
    NSDictionary *content = @{
        @"type": @"git-update",
        @"repo": self.repoID,
        @"refs": refs,
        @"packs": packs,
        @"indexes": indexes
    };
    
    [client publishLocalMessageWithContent:content completion:^(NSError *error, SSBMessage *msg) {
        if (error) {
            completion(nil, error);
        } else {
            completion(msg.key, nil);
        }
    }];
}

+ (void)uploadBlobAtURL:(NSURL *)url completion:(void(^)(NSString * _Nullable blobID, NSError * _Nullable error))completion {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    if (!data) {
        completion(nil, error);
        return;
    }
    
    NSString *blobID = [[SSBBlobStore sharedStore] addBlobWithData:data];
    if (blobID) {
        completion(blobID, nil);
    } else {
        completion(nil, [NSError errorWithDomain:@"SSBGitRepoError" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store blob"}]);
    }
}

- (NSArray<SSBMessage *> *)updateMessages {
    NSDictionary *query = @{
        @"AND": @[
            @{ @"EQUAL": @[ @[@"value", @"content", @"type"], @"git-update" ] },
            @{ @"EQUAL": @[ @[@"value", @"content", @"repo"], self.repoID ] }
        ]
    };
    
    NSDictionary *options = @{
        @"descending": @YES
    };
    
    return [self.feedStore querySubset:query options:options];
}

- (NSDictionary<NSString *, NSString *> *)currentRefs {
    NSArray<SSBMessage *> *updates = [self updateMessages];
    NSMutableDictionary<NSString *, NSString *> *refs = [NSMutableDictionary dictionary];
    
    // Updates are returned in reverse chronological order (newest first).
    // The first time we see a ref, it represents its current state.
    // If we see it as NSNull or null string, it means it was deleted.
    
    for (SSBMessage *msg in updates) {
        NSDictionary *content = msg.content;
        NSDictionary *msgRefs = content[@"refs"];
        
        if ([msgRefs isKindOfClass:[NSDictionary class]]) {
            for (NSString *refName in msgRefs) {
                if (refs[refName] == nil) { // Only set if not already set by a newer message
                    id refValue = msgRefs[refName];
                    if ([refValue isKindOfClass:[NSString class]]) {
                        refs[refName] = refValue;
                    } else if ([refValue isKindOfClass:[NSNull class]]) {
                        // Mark as deleted so older messages don't resurrect it
                        refs[refName] = @"";
                    }
                }
            }
        }
        
        // Also register packs and indexes to the object store
        NSArray *packs = content[@"packs"];
        NSArray *indexes = content[@"indexes"];
        
        if ([packs isKindOfClass:[NSArray class]] && [indexes isKindOfClass:[NSArray class]]) {
            for (NSUInteger i = 0; i < packs.count && i < indexes.count; i++) {
                NSDictionary *packDict = packs[i];
                NSDictionary *idxDict = indexes[i];
                
                if ([packDict isKindOfClass:[NSDictionary class]] && [idxDict isKindOfClass:[NSDictionary class]]) {
                    NSString *packLink = packDict[@"link"];
                    NSString *idxLink = idxDict[@"link"];
                    
                    if (packLink && idxLink) {
                        [self.objectStore registerPackBlob:packLink idxBlob:idxLink];
                    }
                }
            }
        }
    }
    
    // Remove the tombstoned ones
    NSMutableDictionary *finalRefs = [NSMutableDictionary dictionary];
    for (NSString *key in refs) {
        if (refs[key].length > 0) {
            finalRefs[key] = refs[key];
        }
    }
    
    return finalRefs;
}

@end
