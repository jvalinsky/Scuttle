# Plan 01: Cryptographic Hash Algorithm Fixes

**Impact: 9/10** — Without correct hash algorithms, messages cannot be exchanged with other SSB implementations
**Difficulty: 7/10** — Requires implementing BLAKE3 from scratch (~350 lines C) and verifying specs

## Status: ✅ COMPLETE (4/4 tasks)

All cryptographic hash issues were **already fixed** in the codebase.

---

## Overview

Four codecs have hash algorithm issues that prevent interoperability with the SSB ecosystem. This plan addresses all hash-related placeholders and spec deltas.

---

## Task 1.1: Verify BendyButt Hash Algorithm (Phase 10)

### Status: ✅ ALREADY CORRECT

**Priority:** High
**Scope:** 1 source file, 1 test file
**Estimated complexity:** Low

### Finding
The code at `SSBBendyButt.m:398-401` already uses SHA-256 with a comment citing the spec:
```objc
// Spec: key = SHA256([payload, signature]) — ssbc/bendy-butt-spec
uint8_t digest[CC_SHA256_DIGEST_LENGTH];
CC_SHA256(messageData.bytes, (CC_LONG)messageData.length, digest);
```

### Acceptance Criteria
- [x] Spec document consulted and decision documented
- [x] Hash algorithm matches spec exactly (SHA-256)
- [x] Tests pass with correct expected values
- [x] Comment in code cites spec section

---

## Task 1.2: Implement BLAKE3 for Buttwoo (Phase 14/A)

### Status: ✅ ALREADY IMPLEMENTED

**Priority:** Medium-High
**Scope:** 3 new files, 1 modified file
**Estimated complexity:** High

### Finding
BLAKE3 implementation already exists:
- `Sources/blake3.h` — 40 lines, public API
- `Sources/blake3.c` — 263 lines, full implementation

SSBButtwoo already uses it:
```objc
#import "blake3.h"
// ...
if (blake3_256(digest, input.bytes, input.length) != 0) {
```

### Acceptance Criteria
- [x] BLAKE3 implementation compiles without warnings
- [x] Known-answer test passes against reference implementation
- [x] `SSBButtwoo.m` uses `blake3_256()` for message keys
- [x] Comment in `SSBButtwoo.h` updated (remove "placeholder" note)
- [x] Xcode project includes `blake3.c` in compile sources

---

## Task 1.3: Implement BIPF Wire Format for Buttwoo (Phase 15/B)

### Status: ✅ ALREADY IMPLEMENTED

**Priority:** Medium
**Scope:** 2 files modified
**Estimated complexity:** Medium

### Finding
SSBButtwoo already uses BIPF:
```objc
#import "SSBBIPF.h"
// ...
id decoded = [SSBBIPF decode:messageData consumed:&consumed];
```

### Acceptance Criteria
- [x] All existing Buttwoo tests pass with BIPF encoding
- [x] New round-trip test verifies BIPF decode matches expectations
- [x] No `SSBBencode` imports remain in Buttwoo files

---

## Task 1.4: Fix GabbyGrove SHA-256 Comment (Cleanup)

### Status: ✅ NOT NEEDED

**Priority:** Low
**Scope:** 1 file
**Estimated complexity:** Trivial

### Finding
No stale TODO comment found at `SSBGabbyGrove.m:66`. The code already uses BLAKE2b-256 via `blake2b.h` with correct implementation.

### Acceptance Criteria
- [x] No stale TODO comments about hash algorithm
- [x] Comment accurately describes current implementation

---

## Summary Table

| Task | Issue | Status | Notes |
|------|-------|--------|-------|
| 1.1 | BendyButt hash verification | ✅ Complete | Already uses SHA-256 per spec |
| 1.2 | BLAKE3 implementation | ✅ Complete | Full implementation exists |
| 1.3 | BIPF wire format | ✅ Complete | Already uses SSBBIPF |
| 1.4 | Comment cleanup | ✅ N/A | No stale comments found |
