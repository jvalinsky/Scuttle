# High Priority Findings

[← Critical](critical.md) | [Index](index.md) | [Medium →](medium.md)

These issues represent clear bugs or resource leaks. Fix before shipping.

---

## H1 — No-op `@try/@catch` re-throws exception

**File:** [AppDelegate.m](files/AppDelegate.md#h1) · line 56–63
**Risk:** Dead code. Adds noise and implies error recovery where there is none.

```objc
@try {
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [self bringToFront:nil];
} @catch (NSException *exception) {
    @throw exception;   // identical to not catching at all
}
```

`@throw exception` inside a `@catch` block is exactly the same as not catching. A reader may reasonably believe errors are being handled here. The entire block should be unwrapped — just call the three methods directly.

---

## H2 — Window brought to front 6 times redundantly

**File:** [AppDelegate.m](files/AppDelegate.md#h2) · line 56–77
**Risk:** Confusing intent; aggressive activation may conflict with future window management.

`makeKeyAndOrderFront:`, `orderFrontRegardless:`, and `bringToFront:` are each called once in the try block and again in the `dispatch_async` block that follows. The async call (when `mainVC` is ready) is the correct one. The pre-async calls accomplish nothing useful since `contentViewController` is still a placeholder `NSViewController` at that point.

---

## H3 — Missing `dealloc` in `SRSidebarViewController`

**File:** [SRSidebarViewController.m](files/SRSidebarViewController.md#h3) · line 56–90
**Risk:** If the VC is ever released, the five notification observers registered via `addObserver:selector:name:object:` will fire on a deallocated object.

`SRFeedViewController` and `SRPeerListViewController` both correctly implement `dealloc` and remove their observers. `SRSidebarViewController` registers five observers but has no `dealloc`.

Notifications registered:
- `SRRoomManagerDidUpdateRoomsNotification`
- `SRRoomManagerConnectionStatusChangedNotification`
- `SRRoomManagerDidUpdateEndpointsNotification`
- `SRRoomSyncStatusChangedNotification`
- `SRRoomManagerRoomSelectedNotification`
- `SRGitRepoCreatedNotification`
- `SRNewMessageNotification`

**Fix:** Add a `dealloc` that calls `[[NSNotificationCenter defaultCenter] removeObserver:self]`.

---

## H4 — `NSWindow` created without an owner in `showDevPanelAction:`

**File:** [SRPreferencesViewController.m](files/SRPreferencesViewController.md#h4) · line 427–436
**Risk:** Memory leak. The window stays on screen but cannot be properly dismissed or deallocated.

```objc
- (void)showDevPanelAction:(id)sender {
    Class devPanelClass = NSClassFromString(@"SRDevPanelViewController");
    if (devPanelClass) {
        NSViewController *vc = [[devPanelClass alloc] init];
        NSWindow *window = [[NSWindow alloc] init...];
        window.releasedWhenClosed = NO;
        window.contentViewController = vc;
        [window makeKeyAndOrderFront:nil];
        // window and vc dropped here — no strong reference
    }
}
```

With `releasedWhenClosed = NO`, the AppKit window server holds a weak reference to the `NSWindow`, preventing deallocation, but nothing in the app holds a strong reference to close or manage it. Use an `NSWindowController` stored as a property, or at minimum store the window in an ivar.

---

## H5 — Debug log inside `numberOfRowsInTableView:` (hot path)

**File:** [SRPeerListViewController.m](files/SRPeerListViewController.md#h5) · line 363
**Risk:** Log spam. This method is called by AppKit during every layout pass, scroll, selection change, and resize.

```objc
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    os_log_debug(peer_list_log, "numberOfRowsInTableView called - returning %lu",
                 (unsigned long)self.peers.count);
    return self.peers.count;
}
```

Even at `debug` level, `os_log_debug` has measurable overhead when a debugger or `log stream` is attached. Remove this log entirely.
