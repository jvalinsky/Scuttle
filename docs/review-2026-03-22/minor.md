# Minor Findings

[← Medium](medium.md) | [Index](index.md)

Low-risk issues. Address at your discretion — they won't cause crashes but reduce code clarity or logging quality.

---

## N1 — Strong `self` in `rotateFeedKeyAction:` completion

**File:** [SRPreferencesViewController.m](files/SRPreferencesViewController.md#n1) · line 403–419
**Risk:** If the preferences sheet is dismissed after the rotation is initiated (but before it completes), the VC stays alive until the completion fires and updates now-invisible UI.

```objc
self.rotateFeedKeyButton.enabled = NO;
[[SRRoomManager sharedManager] replaceSubfeed:classicFeedID
                                   completion:^(NSString *newFeedID, NSError *error) {
    self.rotateFeedKeyButton.enabled = YES;  // ← strong self
    ...
}];
```

Use a `weakSelf/strongSelf` pattern. Bail early with `if (!strongSelf) return;` so the UI update is skipped if the sheet is already gone.

---

## N2 — Sort comparator duplicated in `SRStorageUsageView`

**File:** [SRPreferencesViewController.m](files/SRPreferencesViewController.md#n2) · line 39–43 and 84–88
**Risk:** Maintenance burden. If the sort order changes, both copies must be updated.

The same author-sort-by-message-count comparator block appears verbatim in both `mouseMoved:` and `drawRect:`. Extract to a private helper:

```objc
- (NSArray<NSString *> *)_sortedAuthors {
    return [self.stats.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        long long countA = 0; for (NSNumber *n in self.stats[a].allValues) countA += n.longLongValue;
        long long countB = 0; for (NSNumber *n in self.stats[b].allValues) countB += n.longLongValue;
        return [@(countB) compare:@(countA)];
    }];
}
```

---

## N3 — Full peer array logged at INFO level on every update

**File:** [SRPeerListViewController.m](files/SRPeerListViewController.md#n3) · line 350
**Risk:** Log noise. Peer IDs are long strings; logging the full array generates large log entries on every endpoint update.

```objc
os_log_info(peer_list_log, "Updating with %lu peers: %{public}@",
            (unsigned long)peers.count, peers);
```

Log just the count:

```objc
os_log_info(peer_list_log, "Updating with %lu peers", (unsigned long)peers.count);
```

---

## N4 — Emoji in `SSBLogError` / `SSBLogInfo` calls

**File:** [SRFeedViewController.m](files/SRFeedViewController.md#n4) · lines 248–298
**Risk:** Log messages containing emoji (`📥`, `❌`, `✅`, `⚠️`) are harder to grep and non-standard in production logging.

Examples:
```objc
SSBLogInfo(SSBLogCategoryUI, @"📥 loadFeedForAuthor: %@ client=%@ connected=%d", ...);
SSBLogError(SSBLogCategoryUI, @"   ❌ No client provided!");
SSBLogInfo(SSBLogCategoryUI, @"   ✅ Profile fetched: %@", response);
SSBLogWarning(SSBLogCategoryUI, @"   ⚠️ No profile response");
```

Replace with plain-text descriptions. The severity is already conveyed by `SSBLogError` vs `SSBLogInfo`.
