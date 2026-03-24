# SRRoomManager.m — Review Notes

[← Index](../index.md)

**Path:** `App/Logic/SRRoomManager.m`
**Findings:** [C2](#c2) [M6](#m6)

---

## C2

**`internalClients` read outside `managerQueue`** · [→ Critical findings](../critical.md#c2)

`disconnectFromRoom:` (lines 364–374) uses `dispatch_sync(self.managerQueue, ...)` to remove keys from the sync dictionaries but then reads `self.internalClients[host]` on line 372 outside the queue:

```objc
- (void)disconnectFromRoom:(NSString *)host {
    dispatch_sync(self.managerQueue, ^{
        [self.internalRoomEndpoints removeObjectForKey:host];
        // ... other removes
    });
    SSBRoomClient *client = self.internalClients[host]; // ← unguarded
    [client disconnect];
}
```

All writes to `internalClients` happen inside `managerQueue`. Reading outside it is a data race with any concurrent `connectToRoom:`, `removeRoom:`, or `resetAccount:` call.

**Fix:**
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

---

## M6

**Error domain as inline literal string (6×)** · [→ Medium findings](../medium.md#m6)

`@"SRRoomManager"` is used as the error domain in six `NSError` constructions across `joinRoomWithInvite:` and `replaceSubfeed:`. This is:
- Typo-prone (no compiler check)
- Non-idiomatic (should be reverse-DNS style)
- Inconsistent with `os_log` subsystem `"com.scuttlebutt.room"` already in use

**Fix:** Declare once at the top of the file (alongside the other `NSString * const` declarations):

```objc
NSString * const SRRoomManagerErrorDomain = @"com.scuttlebutt.SRRoomManager";
```

And expose it in `SRRoomManager.h` if call sites need to match against it.

---

## Other Observations

**`removeRoom:` double-removes keys from sync dicts**

`removeRoom:` (lines 551–566) calls `disconnectFromRoom:` on line 553, which already removes keys from `internalRoomEndpoints`, `internalPeerSyncProgressByHost`, etc. via `dispatch_sync`. Then `removeRoom:` calls `dispatch_sync` again (line 554) and removes the same keys a second time. Harmless, but indicates the two methods have overlapping responsibilities. Consider whether `disconnectFromRoom:` should not be called from within `removeRoom:`, or whether it should only handle the client lifecycle.

**`needsMetafeedAnnounce` thread safety**

`needsMetafeedAnnounce` is an `assign` BOOL property accessed from: `bootstrapMetafeedIfNeeded` (called on init, potentially background), `offerSeedRestoreFromAuthor:` (called on main), and `roomClientDidSyncLocalFeed:` (called on unknown thread from SSBRoomClient delegate). It is not read/written inside `managerQueue`. For a BOOL this is unlikely to cause a practical issue, but for correctness it should be read/written under `managerQueue` or be `atomic`.

**`resolveDisplayNameForAuthor:` name-equals-ID heuristic**

Lines 619–620 treat a cached display name that equals the author ID as "not cached". This is a reasonable heuristic but will fail for the unlikely case where a user sets their display name to their own public key. Not worth fixing now, but worth a comment.
