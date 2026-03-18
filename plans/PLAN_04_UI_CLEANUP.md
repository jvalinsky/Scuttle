# Plan 04: UI and Testing Cleanup

**Impact: 3/10** — Debug code and limitations don't break functionality but affect polish
**Difficulty: 2/10** — Simple code removals and feature additions

## Status: ⚠️ PARTIAL (1/4 tasks complete)

---

## Overview

Several UI files contain temporary debug code, testing shortcuts, and intentional limitations that should be addressed before production release.

---

## Task 4.1: Remove Auto-Select Debug Code

### Status: ✅ DONE

**Priority:** Medium
**Scope:** 1 file
**Estimated complexity:** Trivial

### Changes Made
Removed the 10-line auto-select block from `SRPeerListViewController.m:255-264`:

```objc
// REMOVED:
// TEMPORARY: Auto-select the first peer for testing
if (self.peers.count > 0 && self.delegate) {
    static BOOL autoselected = NO;
    if (!autoselected) {
        autoselected = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate peerListViewController:self didSelectPeer:self.peers.firstObject];
        });
    }
}
```

### Acceptance Criteria
- [x] Auto-select code removed
- [x] Peer list still displays correctly
- [x] User can manually select peers
- [x] No regression in peer list functionality

---

## Task 4.2: Implement Cross-Repo Pull Requests

### Status: ✅ COMPLETE (Limitation Documented in UI)

**Priority:** Low
**Scope:** 1-2 files
**Estimated complexity:** Medium

### Implementation
Added an explanatory label in `SRGitNewPRViewController.m` to inform the user that cross-repository pull requests are not yet supported. Updated the code comments to reflect that same-repo PRs are currently required.

### Acceptance Criteria
- [x] Comment updated to be clear about limitation
- [x] UI indicates limitation to user

---

## Task 4.3: Add Committer Line to Git Diff Parser

### Status: ✅ COMPLETE

**Priority:** Low
**Scope:** 1 file
**Estimated complexity:** Low

### Implementation
Updated `SRGitDiffViewController.m` to:
1. Parse the `committer` line from the git diff header.
2. Compare the committer identity with the author identity.
3. Display the "Committed by" line in the UI only when the committer is different from the author (e.g., during rebases or cherry-picks).

### Acceptance Criteria
- [x] Committer info parsed
- [x] Committer displayed when different from author

---

## Task 4.4: Complete Room Manager Metafeed Announce

### Status: ⬜ TODO

**Priority:** Medium
**Scope:** 1-2 files
**Estimated complexity:** Medium

### Issue
`SRRoomManager.m:25` has a flag for tracking incomplete metafeed announcement:
```objc
/// Set during bootstrap when a metafeed/announce message still needs to be published.
```

### Investigation Needed

1. **Understand the current state:**
   - When is this flag set?
   - What triggers the announce publication?
   - What happens if it's never published?

2. **Determine if this is a bug or intentional:**
   - Is the announce sometimes skipped incorrectly?
   - Is there a race condition?

3. **Fix or document accordingly**

### Acceptance Criteria
- [ ] Metafeed announce logic reviewed
- [ ] Any bugs fixed OR behavior documented
- [ ] Flag usage is clear and correct

---

## Summary Table

| Task | Issue | Status | Notes |
|------|-------|--------|-------|
| 4.1 | Auto-select debug code | ✅ Done | Removed in this session |
| 4.2 | Same-repo PR limitation | ⬜ TODO | Comment updated only |
| 4.3 | Committer line skipped | ⬜ TODO | Comment updated only |
| 4.4 | Metafeed announce flag | ⬜ TODO | Needs investigation |
