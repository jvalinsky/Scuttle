# Objective-C Patterns & macOS API Review

This document critiques Objective-C patterns, architecture decisions, and macOS API usage found in the Scuttle codebase.

---

## Critical Issues

### 1. Strong `self` Captures in Network Callbacks (Retain Cycles)

**`SSBRoomClient.m:144–167`** — The `nw_connection_set_state_changed_handler` block captures `self` strongly while `self` owns the `connection`. This is a retain cycle:

```objc
nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
    self.isConnected = YES;   // strong capture — retain cycle
    [self startReceivingMessages];
    [self performInitialSetup];
});
```

**`SSBRoomClient.m:173–204`** — `startReceivingMessages` re-schedules itself recursively inside a completion block that also captures `self` strongly. This forms a second retain cycle and the recursion continues indefinitely until the connection is torn down:

```objc
- (void)startReceivingMessages {
    nw_connection_receive_message(self.connection, ^(...) {
        ...
        [self startReceivingMessages]; // strong capture, infinite recursion
    });
}
```

Both should use `__weak typeof(self) weakSelf = self;` + a `strongSelf` guard inside.

---

### 2. Private Key Stored in `NSUserDefaults`

**`SRMainSplitViewController.m:67`** and **`:132`**:

```objc
NSData *localSecret = [[NSUserDefaults standardUserDefaults] dataForKey:@"SSBLocalIdentity"];
```

`NSUserDefaults` is not encrypted and is world-readable on macOS (stored plaintext in `~/Library/Preferences`). The same private key is stored correctly via `SSBKeychain`, which wraps the secure Keychain API. Reading credentials from `NSUserDefaults` instead of the Keychain is a security vulnerability — if this path is exercised, the private key material is exposed.

---

### 3. Keychain Accessibility Too Permissive

**`SSBKeychain.m:48`**:

```objc
query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
```

`kSecAttrAccessibleAfterFirstUnlock` allows the item to be read even when the screen is locked (e.g. by background daemons). For an Ed25519 private key, `kSecAttrAccessibleWhenUnlocked` is more appropriate — it restricts access to only when the user's session is active.

---

### 4. Thread Safety: Mutable Collections Accessed Without Synchronization

**`SRRoomManager.m`** — `internalRooms`, `internalClients`, and `internalRoomEndpoints` are `NSMutableArray`/`NSMutableDictionary` instances that are read and written from multiple threads:

- `connectToRoom:` and `removeRoom:` mutate `internalClients` (called from the main thread)
- Delegate callbacks like `roomClient:didUpdateEndpoints:` write to `internalRoomEndpoints` (they arrive on `clientQueue`, not the main thread)
- `resetAccount` wipes all three collections

There is no `@synchronized`, serial dispatch queue, or any other synchronization protecting these accesses. This is a data race.

---

## Objective-C Pattern Issues

### 5. `NSLog` vs `os_log` Used Inconsistently

Many files set up a dedicated `os_log` channel at the top:

```objc
static os_log_t ssb_room_log = os_log_create("com.scuttlebutt.room", "Client");
```

Yet the same files have dozens of raw `NSLog` calls for the actual logging:

```objc
NSLog(@"[ROOM_DIAG] Connection state: READY");
NSLog(@"[EBT] startEBTReplicationWithSession called...");
NSLog(@"[RPCSession %p] handleIncomingMessage called...");
```

`NSLog` is synchronous, always emits to stderr/Console, and has no privacy controls. `os_log` is the correct unified logging API for production macOS code — it is async, respects log levels, supports privacy annotations (`{public}`, `{private}`), and integrates with Instruments. The code should use the declared `os_log` handles consistently. The diagnostic `[ROOM_DIAG]` prefix convention also suggests these are debug traces that were never cleaned up.

---

### 6. FSM State Advance by Integer Increment

**`SSBConnectionFSM.m:23`**:

```objc
_currentState++;
```

