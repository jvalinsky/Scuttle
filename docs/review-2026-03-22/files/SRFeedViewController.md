# SRFeedViewController.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRFeedViewController.m`
**Findings:** [C1](#c1) [M5](#m5) [N4](#n4)

---

## C1

**nil guard fires after `strongSelf` access** · [→ Critical findings](../critical.md#c1)

Inside the main-queue block in `refreshFeed` (lines 193–209), `strongSelf` is accessed before the nil guard:

```objc
dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf.filterAuthor) {            // line 196 — access before nil check
        strongSelf.integrityBadge.stringValue = ...;
        strongSelf.integrityBadge.textColor = ...;
        strongSelf.integrityBadge.hidden = NO;
    } else {
        strongSelf.integrityBadge.hidden = YES; // line 203 — still before nil check
    }
    if (!strongSelf) return;                  // line 204 — too late
    [strongSelf applySnapshotWithMessages:newMessages];
    ...
});
```

If the VC is deallocated on the background thread between the `dispatch_async` enqueue and execution on main, `strongSelf` will be nil and all property accesses on lines 196–203 will silently no-op (messaging nil is safe in ObjC). However, the pattern is still wrong: the intent is to skip the block entirely when the VC is gone, and in a future refactor someone might add a non-nil-safe operation before the guard.

**Fix:** Move the guard to the top:

```objc
dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if (strongSelf.filterAuthor) {
        ...
    }
    ...
});
```

---

## M5

**Hardcoded notification name not in `SRNotificationNames.h`** · [→ Medium findings](../medium.md#m5)

Line 291:

```objc
[[NSNotificationCenter defaultCenter] postNotificationName:@"SRProfileUpdatedNotification"
                                                    object:author];
```

This is the only notification name in the UI layer that is not declared as a constant. Any observer that registers for this notification must also use the raw string, with no compile-time safety. Add to `SRNotificationNames.h`:

```objc
extern NSString * const SRProfileUpdatedNotification;
```

And define it in `SRNotificationNames.m`.

---

## N4

**Emoji in log calls** · [→ Minor findings](../minor.md#n4)

`loadFeedForAuthor:client:` (lines 248–346) uses `SSBLogInfo`, `SSBLogError`, and `SSBLogWarning` with emoji prefixes:

```objc
SSBLogInfo(SSBLogCategoryUI, @"📥 loadFeedForAuthor: ...");
SSBLogError(SSBLogCategoryUI, @"   ❌ No client provided!");
SSBLogInfo(SSBLogCategoryUI, @"   ✅ Profile fetched: %@", response);
SSBLogWarning(SSBLogCategoryUI, @"   ⚠️ No profile response");
```

These work fine during development but make log grepping awkward in production (`log stream --predicate` on the command line does not handle emoji well). Replace with plain-text log messages.

---

## Other Observations

**Cell size calculation uses hardcoded arithmetic tied to layout constants**

`sizeForItemAtIndexPath:` (lines 381–413) computes cell width as `collectionView.bounds.size.width - 80` with a comment saying "20 section inset * 2 + cell padding". The actual section inset is `[SRStyle spacingXL]`, which may not be 20pt. If `spacingXL` changes, the size calculation will be wrong. Compute the padding from the actual inset value.

**`SRFeedShortcutReply` and `SRFeedShortcutOpen` handled identically**

In `keyDown:` (lines 447–450), both shortcuts call `didSelectMessageThread:`. If these are intended to do different things (e.g. open vs. inline reply), the routing should be separated. If they are intentionally the same, consider collapsing the condition.
