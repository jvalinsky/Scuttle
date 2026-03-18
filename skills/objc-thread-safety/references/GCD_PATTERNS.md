# GCD Patterns for Thread Safety

## Queue Types

### Serial Queue
- Executes one task at a time, in order
- Use for: protecting mutable state, sequential operations
```objc
dispatch_queue_t queue = dispatch_queue_create("com.app.serial", DISPATCH_QUEUE_SERIAL);
```

### Concurrent Queue
- Executes multiple tasks simultaneously
- Use for: parallel independent operations
```objc
dispatch_queue_t queue = dispatch_queue_create("com.app.concurrent", DISPATCH_QUEUE_CONCURRENT);
```

### Main Queue
- The UI queue, serial by nature
- Use for: all UI updates
```objc
dispatch_async(dispatch_get_main_queue(), ^{
    self.label.text = @"Updated";
});
```

## Common Patterns

### Pattern 1: Serial Queue for State Protection

```objc
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary *state;

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.app.state", DISPATCH_QUEUE_SERIAL);
        _state = [NSMutableDictionary dictionary];
    }
    return self;
}

// Write
- (void)updateState:(id)value forKey:(NSString *)key {
    dispatch_async(self.stateQueue, ^{
        self.state[key] = value;
    });
}

// Read  
- (id)stateForKey:(NSString *)key {
    __block id result;
    dispatch_sync(self.stateQueue, ^{
        result = self.state[key];
    });
    return result;
}
```

### Pattern 2: Barrier for Read-Write Dictionary

Using concurrent queue with barrier for writes:

```objc
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableDictionary *cache;

- (instancetype)init {
    _queue = dispatch_queue_create("com.app.cache", DISPATCH_QUEUE_CONCURRENT);
    _cache = [NSMutableDictionary dictionary];
}

// Read - concurrent allowed
- (id)objectForKey:(NSString *)key {
    __block id result;
    dispatch_sync(self.queue, ^{
        result = self.cache[key];
    });
    return result;
}

// Write - barrier blocks all access
- (void)setObject:(id)obj forKey:(NSString *)key {
    dispatch_barrier_async(self.queue, ^{
        self.cache[key] = obj;
    });
}
```

### Pattern 3: dispatch_sync vs dispatch_async

**dispatch_async** - Fire and forget, returns immediately:
```objc
// Returns immediately, work happens in background
dispatch_async(self.queue, ^{
    [self doHeavyWork];
});
// Code here runs before work completes!
```

**dispatch_sync** - Waits for completion:
```objc
// Blocks until work completes, result available immediately
__block id result;
dispatch_sync(self.queue, ^{
    result = [self computeValue];
});
// result is valid here
```

### Pattern 4: Waiting on Multiple Queues

```objc
dispatch_group_t group = dispatch_group_create();

dispatch_group_enter(group);
dispatch_async(self.queue1, ^{
    // Work 1
    dispatch_group_leave(group);
});

dispatch_group_enter(group);
dispatch_async(self.queue2, ^{
    // Work 2  
    dispatch_group_leave(group);
});

dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    // All work complete, update UI
});
```

### Pattern 5: Capturing Self Safely in Blocks

```objc
// Always use weak self in GCD blocks
__weak typeof(self) weakSelf = self;
dispatch_async(self.queue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    [strongSelf doWork];
});
```

## Scuttle Patterns

### Good: SSBMuxRPCSession

```objc
// Sources/SSBMuxRPCSession.m lines 10-11
@property (nonatomic, assign) _Atomic int32_t nextRequestID;
@property (nonatomic, strong) dispatch_queue_t accessQueue;

// Atomic for counter
int32_t reqNum = atomic_fetch_add_explicit(&_nextRequestID, 1, memory_order_relaxed);

// Queue for dictionary access
dispatch_sync(self.accessQueue, ^{
    self.pendingRequests[@(reqNum)] = handler;
});
```

### Good: SSBBlobStore (Partial)

```objc
// Sources/SSBBlobStore.m line 36
@property (nonatomic, strong) dispatch_queue_t ioQueue;
_ioQueue = dispatch_queue_create("com.scuttlebutt.blobstore", DISPATCH_QUEUE_SERIAL);

// Only used for wipeBlobs - most operations lack protection
- (void)wipeBlobs {
    dispatch_sync(self.ioQueue, ^{
        // ...
    });
}
```

## Thread Sanitizer

Enable to catch race conditions at runtime:

```
Xcode -> Edit Scheme -> Run -> Enable Thread Sanitizer = Yes
```

Or via build setting:
```
Other Warning Flags: -fsanitize=thread
```
