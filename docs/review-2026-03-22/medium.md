# Medium Priority Findings

[← High](high.md) | [Index](index.md) | [Minor →](minor.md)

These issues are real bugs or structural weaknesses that should be addressed in a follow-up PR.

---

## M1 — `keyEquivalent` set twice in `SRComposeViewController`

**File:** [SRComposeViewController.m](files/SRComposeViewController.md#m1) · line 173–177
**Risk:** Redundant. No functional harm, but implies cut-paste error.

```objc
self.publishButton.keyEquivalent = @"\r";                              // line 173
self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand; // line 174
self.publishButton.keyEquivalent = @"\r"; // ← duplicate              // line 176
self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand; // line 177
```

Remove lines 176–177.

---

## M2 — Success banner shown before publish is confirmed

**File:** [SRComposeViewController.m](files/SRComposeViewController.md#m2) · line 236–244
**Risk:** Incorrect UX. User sees "Message published successfully!" even if `onPublish` fails silently or asynchronously.

```objc
- (void)publishAction:(id)sender {
    NSString *text = [self.textView.string copy];
    if (text.length == 0) return;

    if (self.onPublish) {
        self.onPublish(text, cw, self.replyToKey);  // ← result ignored
    }

    // ← banner shown unconditionally, regardless of publish outcome
    [SRNotificationBannerView showInView:... message:@"Message published successfully!" ...];
    [self clear];
}
```

If `onPublish` is updated to report success/failure (e.g. via a callback), the banner should be gated on actual success. At minimum, only show it if `onPublish` is non-nil and was called.

---

## M3 — DB query on main thread in `loadGitRepos`

**File:** [SRSidebarViewController.m](files/SRSidebarViewController.md#m3) · line 96–101
**Risk:** Main-thread block on database I/O. Called on every `SRNewMessageNotification`, which fires frequently during sync.

```objc
- (void)loadGitRepos {
    self.gitRepos = [[SSBFeedStore sharedStore] messagesOfType:@"git-repo" limit:100];
    // ^ synchronous DB read, main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _rebuildSections];
    });
}
```

Move the store query onto a background queue and dispatch back to main to assign `self.gitRepos` and trigger the rebuild.

---

## M4 — Strong `self` capture in `joinRoomAction:` completion

**File:** [SRSidebarViewController.m](files/SRSidebarViewController.md#m4) · line 668
**Risk:** Retain cycle / delayed deallocation. If the sidebar VC is released before the network operation completes, it stays alive and attempts to update UI.

```objc
[[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.syncProgress stopAnimation:nil];   // ← strong self
        self.syncStatusContainer.hidden = YES;
        ...
    });
}];
```

Use `__weak`/`__strong` dance:

```objc
__weak typeof(self) weakSelf = self;
[[SRRoomManager sharedManager] joinRoomWithInvite:invite completion:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.syncProgress stopAnimation:nil];
        ...
    });
}];
```

---

## M5 — Hardcoded notification name not defined in `SRNotificationNames.h`

**File:** [SRFeedViewController.m](files/SRFeedViewController.md#m5) · line 291
**Risk:** A typo will silently drop the notification. No compiler warning. Not matched against any existing constant.

```objc
[[NSNotificationCenter defaultCenter] postNotificationName:@"SRProfileUpdatedNotification"
                                                    object:author];
```

Every other notification name in this codebase is declared as an `NSString * const` in `SRNotificationNames.h`. Add `SRProfileUpdatedNotification` there and use the constant.

---

## M6 — Error domain as inline literal string (repeated 6×) in `SRRoomManager`

**File:** [SRRoomManager.m](files/SRRoomManager.md#m6)
**Risk:** Typo-prone. Cannot be matched with `isEqualToString:` defensively at call sites.

Occurrences:
- line 107 — `joinRoomWithInvite:`
- line 125 — `joinRoomWithInvite:`
- line 497 — `replaceSubfeed:`
- line 505 — `replaceSubfeed:`
- line 519 — `replaceSubfeed:`
- line 527 — `replaceSubfeed:`

```objc
// Current (fragile):
[NSError errorWithDomain:@"SRRoomManager" code:-1 userInfo:...]

// Fix: declare once
NSString * const SRRoomManagerErrorDomain = @"com.scuttlebutt.SRRoomManager";
```

Use a reverse-DNS style domain (`com.scuttlebutt.SRRoomManager`) consistent with the `os_log` subsystem strings already in use.
