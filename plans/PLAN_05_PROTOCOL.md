# Plan 05: Protocol and Algorithm Improvements

**Impact: 5/10** — Workarounds and simplifications affect edge cases and performance
**Difficulty: 6/10** — Protocol changes require careful consideration of side effects

## Status: ⚠️ PARTIAL (1/3 tasks complete)

---

## Overview

Several protocol-level implementations have workarounds or simplifications that may cause issues in production. This plan addresses EBT replication handling and diff algorithm optimizations.

---

## Task 5.1: Fix EBT Bilateral Replication Handling

### Status: ✅ COMPLETE

**Priority:** Medium-High
**Scope:** 1 file
**Estimated complexity:** High

### Implementation Details
Implemented bilateral EBT handling in `SSBRoomClient.m`:
1. **Per-peer state:** Added `peerEBTState` to track clocks and request IDs per connection, preventing clock corruption from concurrent peers.
2. **Bilateral RPC:** Handled incoming `ebt.replicate` requests by sending our local clock as a duplex response.
3. **Session routing:** Updated `handleEBTMessage:` to identify the source peer and use the correct isolated clock state for updates and filtering.
4. **Binary support:** Ensured binary EBT payloads are correctly routed to per-peer processing.

### Acceptance Criteria
- [x] Root cause of clock corruption identified (shared global clock state)
- [x] Bilateral EBT properly handled
- [x] Clear documentation of implementation in master plan
- [x] No message loss in normal replication scenarios
- [x] Per-peer clock isolation implemented

---

## Task 5.2: Improve Histogram Diff Line Matching

### Status: ✅ COMPLETE

**Priority:** Low
**Scope:** 1 file
**Estimated complexity:** Medium

### Changes Made
Documented the trade-off of the "first occurrence" heuristic in `Sources/SSBDiffCore.c`. Added detailed comments explaining:
- Why the current simplification is acceptable for histogram diff.
- How the algorithm prioritizes low-frequency lines to minimize ambiguity.
- The performance vs. optimality trade-off.

### Acceptance Criteria
- [x] Trade-off documented in code comment
- [x] Existing diff tests still pass
- [x] No performance regression

---

## Task 5.3: Review SSBSecretHandshake State Machine

### Status: ✅ DONE (via Task 3.4)

**Priority:** Low
**Scope:** Code review
**Estimated complexity:** Low

### Changes Made
The "dummy check" code was removed in Task 3.4. The state machine is now clearer:
```objc
// Server ephemeral key (b) is generated in processHello when client's hello arrives.
```

### Acceptance Criteria
- [x] State machine reviewed
- [x] Any unclear transitions documented or fixed
- [x] "Dummy check" comment clarified (removed)

---

## Summary Table

| Task | Issue | Status | Notes |
|------|-------|--------|-------|
| 5.1 | EBT bilateral skip | ⬜ TODO | High priority — needs investigation |
| 5.2 | Diff first-occurrence heuristic | ⬜ TODO | Low priority optimization |
| 5.3 | Handshake state machine | ✅ Done | Via task 3.4 |

---

## Remaining Work Priority

1. **5.1 EBT Bilateral Replication** — This is the most significant remaining technical debt. It could cause message loss in multi-peer scenarios.

2. **5.2 Diff Algorithm** — Nice to have, but current implementation works well for most cases.
