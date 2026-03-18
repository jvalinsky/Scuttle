# Mutable Collection Thread Safety

## The Problem

NSMutableArray, NSMutableDictionary, and NSMutableSet are not thread-safe. Concurrent reads and writes cause crashes, corruption, or data loss.

## Solution Patterns

### Pattern 1: Serial Queue (Recommended)

Use a serial dispatch queue to serialize all access:

```objc
@property (nonatomic, strong) dispatch_queue_t dataQueue;
@property (nonatomic, strong) NSMutableDictionary *cache;

- (instancetype)init {
    self = [super init];
    if (self) {
        _dataQueue = dispatch_queue_create("com.app.dataqueue", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
    }
    return self;
}

// Read
- (id)objectForKey:(NSString *)key {
    __block id result;
    dispatch_sync(self.dataQueue, ^{
        result = self.cache[key];
    });
    return result;
}

// Write
- (void)setObject:(id)obj forKey:(NSString *)key {
    dispatch_async(self.dataQueue, ^{
        self.cache[key] = obj;
    });
}
```

### Pattern 2: Copy on Read (Safe for Read-Heavy)

If reads vastly outnumber writes and you can tolerate slight staleness:

```objc
@property (nonatomic, strong) dispatch_queue_t dataQueue;
@property (nonatomic, strong) NSDictionary *cache;  // Note: immutable!

- (void)updateCache:(NSDictionary *)newData {
    dispatch_async(self.dataQueue, ^{
        self.cache = [newData copy];  // Replace entirely
    });
}

- (NSDictionary *)cache {
    // Reading immutable NSDictionary is thread-safe
    return _cache;
}
```

### Pattern 3: @synchronized (Simple Cases)

Good for short critical sections:

```objc
@property (nonatomic, strong) NSMutableArray *items;

- (void)addItem:(id)item {
    @synchronized(self.items) {
        [self.items addObject:item];
    }
}

- (NSArray *)allItems {
    @synchronized(self.items) {
        return [self.items copy];
    }
}
```

## Scuttle Examples

### Good: SSBFeedStore

```objc
// Sources/SSBFeedStore.m lines 17, 61
@property (nonatomic, strong) dispatch_queue_t dbQueue;
_dbQueue = dispatch_queue_create("com.scuttlebutt.feedstore.db", DISPATCH_QUEUE_SERIAL);

// All database access properly serialized
- (nullable SSBMessage *)messageWithHash:(NSData *)hash {
    __block SSBMessage *msg = nil;
    dispatch_sync(self.dbQueue, ^{
        msg = [self _messageWithHash:hash];
    });
    return msg;
}
```

### Good: SSBHTTPAuth

```objc
// Sources/SSBHTTPAuth.m lines 108, 145
@property (nonatomic, strong) dispatch_queue_t authQueue;
_authQueue = dispatch_queue_create("com.ssb.httpauth", DISPATCH_QUEUE_SERIAL);

// Properly synchronized
- (nullable SSBHTTPAuthToken *)tokenForTokenString:(NSString *)tokenString {
    __block SSBHTTPAuthToken *token = nil;
    dispatch_sync(self.authQueue, ^{
        token = self.tokensByString[tokenString];
    });
    return token;
}
```

### Bad: SSBGitObjectStore

```objc
// Sources/SSBGitObjectStore.m line 8
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *packs;

// NO SYNCHRONIZATION - race condition!
- (void)registerPackBlob:(NSString *)packBlobID idxBlob:(NSString *)idxBlobID {
    for (NSDictionary *dict in self.packs) {  // Unsafe iteration
        if ([dict[@"pack"] isEqualToString:packBlobID]) {
            return;
        }
    }
    [self.packs addObject:@{  // Unsafe mutation
        @"pack": packBlobID,
        @"idx": idxBlobID
    }];
}
```

## Checklist for Adding Synchronization

- [ ] Identify all mutable properties
- [ ] Trace all read locations (main thread, background threads, callbacks)
- [ ] Trace all write locations
- [ ] Choose synchronization strategy
- [ ] Apply consistently - all reads AND all writes must use it
- [ ] Test with Thread Sanitizer: `-fsanitize=thread`
