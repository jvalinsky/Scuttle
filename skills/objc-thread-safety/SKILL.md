---
name: objc-thread-safety
description: Identify and fix Objective-C thread safety issues including race conditions in mutable collections, proper GCD queue usage, and atomic property patterns.
---

# Objective-C Thread Safety for Scuttle

This skill provides expertise in detecting and fixing thread safety issues in Objective-C code, focusing on mutable collection access, GCD patterns, and synchronization.

## When to Use This Skill

Use this skill when you are:
- Working with NSMutableArray, NSMutableDictionary, or NSMutableSet
- Accessing shared state from multiple threads
- Implementing async operations or callbacks
- Modifying network code or data stores
- Investigating crashes that occur intermittently

## Key Issues in Scuttle

### Critical: No Synchronization on Mutable Properties

**SSBRoomClient.m** - 7 mutable properties accessed without synchronization:
- `attendantsList`, `activeTunnels`, `pendingPublishQueue`
- `remoteClock`, `internalPeerSyncProgress`, `internalPeerSyncStates`
- `peerEBTState`

**SSBGitObjectStore.m** - `packs` NSMutableArray accessed without sync

### Medium: Queue Created But Unused

**SSBBlobStore.m** - Serial queue created but not used for most operations

### Low: Single Method Missing Sync

**SRRoomManager.m line 305** - `disconnectFromRoom:` accesses mutable dict without queue

### Good Patterns Already in Codebase

**SSBFeedStore.m** - Serial queue for all database access:
```objc
@property (nonatomic, strong) dispatch_queue_t dbQueue;
_dbQueue = dispatch_queue_create("com.scuttlebutt.feedstore.db", DISPATCH_QUEUE_SERIAL);

- (nullable SSBFeedState *)feedStateForAuthor:(NSString *)author {
    __block SSBFeedState *state = nil;
    dispatch_sync(self.dbQueue, ^{
        state = [self _feedStateForAuthor:author];
    });
    return state;
}
```

**SSBMuxRPCSession.m** - Atomic counter + serial queue:
```objc
@property (nonatomic, assign) _Atomic int32_t nextRequestID;
@property (nonatomic, strong) dispatch_queue_t accessQueue;

int32_t reqNum = atomic_fetch_add_explicit(&_nextRequestID, 1, memory_order_relaxed);
```

## Workflow: Fix Thread Safety Issue

1. **Identify shared mutable state**: Look for NSMutableArray, NSMutableDictionary properties
2. **Trace access points**: Find all read/write locations
3. **Determine thread context**: Which threads access this data?
4. **Choose synchronization**:
   - Serial queue for writes + reads
   - @synchronized for simple cases
   - _Atomic for simple scalars
5. **Apply pattern**: Use consistent sync for all accesses

## Reference Files

- [MUTABLE_COLLECTION_PATTERNS.md](references/MUTABLE_COLLECTION_PATTERNS.md) - NSMutable thread safety
- [GCD_PATTERNS.md](references/GCD_PATTERNS.md) - Serial/concurrent queues
- [ATOMIC_PATTERNS.md](references/ATOMIC_PATTERNS.md) - _Atomic usage
- [ISSUES_FOUND.md](references/ISSUES_FOUND.md) - Known issues in codebase
