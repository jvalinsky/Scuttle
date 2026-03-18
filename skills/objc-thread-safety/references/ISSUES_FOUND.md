# Known Thread Safety Issues in Scuttle

## Critical Issues

### 1. SSBRoomClient.m - Multiple Mutable Properties Without Synchronization

**File:** `Sources/SSBRoomClient.m`

**Problem:** 7 mutable properties accessed without any synchronization from multiple threads.

| Property | Accessed From | Risk |
|----------|---------------|------|
| `attendantsList` | Main + callbacks | HIGH |
| `activeTunnels` | Main + clientQueue | HIGH |
| `pendingPublishQueue` | Main + callbacks | HIGH |
| `remoteClock` | clientQueue callbacks | HIGH |
| `internalPeerSyncProgress` | Main + property getter | HIGH |
| `internalPeerSyncStates` | Main + property getter | HIGH |
| `peerEBTState` | clientQueue callbacks | HIGH |

**Example Issue - remoteClock:**
```objc
// Lines 831-850 - Modified in handleRemoteClockUpdate callback (runs on clientQueue)
NSMutableDictionary *targetClock = self.remoteClock;  // Direct access
[update enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
    targetClock[author] = @(ABS(seq));  // Mutating without sync
}];
```

**Fix needed:** Use serial queue for all these properties.

---

### 2. SSBGitObjectStore.m - Unprotected Mutable Array

**File:** `Sources/SSBGitObjectStore.m`

**Problem:** `packs` NSMutableArray accessed without synchronization.

```objc
// Line 8
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *packs;

// Lines 22-36 - No synchronization
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

**Fix needed:** Add serial queue protection.

---

## Medium Issues

### 3. SSBBlobStore.m - Queue Created But Underutilized

**File:** `Sources/SSBBlobStore.m`

**Problem:** Serial queue created but not used for most operations.

```objc
// Line 36 - Queue created
_ioQueue = dispatch_queue_create("com.scuttlebutt.blobstore", DISPATCH_QUEUE_SERIAL);

// Line 177 - Only used for wipeBlobs
- (void)wipeBlobs {
    dispatch_sync(self.ioQueue, ^{
        // ...
    });
}

// Lines 102-108 - fetchBlob accesses state directly without queue
- (void)fetchBlob:(NSString *)blobID session:(SSBMuxRPCSession *)session completion:... {
    NSString *existing = [self localPathForBlobID:blobID];  // Direct access - RACE
    if (existing) {
        // ...
    }
    // No queue protection for pendingFetches access
}
```

**Fix needed:** Use `_ioQueue` for all state access.

---

## Low Issues

### 4. SRRoomManager.m - One Method Missing Sync

**File:** `App/Logic/SRRoomManager.m`

**Problem:** `disconnectFromRoom:` accesses mutable dict without queue.

```objc
// Line 305 - Direct access without synchronization!
- (void)disconnectFromRoom:(NSString *)host {
    SSBRoomClient *client = self.internalClients[host];  // NO SYNC
    [client disconnect];
}
```

Compare to correct pattern at lines 531-535:
```objc
// Correct - uses queue
- (nullable SSBRoomClient *)clientForHost:(NSString *)host {
    __block SSBRoomClient *client;
    dispatch_sync(self.managerQueue, ^{ client = self.internalClients[host]; });
    return client;
}
```

**Fix needed:** Wrap in `dispatch_sync(self.managerQueue, ^{...})`.

---

## Issues in SSBHTTPAuth.m (Memory/Thread Combined)

### 5. SSBHTTPAuth.m - Direct Self Capture in dispatch_async

**File:** `Sources/SSBHTTPAuth.m`

**Problem:** Multiple blocks capture `self` strongly in `dispatch_async`.

Lines to check: 273-304, 331, 484, 499, 561, 678, 808

```objc
// Example from lines 273-304
void (^signAndComplete)(void) = ^{
    dispatch_async(self.authQueue, ^{  // self retained by block
        NSString *signatureMessage = [self signatureMessageWithServerId:self.serverId
                                                                clientId:clientId
                                                    ...];
    });
};
```

This is both a retain cycle AND a thread safety issue - the block captures `self` strongly while the queue accesses `self` properties.

**Fix needed:** Use `__weak typeof(self) weakSelf = self;` pattern.

---

## Summary Table

| File | Issue | Severity | Type |
|------|-------|----------|------|
| `SSBRoomClient.m` | 7 mutable properties | CRITICAL | Race condition |
| `SSBGitObjectStore.m` | packs array | CRITICAL | Race condition |
| `SSBBlobStore.m` | Queue unused | MEDIUM | Race condition |
| `SRRoomManager.m` | disconnectFromRoom | LOW | Race condition |
| `SSBHTTPAuth.m` | Strong self in blocks | CRITICAL | Retain cycle |
