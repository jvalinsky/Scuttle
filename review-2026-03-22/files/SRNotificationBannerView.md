# SRNotificationBannerView.m — Review Notes

[← Index](../index.md)

**Path:** `App/UI/SRNotificationBannerView.m`
**Findings:** None (observations only)

---

## Observations

**`animateIn` retain cycle is intentional but worth noting**

`animateIn` (lines 113–123) captures `self` strongly in a `dispatch_after` block that fires 3 seconds later to call `animateOut`. During those 3 seconds:

1. The banner is a subview of the window content view (strong reference from superview).
2. The `dispatch_after` block holds a second strong reference.

When `animateOut` completes, the completion handler calls `[self removeFromSuperview]` which drops the superview reference. The `dispatch_after` block reference drops naturally when it finishes. The retain cycle resolves cleanly.

This is correct, but it means `SRNotificationBannerView` instances are always retained for at least 3.25 seconds after appearing, regardless of whether the parent view is removed. If banners accumulate (e.g., rapid publish actions), multiple banners will be alive simultaneously. The current layout pins each banner to the same `topAnchor` constant so simultaneous banners will overlap exactly. Consider offsetting stacked banners or cancelling an existing banner before showing a new one.

**`showInView:` dispatches to main queue unconditionally**

Line 14: `dispatch_async(dispatch_get_main_queue(), ...)`. All current call sites are already on the main thread. The dispatch adds a frame of latency before the banner appears. If it is intended as a safety net for off-thread callers, add an assertion that call sites use it correctly rather than silently deferring.

**`_applyBorderColor` called redundantly on `initWithFrame:` before `wantsLayer = YES`**

Line 43 calls `[self _applyBorderColor]` inside `initWithFrame:`, which sets `self.layer.borderColor`. At that point `wantsLayer` has just been set to `YES` on line 39. This should be fine as `wantsLayer = YES` triggers layer creation, but it precedes the `setupUI` call on line 45. The ordering is fragile; consider moving `_applyBorderColor` to after `setupUI` for clarity.
