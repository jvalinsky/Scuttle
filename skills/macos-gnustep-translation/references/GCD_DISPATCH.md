# GCD (libdispatch) on Linux

## Overview

**Grand Central Dispatch (GCD)** is available on Linux via **libdispatch**. The Scuttle codebase uses GCD extensively for async operations.

**Status:** ✅ Fully compatible - libdispatch works on Linux

## Package Requirements

### Ubuntu/Debian
```bash
apt install libdispatch-dev
```

### Fedora
```bash
dnf install libdispatch-devel
```

### macOS
- Built into the system as `libdispatch.dylib`

## Header

```objc
#import <dispatch/dispatch.h>
```

## Queues

### Main Queue

```objc
// Get main queue
dispatch_queue_t mainQueue = dispatch_get_main_queue();

// Execute on main queue
dispatch_async(dispatch_get_main_queue(), ^{
    // UI updates must happen here
});
```

### Global Queues

```objc
// Priority levels
dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
dispatch_queue_t highQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
dispatch_queue_t lowQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
```

### Custom Queues

```objc
// Serial queue - executes one at a time
dispatch_queue_t serialQueue = dispatch_queue_create("com.scuttle.serial", DISPATCH_QUEUE_SERIAL);

// Concurrent queue - executes multiple at a time
dispatch_queue_t concurrentQueue = dispatch_queue_create("com.scuttle.concurrent", DISPATCH_QUEUE_CONCURRENT);
```

## Execution

### dispatch_async

Fire and forget - returns immediately:

```objc
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // This runs in background
    NSLog(@"Background work");
});
// This runs immediately, before background work completes
NSLog(@"This runs first");
```

### dispatch_sync

Waits for completion:

```objc
__block NSString *result;
dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    result = @"Computed value";
});
// result is available here
NSLog(@"Result: %@", result);
```

### dispatch_after

Delayed execution:

```objc
// Execute after 2 seconds
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), 
              dispatch_get_main_queue(), ^{
    // This runs after 2 seconds
});
```

## Dispatch Groups

### Basic Pattern

```objc
dispatch_group_t group = dispatch_group_create();

dispatch_group_enter(group);
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // Work 1
    dispatch_group_leave(group);
});

dispatch_group_enter(group);
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // Work 2
    dispatch_group_leave(group);
});

// Runs when all work is complete
dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    NSLog(@"All work complete");
});
```

### Wait for Completion

```objc
dispatch_group_t group = dispatch_group_create();

dispatch_group_enter(group);
dispatch_async(queue, ^{
    // Work
    dispatch_group_leave(group);
});

// Block until complete
dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
// All work done here
```

## Semaphores

### Limiting Concurrency

```objc
// Allow only 4 concurrent operations
dispatch_semaphore_t semaphore = dispatch_semaphore_create(4);

for (int i = 0; i < 10; i++) {
    dispatch_async(queue, ^{
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        // Do work
        
        dispatch_semaphore_signal(semaphore);
    });
}
```

### Timeout Pattern

```objc
dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

// Wait with timeout (5 seconds)
long result = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

if (result == 0) {
    // Signal was received
} else {
    // Timeout occurred
}
```

## Dispatch Sources

### Timer Source

```objc
dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);

dispatch_source_set_event_handler(timer, ^{
    NSLog(@"Timer fired");
});

dispatch_resume(timer);

// Later: dispatch_suspend(timer) or dispatch_source_cancel(timer);
```

### Read Source (Socket)

```objc
int socket_fd = /* ... */;

dispatch_source_t readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socket_fd, 0, queue);

dispatch_source_set_event_handler(readSource, ^{
    char buffer[1024];
    ssize_t bytesRead = recv(socket_fd, buffer, sizeof(buffer), 0);
    if (bytesRead > 0) {
        // Handle data
    }
});

dispatch_resume(readSource);
```

### Signal Source

