# Code Review — 2026-03-22

Scope: 16 files modified on the `main` branch prior to this review.

## Files Reviewed

| File | Issues |
|------|--------|
| [AppDelegate.m](files/AppDelegate.md) | 2 high |
| [SRRoomManager.m](files/SRRoomManager.md) | 1 critical, 1 medium |
| [SRFeedViewController.m](files/SRFeedViewController.md) | 1 critical, 2 medium |
| [SRSidebarViewController.m](files/SRSidebarViewController.md) | 1 high, 2 medium |
| [SRPeerListViewController.m](files/SRPeerListViewController.md) | 1 high, 1 minor |
| [SRComposeViewController.m](files/SRComposeViewController.md) | 2 medium |
| [SRPreferencesViewController.m](files/SRPreferencesViewController.md) | 1 high, 2 minor |
| [SRNotificationBannerView.m](files/SRNotificationBannerView.md) | — (notes only) |

## Findings by Severity

- [Critical](critical.md) — 2 findings. Fix before merge.
- [High](high.md) — 5 findings. Fix before shipping.
- [Medium](medium.md) — 6 findings. Fix in follow-up PR.
- [Minor](minor.md) — 4 findings. Address at your discretion.

## Summary Table

| # | Severity | File | Issue |
|---|----------|------|-------|
| C1 | **Critical** | [SRFeedViewController](files/SRFeedViewController.md#c1) | nil guard fires after strongSelf access — potential crash |
| C2 | **Critical** | [SRRoomManager](files/SRRoomManager.md#c2) | `internalClients` read outside `managerQueue` — data race |
| H1 | High | [AppDelegate](files/AppDelegate.md#h1) | no-op `@try/@catch` re-throws exception |
| H2 | High | [AppDelegate](files/AppDelegate.md#h2) | window brought to front 6 times redundantly |
| H3 | High | [SRSidebarViewController](files/SRSidebarViewController.md#h3) | missing `dealloc` — notification observers never removed |
| H4 | High | [SRPreferencesViewController](files/SRPreferencesViewController.md#h4) | `NSWindow` created without owner — leaked orphan window |
| H5 | High | [SRPeerListViewController](files/SRPeerListViewController.md#h5) | debug log inside `numberOfRowsInTableView:` (hot path) |
| M1 | Medium | [SRComposeViewController](files/SRComposeViewController.md#m1) | `keyEquivalent` and `keyEquivalentModifierMask` set twice |
| M2 | Medium | [SRComposeViewController](files/SRComposeViewController.md#m2) | success banner shown before confirming publish succeeded |
| M3 | Medium | [SRSidebarViewController](files/SRSidebarViewController.md#m3) | DB query on main thread in `loadGitRepos` |
| M4 | Medium | [SRSidebarViewController](files/SRSidebarViewController.md#m4) | strong `self` capture in `joinRoomAction:` completion |
| M5 | Medium | [SRFeedViewController](files/SRFeedViewController.md#m5) | hardcoded notification name string not in `SRNotificationNames.h` |
| M6 | Medium | [SRRoomManager](files/SRRoomManager.md#m6) | error domain as inline literal string (repeated 6×) |
| N1 | Minor | [SRPreferencesViewController](files/SRPreferencesViewController.md#n1) | strong `self` in `rotateFeedKeyAction:` completion |
| N2 | Minor | [SRPreferencesViewController](files/SRPreferencesViewController.md#n2) | sort comparator duplicated in `SRStorageUsageView` |
| N3 | Minor | [SRPeerListViewController](files/SRPeerListViewController.md#n3) | full peer array logged at INFO level on every update |
| N4 | Minor | [SRFeedViewController](files/SRFeedViewController.md#n4) | emoji in `SSBLogError` calls |