`advanceState` moves through the handshake by blindly incrementing the enum value. This is fragile — it requires enum values to be contiguous, in the correct order, and never reordered. A state transition table or explicit `switch` dispatch would be safer:

```objc
// Fragile: relies on enum layout
typedef NS_ENUM(NSInteger, SSBConnectionState) {
    SSBConnectionStateInit,
    SSBConnectionStateSHSHello,   // if reordered, increment breaks
    SSBConnectionStateSHSAuth,
    SSBConnectionStateSHSAccept,
    SSBConnectionStateBoxStream,
    SSBConnectionStateError,
    SSBConnectionStateClosed
};
```

Additionally, the FSM only calls `connectionFSMDidRequestParse:` for all non-BoxStream transitions. The delegate receives no information about *which* state was entered, making it responsible for tracking state externally.

---

### 7. `dispatch_after` Used for UI Synchronization

**`SRRoomManager.m:44–50`**:

```objc
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    // "Notify after a short delay to allow UI to setup and listen"
    [[NSNotificationCenter defaultCenter] postNotificationName:SRRoomManagerDidUpdateRoomsNotification object:nil];
});
```

This is a race condition disguised as a workaround. If the UI takes more than 2 seconds to load (slow machine, heavy initialization), the notification fires before any observer is registered and is silently dropped. The correct pattern is for the UI to call into the model on `viewDidLoad` to pull current state, rather than relying on a lucky timing window.

**`SSBRoomClient.m:255`** has a similar pattern — a `dispatch_after` of 5 seconds for `room.metadata` timeout — with an unguarded `__block BOOL metadataFinished` flag that is not atomic.

---

### 8. Public Key Derivation Duplicated in Multiple Places

The same 3-line snippet for deriving the SSB public ID from a 64-byte Ed25519 keypair appears in at least three places:

- `SRRoomManager.m:72–73`
- `SRMainSplitViewController.m:69–70`
- `SRMainSplitViewController.m:133–135`

```objc
NSData *pkData = [savedIdentity subdataWithRange:NSMakeRange(32, 32)];
NSString *myId = [NSString stringWithFormat:@"@%@.ed25519", [pkData base64EncodedStringWithOptions:0]];
```

The magic offset `32` and length `32` are undocumented. This belongs in `SSBKeychain` or a dedicated identity utility as a named method.

---

### 9. Notification Object Used for Data Instead of `userInfo`

**`AppDelegate.m:104–106`**:

```objc
- (void)handleNewMessageNotification:(NSNotification *)notification {
    NSDictionary *msgDict = notification.object;
```

`NSNotification.object` is the *sender*, not a data payload. Data should be passed in `notification.userInfo`. This is an incorrect use of the API and makes the notification contract opaque. The same problem occurs at `AppDelegate.m:154` (`postNotificationName:@"SRRoomSelectedNotification" object:room`).

---

### 10. Notification Names as String Literals (Mixed with Constants)

Some notifications are properly defined as constants:

```objc
// SRRoomManager.h/.m
NSString * const SRRoomManagerDidUpdateRoomsNotification = @"SRRoomManagerDidUpdateRoomsNotification";
```

But others are bare string literals scattered throughout:

```objc
// AppDelegate.m
[[NSNotificationCenter defaultCenter] addObserver:self ... name:@"SRNewMessageNotification" ...];
// SRMainSplitViewController.m
[[NSNotificationCenter defaultCenter] addObserver:self ... name:@"SRRoomSelectedNotification" ...];
[[NSNotificationCenter defaultCenter] addObserver:self ... name:@"SRLocalIdentityGeneratedNotification" ...];
```

A typo in either the post or observe site silently drops the notification. All notification names should be `extern NSString * const` declared in a header.

---

### 11. `performSelector:` to Work Around Missing Interface Declaration

**`AppDelegate.m:76–78`**:

```objc
- (void)showPreferences:(id)sender {
    if ([self.mainVC respondsToSelector:@selector(showPreferences)]) {
        [self.mainVC performSelector:@selector(showPreferences)];
    }
}
```

