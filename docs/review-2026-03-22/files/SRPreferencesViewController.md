# SRPreferencesViewController.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRPreferencesViewController.m`
**Findings:** [H4](#h4) [N1](#n1) [N2](#n2)

---

## H4

**`NSWindow` created without an owner — leaked orphan window** · [→ High findings](../high.md#h4)

Lines 427–436 in `showDevPanelAction:`:

```objc
- (void)showDevPanelAction:(id)sender {
    Class devPanelClass = NSClassFromString(@"SRDevPanelViewController");
    if (devPanelClass) {
        NSViewController *vc = [[devPanelClass alloc] init];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                       styleMask:...
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Developer Panel";
        window.releasedWhenClosed = NO;
        window.contentViewController = vc;
        [window makeKeyAndOrderFront:nil];
        // window falls out of scope here — no owner retains it
    }
}
```

With `releasedWhenClosed = NO`, AppKit does not release the window when it is closed, which means the window cannot be deallocated via normal close gestures. Nothing in the app holds a strong reference to it. The result:

1. If the user closes the dev panel, the window object leaks (it's referenced only by the window server).
2. If the user invokes "Show Developer Panel" multiple times, a new orphan window is created each time.

**Fix:** Store the window in a property or use `NSWindowController`:

```objc
@property (nonatomic, strong) NSWindowController *devPanelWindowController;

- (void)showDevPanelAction:(id)sender {
    if (!self.devPanelWindowController) {
        Class devPanelClass = NSClassFromString(@"SRDevPanelViewController");
        if (!devPanelClass) return;
        NSViewController *vc = [[devPanelClass alloc] init];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Developer Panel";
        window.contentViewController = vc;
        self.devPanelWindowController = [[NSWindowController alloc] initWithWindow:window];
    }
    [self.devPanelWindowController showWindow:nil];
}
```

---

## N1

**Strong `self` in `rotateFeedKeyAction:` completion** · [→ Minor findings](../minor.md#n1)

Lines 403–419. The completion block passed to `replaceSubfeed:completion:` captures `self` strongly:

```objc
[[SRRoomManager sharedManager] replaceSubfeed:classicFeedID
                                   completion:^(NSString *newFeedID, NSError *error) {
    self.rotateFeedKeyButton.enabled = YES;    // ← strong self
    if (error) {
        NSAlert *errAlert = ...
        [errAlert runModal];
    } else {
        NSAlert *ok = ...
        [ok runModal];
    }
}];
```

Key rotation is an asynchronous network operation. If the preferences sheet is dismissed while it is in progress, `self` stays alive until the completion fires. UI elements updated in the completion (`rotateFeedKeyButton`) belong to a dismissed sheet.

The retain keeps `self` alive, which is arguably acceptable to ensure the completion runs fully. But it also keeps all of the preferences VC's resources alive (profile header view, multiple NSButtons, storage view). Use `weakSelf/strongSelf` and bail early if the VC is gone.

---

## N2

**Sort comparator duplicated in `SRStorageUsageView`** · [→ Minor findings](../minor.md#n2)

The same author-sort-by-total-message-count comparator block appears in both `drawRect:` (lines 84–88) and `mouseMoved:` (lines 39–43):

```objc
NSArray *sortedAuthors = [self.stats.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    long long countA = 0; for (NSNumber *n in self.stats[a].allValues) countA += n.longLongValue;
    long long countB = 0; for (NSNumber *n in self.stats[b].allValues) countB += n.longLongValue;
    return [@(countB) compare:@(countA)];
}];
```

This is also computed on every `drawRect:` call, which includes every resize and dirty-rect repaint. Extract to a lazy cached property or a `-sortedAuthors` helper, and invalidate the cache when `stats` is set.

---

## Other Observations

**`loadIdentity` extracts public key by byte offset instead of using `SSBPublicIDFromSecret`**

Lines 307–312:

```objc
NSData *localSecret = SSBLoadIdentitySecret();
if (localSecret && localSecret.length >= 64) {
    NSData *pkData = [localSecret subdataWithRange:NSMakeRange(32, 32)];
    NSString *pubkey = [NSString stringWithFormat:@"@%@.ed25519",
                        [pkData base64EncodedStringWithOptions:0]];
    [self.headerView updateWithIdentity:pubkey name:nil];
}
```

`saveAction:` (line 324) uses `SSBPublicIDFromSecret(localSecret)` to derive the same string. `loadIdentity` should use the same helper rather than manually offsetting into the secret bytes.

**`NSClassFromString` for dev panel is a code smell**

Using `NSClassFromString(@"SRDevPanelViewController")` means the class can be silently removed or renamed with no compile-time error. If the dev panel is always included in the build, import its header directly. If it is conditionally compiled, use `#ifdef DEBUG` or a build configuration flag rather than runtime class lookup.
