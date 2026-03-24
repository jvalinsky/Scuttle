# SRComposeViewController.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRComposeViewController.m`
**Findings:** [M1](#m1) [M2](#m2)

---

## M1

**`keyEquivalent` and `keyEquivalentModifierMask` set twice** · [→ Medium findings](../medium.md#m1)

Lines 173–177 in `setupUI`:

```objc
self.publishButton.keyEquivalent = @"\r";                                  // line 173
self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand; // line 174
self.publishButton.keyEquivalent = @"\r"; // ← duplicate                  // line 176
self.publishButton.keyEquivalentModifierMask = NSEventModifierFlagCommand; // line 177
```

Lines 176–177 are identical to 173–174 and have no effect. This appears to be a copy-paste error. Remove lines 176–177.

---

## M2

**Success banner shown before publish is confirmed** · [→ Medium findings](../medium.md#m2)

Lines 231–244 in `publishAction:`:

```objc
- (void)publishAction:(id)sender {
    NSString *text = [self.textView.string copy];
    NSString *cw = self.cwField.stringValue;
    if (text.length == 0) return;

    if (self.onPublish) {
        self.onPublish(text, cw.length > 0 ? cw : nil, self.replyToKey);
    }

    // ← always shown, regardless of publish outcome
    [SRNotificationBannerView showInView:self.view.window.contentView
                                 message:NSLocalizedString(@"Message published successfully!", nil)
                                    type:SRNotificationTypeSuccess];
    [self clear];
}
```

`onPublish` is a block with signature `void(^)(NSString *text, NSString *cw, NSString *replyKey)` — it has no success/failure return. The banner fires unconditionally. If the downstream publish operation fails (network error, not connected, etc.), the user sees false confirmation.

**Recommended fix:** Update `onPublish` to accept a completion callback, or expose a separate `onPublishResult` block that the caller fires with success/failure. Only show the success banner on confirmed success; show an error banner on failure via `SRNotificationTypeError`.

---

## Other Observations

**`setReplyToKey:` dispatches to main queue unnecessarily**

Lines 74–79: `setReplyToKey:` wraps UI updates in `dispatch_async(dispatch_get_main_queue(), ...)`. The callers (e.g., `SRMainSplitViewController`) call this from the main thread already. The dispatch is defensive but adds unnecessary indirection, and the method captures `replyToKey` by value in the block rather than using `_replyToKey`, which means the block reads the parameter not the ivar — a subtle correctness issue if `setReplyToKey:` is called again before the block executes.

**`clear` calls `textDidChange:` with a synthetic notification**

Line 252: `[self textDidChange:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:self.textView]]`. The notification name passed is `NSTextViewDidChangeSelectionNotification`, not the text-changed notification, which is inconsistent. Since `textDidChange:` only looks at `self.textView.string`, the notification content doesn't matter functionally — but it's misleading. Call the character-count update logic directly instead of constructing a fake notification.