`showPreferences` is a public method on `SRMainSplitViewController` but is not declared in its header. Using `respondsToSelector:` + `performSelector:` to call it bypasses the compiler, produces a `performSelector may cause a leak` warning, and hides a missing public interface declaration.

---

### 12. Forced Protocol Cast Without Declared Conformance

**`AppDelegate.m:19`**:

```objc
center.delegate = (id<UNUserNotificationCenterDelegate>)self;
```

**`AppDelegate.m:41`**:

```objc
toolbar.delegate = (id<NSToolbarDelegate>)self.mainVC;
```

`AppDelegate` does not declare `<UNUserNotificationCenterDelegate>` in its interface, so the cast silences a compiler warning rather than fixing it. The class should declare the conformance. The toolbar cast is similarly unsafe.

---

### 13. `processPublishQueue`: Mutating Array During Copy + O(n²) `removeObject:`

**`SSBRoomClient.m:634–652`**:

```objc
for (NSDictionary *queuedItem in [self.pendingPublishQueue copy]) {
    ...
    [self.pendingPublishQueue removeObject:queuedItem]; // O(n) scan per item
}
// Then: removeAllObjects + addObjectsFromArray:failedItems
```

`removeObject:` scans the array linearly for each item and is being called in a loop, making the whole operation O(n²). Since the array is cleared and re-populated at the end anyway, the mid-loop removals are pointless. The iteration and the cleanup should just process all items and then rebuild the queue once.

---

### 14. `__block SSBRPCCallback` Potential Retain Cycle

**`SSBRoomClient.m:696–708`**:

```objc
__block SSBRPCCallback ebtCallback;
ebtCallback = ^(id response, NSError *error) {
    ...
    [weakSelf handleEBTMessage:response requestID:0 flags:0];
};
self.ebtRequestID = [session sendRequest:... completion:ebtCallback];
```

`ebtCallback` is a `__block` variable captured in a block that is itself stored in `session.pendingRequests`. The block keeps a strong reference to `ebtCallback` (through `__block` storage), and `ebtCallback` references the block. The commented-out `if (self.isEBTRunning) return;` guard at line 690 was likely suppressing this to allow multiple invocations — re-enabling it without addressing the ownership structure would mask the underlying problem.

---

### 15. Schema Migration Without Version Tracking

**`SSBFeedStore.m:78–128`** detects missing columns by scanning `PRAGMA table_info` for each column name. This ad-hoc migration approach does not scale — each future migration requires another `PRAGMA` check. SQLite's `PRAGMA user_version` provides a proper integer schema version that can drive a deterministic migration sequence.

---

### 16. Database Queries on the Main Thread

**`SRFeedViewController.m:91–118`** (`refreshFeed`) is called directly from UI event handlers and notification observers, and runs synchronous SQLite queries inline:

```objc
- (void)refreshFeed {
    // This entire block runs on the main thread
    [newMessages addObjectsFromArray:[[SSBFeedStore sharedStore] feedForAuthor:self.filterAuthor limit:50]];
    ...
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData]; // redundant — already on main
    });
}
```

The `dispatch_async(dispatch_get_main_queue(), ...)` for `reloadData` is also redundant if `refreshFeed` is already on the main thread. Database I/O should move to a background queue, with only the collection view reload dispatched back to main.

---

## macOS API Issues

### 17. `activateIgnoringOtherApps:` Is Deprecated

**`AppDelegate.m:158`**:

```objc
[NSApp activateIgnoringOtherApps:YES];
```

Deprecated in macOS 14 (Sonoma). Use `[NSApp activate]` instead.

---

### 18. Main Window and Menu Created Entirely in Code

**`AppDelegate.m:29–72`** creates both the main window and the entire application menu programmatically. While technically valid, this means:

- No visual design-time preview
- Localization requires code changes (not Localizable.strings-friendly)
- The Edit menu's standard responder chain items (Cut/Copy/Paste/Select All) work, but only by coincidence because they target `nil` and walk the responder chain — they are not connected to any explicit first responder

