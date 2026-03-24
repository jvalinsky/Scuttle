# SRSidebarViewController.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRSidebarViewController.m`
**Findings:** [H3](#h3) [M3](#m3) [M4](#m4)

---

## H3

**Missing `dealloc` — notification observers never removed** · [→ High findings](../high.md#h3)

Seven observers are registered in `viewDidLoad` (lines 56–90) using `addObserver:selector:name:object:`. This form of observer registration does **not** auto-remove on dealloc — the caller is responsible for removing via `removeObserver:`. There is no `dealloc` implementation.

Registered selectors:
- `roomsDidUpdate:` — `SRRoomManagerDidUpdateRoomsNotification`
- `statusDidUpdate:` — `SRRoomManagerConnectionStatusChangedNotification`
- `endpointsDidUpdate:` — `SRRoomManagerDidUpdateEndpointsNotification`
- `syncStatusDidUpdate:` — `SRRoomSyncStatusChangedNotification`
- `roomSelected:` — `SRRoomManagerRoomSelectedNotification`
- `gitReposDidUpdate:` — `SRGitRepoCreatedNotification`
- `gitReposDidUpdate:` — `SRNewMessageNotification`

In the current architecture the sidebar VC likely lives for the app's lifetime. But defensive cleanup is important, and other view controllers in this file (`SRFeedViewController`, `SRPeerListViewController`) both implement `dealloc`. Consistency matters.

**Fix:**
```objc
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
```

---

## M3

**DB query on main thread in `loadGitRepos`** · [→ Medium findings](../medium.md#m3)

Lines 96–101:

```objc
- (void)loadGitRepos {
    self.gitRepos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
    });
}
```

`messagesOfType:limit:` is a synchronous database read. `loadGitRepos` is called from:
- `viewDidLoad` (main thread)
- `gitReposDidUpdate:` (triggered by `SRNewMessageNotification` — fired frequently during active sync)

During sync, this method runs a DB query on the main thread on every incoming message. This will cause UI jank as the message count grows.

**Fix:**
```objc
- (void)loadGitRepos {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *repos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.gitRepos = repos;
            [self _rebuildSections];
        });
    });
}
```

---

## M4

**Strong `self` capture in `joinRoomAction:` completion** · [→ Medium findings](../medium.md#m4)

Lines 668–689, inside the `NSAlert` handler for the "Join" button:

```objc
[[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.syncProgress stopAnimation:nil];       // strong self
        self.syncStatusContainer.hidden = YES;
        if (!success) {
            ...
        } else {
            self.syncLabel.stringValue = @"Joined room!";
            self.syncStatusContainer.hidden = NO;
            dispatch_after(..., ^{
                self.syncStatusContainer.hidden = YES; // strong self, inner block
            });
            [self _rebuildSections];
        }
    });
}];
```

The inner `dispatch_after` block also captures `self` strongly. This forms a two-level retain cycle that lasts for 2 seconds after the join completes.

**Fix:** Capture weakly at the outer block, re-strengthen at each block entry:

```objc
__weak typeof(self) weakSelf = self;
[[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.syncProgress stopAnimation:nil];
        ...
        dispatch_after(..., ^{
            __strong typeof(weakSelf) s = weakSelf;
            s.syncStatusContainer.hidden = YES;
        });
    });
}];
```

---

## Other Observations

**`_rebuildSections` triggered on every incoming message**

`SRNewMessageNotification` → `gitReposDidUpdate:` → `loadGitRepos` → `_rebuildSections` calls `[self.outlineView reloadData]`. During active sync this can fire dozens of times per second, causing excessive outline view reloads. Consider debouncing with a short timer (50–100 ms) or checking whether the git-repo message count actually changed.

**`outlineView:viewForTableColumn:item:` builds cell icons in the item-creation branch only**

For `SRSidebarItemTypeRepo` (lines 450–495), the icon is only set during cell creation (inside `if (!cell)`), but for `SRSidebarItemTypeRoom` the icon is updated on every cell dequeue (lines 399–422). If a repo cell is reused for a different repo, its icon will reflect the cell's original creation-time icon. Since the repo icon logic is currently a no-op for non-git repos, this has no visible effect now but will become a bug if icon logic grows.
