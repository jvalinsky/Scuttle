# Plan 03: Spec Compliance Fixes

**Impact: 6/10** — Non-standard implementations may cause interoperability issues with other SSB clients
**Difficulty: 5/10** — Clear spec references, moderate code changes

## Status: ✅ COMPLETE (4/4 tasks)

---

## Overview

Several codec implementations deviate from their specifications in ways that could cause interoperability issues. This plan addresses entry ID format, protobuf forward compatibility, and other spec deltas.

---

## Task 3.1: Fix Bamboo Entry ID Format (Phase 12)

### Status: ✅ ALREADY CORRECT

**Priority:** Medium
**Scope:** 1 source file, 1 test file, 1 doc file
**Estimated complexity:** Medium

### Finding
The code at `SSBBamboo.m:241-247` already returns the correct 32-byte hash:

```objc
+ (nullable NSData *)computeEntryID:(NSData *)entryData {
    if (!entryData || entryData.length < kBambooMinSize) {
        return nil;
    }
    // Spec: entry ID = BLAKE2b-256 of the full entry bytes (32 bytes)
    return [self hashData:entryData];
}
```

### Acceptance Criteria
- [x] `computeEntryID:` returns 32 bytes
- [x] Entry ID equals `BLAKE2b-256(fullEntryBytes)`
- [x] Header comment updated
- [x] All Bamboo tests pass
- [x] FEED_FORMAT_REPORT.md updated

---

## Task 3.2: GabbyGrove Forward Compatibility (Phase 13)

### Status: ✅ ALREADY IMPLEMENTED

**Priority:** Low-Medium
**Scope:** 1 source file, 1 test addition
**Estimated complexity:** Low

### Finding
The code at `SSBGabbyGrove.m:222-233` already handles wire types 1 and 5:

```objc
} else if (wireType == kWireType64Bit) {
    // 64-bit fixed field (wire type 1) — skip 8 bytes
    if (offset + 8 > length) return NO;
    offset += 8;
} else if (wireType == kWireType32Bit) {
    // 32-bit fixed field (wire type 5) — skip 4 bytes
    if (offset + 4 > length) return NO;
    offset += 4;
} else {
    // Wire types 3, 4, 6, 7 are deprecated/reserved — treat as parse failure
    return NO;
}
```

### Acceptance Criteria
- [x] Wire type 1 (64-bit) skips 8 bytes and continues parsing
- [x] Wire type 5 (32-bit) skips 4 bytes and continues parsing
- [x] Wire types 3, 4, 6, 7 still return NO
- [x] Forward compatibility tests pass
- [x] Existing GabbyGrove tests still pass

---

## Task 3.3: Clean Up Bamboo Lipmaa Comments

### Status: ✅ DONE

**Priority:** Low
**Scope:** 1 file
**Estimated complexity:** Trivial

### Changes Made
Replaced the confusing multi-line comment block with:
```objc
// Lipmaa link calculation per Bamboo spec.
// Find the largest power of 3 strictly less than seq, then subtract.
// This provides O(log n) skip-list traversal for feed verification.
```

### Acceptance Criteria
- [x] Comment clearly explains the purpose
- [x] No misleading "should be?" or "hmm" notes
- [x] Reference to spec or reference implementation included

---

## Task 3.4: Fix SSBSecretHandshake Dummy Check Comment

### Status: ✅ DONE

**Priority:** Low
**Scope:** 1 file
**Estimated complexity:** Trivial

### Changes Made
Removed the useless code block and replaced with clear comment:
```objc
// Before:
if (NSData.data.length == 0) { // Check if already generated
     // Dummy check for clarity, b should be generated in processHello
}

// After:
// Server ephemeral key (b) is generated in processHello when client's hello arrives.
```

### Acceptance Criteria
- [x] Comment is clear and accurate
- [x] No "dummy" terminology
- [x] Useless code removed

---

## Summary Table

| Task | Issue | Status | Notes |
|------|-------|--------|-------|
| 3.1 | Bamboo entry ID 96→32 bytes | ✅ Complete | Already returns 32 bytes |
| 3.2 | GabbyGrove wire type handling | ✅ Complete | Already handles types 1 & 5 |
| 3.3 | Lipmaa comment cleanup | ✅ Done | Cleaned up in this session |
| 3.4 | Handshake comment cleanup | ✅ Done | Removed dummy check code |