macOS convention is to define the application menu in `MainMenu.xib` or the main storyboard.

---

### 19. Missing `NSWindowRestoration` Support

The main `NSWindow` is created without a restoration class or identifier. After a crash or logout, macOS cannot restore the window's position, size, or state. At minimum, `window.restorationClass` or `window.identifier` should be set.

---

### 20. `NSCollectionView` Used Without `NSCollectionViewDiffableDataSource`

**`SRFeedViewController.m`** uses the legacy `NSCollectionViewDataSource` protocol with `reloadData`. On macOS 10.15+, `NSCollectionViewDiffableDataSource` provides automatic diff-based animated updates, avoids index-path mismatches, and is the idiomatic modern approach.

---

### 21. `NSSplitViewItem` Pane Management via View Hide/Show

**`SRMainSplitViewController.m`** manages navigation by hiding and showing subviews (`.hidden = YES/NO`). All child views remain loaded and in the hierarchy simultaneously:

```objc
self.headerView.hidden = YES;
self.feedVC.view.hidden = YES;
self.composeVC.view.hidden = YES;
```

This means all views consume memory and layout resources continuously. Using `NSSplitViewController` with `NSSplitViewItem` collapse or replacing the content view controller would be more idiomatic and efficient. Alternatively, a `NSTabViewController` or view controller containment with proper `addChildViewController:` / `removeFromParentViewController` lifecycle (which *is* used for profile/thread views, but not for the primary feed) would be consistent.

---

### 22. `dispatch_sync` Risk of Deadlock in `SSBMuxRPCSession`

**`SSBMuxRPCSession.m:36`**:

```objc
dispatch_sync(self.accessQueue, ^{
    reqNum = self.nextRequestID++;
    ...
});
```

If `sendRequest:` is ever called from the `accessQueue` itself (e.g. from inside another block dispatched on that queue), this will deadlock. There is no assertion or check to prevent this. An atomic integer (`OSAtomicIncrement32` / `_Atomic int32_t`) would eliminate the lock for the counter increment entirely.

---

## Summary Table

| # | File | Severity | Category |
|---|------|----------|----------|
| 1 | `SSBRoomClient.m:144,173` | Critical | Retain cycle / memory |
| 2 | `SRMainSplitViewController.m:67,132` | Critical | Security — plaintext private key |
| 3 | `SSBKeychain.m:48` | High | Security — accessibility policy |
| 4 | `SRRoomManager.m` | High | Thread safety — data race |
| 5 | Throughout | Medium | `NSLog` vs `os_log` |
| 6 | `SSBConnectionFSM.m:23` | Medium | Fragile state increment |
| 7 | `SRRoomManager.m:44` | Medium | Timing-dependent UI notification |
| 8 | Multiple files | Medium | Duplicated key derivation |
| 9 | `AppDelegate.m:104` | Medium | `notification.object` misuse |
| 10 | Multiple files | Low | String literal notification names |
| 11 | `AppDelegate.m:76` | Low | `performSelector` / missing interface |
| 12 | `AppDelegate.m:19,41` | Low | Forced protocol cast |
| 13 | `SSBRoomClient.m:634` | Low | O(n²) queue processing |
| 14 | `SSBRoomClient.m:696` | Medium | `__block` callback retain cycle |
| 15 | `SSBFeedStore.m:78` | Low | Ad-hoc schema migration |
| 16 | `SRFeedViewController.m:91` | Medium | DB query on main thread |
| 17 | `AppDelegate.m:158` | Low | Deprecated `activateIgnoringOtherApps:` |
| 18 | `AppDelegate.m:29` | Low | Programmatic window/menu |
| 19 | `AppDelegate.m:29` | Low | Missing window restoration |
| 20 | `SRFeedViewController.m` | Low | Legacy `NSCollectionViewDataSource` |
| 21 | `SRMainSplitViewController.m` | Low | View hide/show navigation pattern |
| 22 | `SSBMuxRPCSession.m:36` | Medium | `dispatch_sync` deadlock risk |
