# SRPeerListViewController.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRPeerListViewController.m`
**Findings:** [H5](#h5) [N3](#n3)

---

## H5

**Debug log inside `numberOfRowsInTableView:` (hot path)** · [→ High findings](../high.md#h5)

Lines 362–365:

```objc
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    os_log_debug(peer_list_log, "numberOfRowsInTableView called - returning %lu",
                 (unsigned long)self.peers.count);
    return self.peers.count;
}
```

AppKit calls `numberOfRowsInTableView:` during every layout pass, selection change, scroll event, and reload. This log entry will fire continuously during normal UI interaction. Even though `os_log_debug` is a no-op when no debugger or `log stream` is attached, it should not be in production code. Remove it.

---

## N3

**Full peer array logged at INFO level on every update** · [→ Minor findings](../minor.md#n3)

Line 350:

```objc
os_log_info(peer_list_log, "Updating with %lu peers: %{public}@",
            (unsigned long)peers.count, peers);
```

`INFO` messages are retained in the system log buffer even without an attached debugger. With 50–200 peer IDs each being 50+ character base64 strings, this generates multi-kilobyte log entries on every endpoint update notification.

**Fix:** Log only the count. If peer IDs are needed for debugging, use `os_log_debug`.

---

## Other Observations

**`updatePeers:` mutates UI labels off main thread**

`setRoomHost:` can be called from outside (e.g., from a notification handler), and it calls `[self loadPeers]` → `[self updatePeers:]`. Inside `updatePeers:`, `self.emptyLabel.hidden` is set directly (line 352) before the `dispatch_async(dispatch_get_main_queue(), ...)` that reloads the table. If called off-main, this is a UI mutation off the main thread.

**`loadPeers` calls `SSBFeedStore allKnownAuthors` on caller's thread**

Line 234: `[NSMutableSet setWithArray:[[SSBFeedStore sharedStore] allKnownAuthors]]`. This is a synchronous DB scan. If `setRoomHost:` is called on the main thread (which it is from `SRMainSplitViewController`), this blocks main.

**Unused `list` variable in `endpointsDidUpdate:`**

Line 249: `NSArray *list = userInfo[SRRoomManagerEndpointsListKey];` — `list` is never used. The method always calls `loadPeers` which fetches from the manager. Remove the unused local.

**`SRPeerCell` corner radius hardcodes `20` for a `40pt` avatar**

`_avatarView.layer.cornerRadius = 20` at line 29. This is correct for a 40pt circular view but the magic number is fragile if the avatar size changes. Either reference a constant or compute `frame.size.width / 2` in `layoutSubviews`.
