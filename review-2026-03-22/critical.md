# Critical Findings

[← Index](index.md) | [High →](high.md)

These issues can cause crashes or data races under normal use. Fix before merging.

---

## C1 — nil guard fires after strongSelf access

**File:** [SRFeedViewController.m](files/SRFeedViewController.md#c1) · line 196–204
**Risk:** Crash if the view controller is deallocated between `dispatch_async` enqueue and execution.

In the main-queue block inside `refreshFeed`, `strongSelf` is dereferenced on lines 196–203 before the nil guard on line 204:

```objc
dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    // ← strongSelf accessed here (lines 196-203)
    if (strongSelf.filterAuthor) {
        strongSelf.integrityBadge.stringValue = ...;
        strongSelf.integrityBadge.textColor = ...;
        strongSelf.integrityBadge.hidden = NO;
    } else {
        strongSelf.integrityBadge.hidden = YES;
    }
    if (!strongSelf) return;   // ← nil check is too late
    [strongSelf applySnapshotWithMessages:newMessages];
    ...
});
```

**Fix:** Move `if (!strongSelf) return;` to immediately after the `__strong` assignment, before any property access.

---

## C2 — `internalClients` read outside `managerQueue`

**File:** [SRRoomManager.m](files/SRRoomManager.md#c2) · line 364–374
**Risk:** Data race. A concurrent writer on `managerQueue` can mutate `internalClients` while this thread reads it unprotected.

```objc
- (void)disconnectFromRoom:(NSString *)host {
    dispatch_sync(self.managerQueue, ^{          // ← mutation guarded
        [self.internalRoomEndpoints removeObjectForKey:host];
        [self.internalPeerSyncProgressByHost removeObjectForKey:host];
        [self.internalPeerSyncStatesByHost removeObjectForKey:host];
        [self.internalSyncStatusByHost removeObjectForKey:host];
        [self.internalSyncProgressByHost removeObjectForKey:host];
    });
    SSBRoomClient *client = self.internalClients[host]; // ← unguarded read
    [client disconnect];
}
```

`internalClients` is written inside `managerQueue` (e.g. in `connectToRoom:`, `removeRoom:`, `resetAccount:`). Reading it outside the queue is unsynchronised.

**Fix:** Extend the `dispatch_sync` block to also capture the client reference before leaving the queue:

```objc
- (void)disconnectFromRoom:(NSString *)host {
    __block SSBRoomClient *client;
    dispatch_sync(self.managerQueue, ^{
        client = self.internalClients[host];
        [self.internalRoomEndpoints removeObjectForKey:host];
        [self.internalPeerSyncProgressByHost removeObjectForKey:host];
        [self.internalPeerSyncStatesByHost removeObjectForKey:host];
        [self.internalSyncStatusByHost removeObjectForKey:host];
        [self.internalSyncProgressByHost removeObjectForKey:host];
    });
    [client disconnect];
}
```