```objc
dispatch_source_t signalSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, queue);

dispatch_source_set_event_handler(signalSource, ^{
    NSLog(@"Received SIGINT");
    // Clean up and exit
});

dispatch_resume(signalSource);
```

## dispatch_once

Thread-safe one-time initialization:

```objc
static dispatch_once_t onceToken;
dispatch_once(&onceToken, ^{
    // This runs exactly once, thread-safe
    NSLog(@"Initialized");
});
```

## dispatch_data_t

### Creating

```objc
// From NSData
NSData *data = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);

// From buffer
dispatch_data_t bufferData = dispatch_data_create(buffer, bufferLength, queue, DISPATCH_DATA_DESTRUCTOR_MUNMAP);
```

### Converting Back to NSData

```objc
// Get size
size_t size = dispatch_data_get_size(dispatchData);

// Create NSData
NSMutableData *nsData = [NSMutableData dataWithLength:size];
dispatch_data_apply(dispatchData, ^(dispatch_data_t region, size_t offset, const void *buffer, size_t size, BOOL *stop) {
    [nsData appendBytes:buffer length:size];
    return true;
});
```

## Memory Considerations

### Block Capture

```objc
// __block allows modification
__block int counter = 0;

dispatch_async(queue, ^{
    counter++;
});

// __weak prevents retain cycles
__weak typeof(self) weakSelf = self;
dispatch_async(queue, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf doSomething];
});
```

## Scuttle Usage Examples

### Thread-Safe Logging

```objc
// Sources/SSBLog.m
dispatch_queue_t logQueue = dispatch_queue_create("com.scuttlebutt.log", DISPATCH_QUEUE_SERIAL);

- (void)logMessage:(NSString *)message level:(NSString *)level {
    dispatch_async(logQueue, ^{
        // Write to log file
    });
}
```

### Concurrent Network Operations

```objc
// Fetch multiple feeds concurrently
dispatch_queue_t feedQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

dispatch_apply(feedCount, feedQueue, ^(size_t index) {
    [self fetchFeed:feeds[index] completion:^(NSArray *messages) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateUIWithMessages:messages];
        });
    }];
});
```

### Resource Pool

```objc
dispatch_semaphore_t poolSemaphore = dispatch_semaphore_create(3); // 3 resources

for (NSDictionary *task in tasks) {
    dispatch_async(queue, ^{
        dispatch_semaphore_wait(poolSemaphore, DISPATCH_TIME_FOREVER);
        
        @try {
            [self processTask:task];
        } @finally {
            dispatch_semaphore_signal(poolSemaphore);
        }
    });
}
```

## Differences from Apple

### No Differences for GCD API

The GCD API is identical between macOS and Linux (libdispatch).

### Minor Differences

| Aspect | macOS | Linux (libdispatch) |
|--------|-------|---------------------|
| Main queue | UI thread | Needs event loop |
| qos_class_t | Full | May be limited |
| dispatch_io | Partial | Not available |
| dispatch_queue_attr_make_with_qos_class | Available | May be limited |

### Main Queue on Linux

On macOS, the main queue is tied to NSApplication's run loop. On Linux with GNUstep, you need to pump the run loop manually:

```objc
// GNUstep main.m
int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Start your app
        });
        
        // Pump the run loop
        while (![app isTerminating]) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode 
                                      beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }
}
```

## Summary

| Feature | macOS | Linux | Status |
|---------|-------|-------|--------|
| Queues | ✅ | ✅ | Compatible |
| Groups | ✅ | ✅ | Compatible |
| Semaphores | ✅ | ✅ | Compatible |
| Sources (timer) | ✅ | ✅ | Compatible |
| Sources (socket) | ✅ | ✅ | Compatible |
| dispatch_data_t | ✅ | ✅ | Compatible |
| dispatch_once | ✅ | ✅ | Compatible |
| QoS classes | ✅ | ⚠️ | Limited |
| dispatch_io | ✅ | ❌ | Not available |

**Conclusion:** GCD is fully compatible on Linux for Scuttle's use cases.
