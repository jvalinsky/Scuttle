# Plan 07: Linux Cryptography Compatibility (CommonCrypto Shim)

**Impact: 9/10** — Critical for protocol operation (Handshake/Hashing) on Linux.
**Difficulty: 5/10** — Requires mapping CommonCrypto function signatures to OpenSSL.

---

## Overview

The codebase uses `CommonCrypto` for SHA-256 and HMAC-SHA256. These are essential for the Secret Handshake (SHS) and message integrity. We will create a compatibility header that maps `CC_SHA256` and `CCHmac` to the OpenSSL `libcrypto` equivalents.

---

## Task 7.1: Create SSBCommonCryptoCompat.h

### Status: ⏳ PENDING

**Priority:** High
**Scope:** 1 new header file
**Estimated complexity:** Medium

### Subtasks
- [ ] Define `SSBCommonCryptoCompat.h` in `Sources/`.
- [ ] Add `#ifdef __APPLE__` guard to include `<CommonCrypto/CommonCrypto.h>`.
- [ ] For non-Apple platforms:
    - [ ] Include `<openssl/sha.h>` and `<openssl/hmac.h>`.
    - [ ] Define `CC_LONG` as `unsigned int`.
    - [ ] Implement `static inline` wrapper for `CC_SHA256`.
    - [ ] Implement `static inline` wrapper for `CCHmac` supporting `kCCHmacAlgSHA256`.

### Acceptance Criteria
- [ ] Header maps signatures exactly to avoid changing call sites in `SSBSecretHandshake.m`.
- [ ] Handshake code compiles without warnings on both platforms.

---

## Task 7.2: Update Secret Handshake Implementation

### Status: ⏳ PENDING

**Priority:** High
**Scope:** `Sources/SSBSecretHandshake.m`
**Estimated complexity:** Low

### Subtasks
- [ ] Replace `#import <CommonCrypto/CommonCrypto.h>` with `#import "SSBCommonCryptoCompat.h"`.
- [ ] Ensure all `CC_SHA256` calls match the new shim's signature.

### Acceptance Criteria
- [ ] `SSBSecretHandshake.m` compiles on macOS.
- [ ] `SSBSecretHandshakeTests` pass on macOS (confirming no regression).

---

## Task 7.3: Linux Build Configuration (Crypto)

### Status: ⏳ PENDING

**Priority:** Medium
**Scope:** Build scripts
**Estimated complexity:** Low

### Subtasks
- [ ] Add `pkg-config --libs libcrypto` (or equivalent) to the Linux build instructions.
- [ ] Ensure OpenSSL headers are in the include path for Linux builds.

---

## Summary Table

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| 7.1 | Create SSBCommonCryptoCompat.h | ⏳ Pending | OpenSSL mapping layer |
| 7.2 | Update SHS Implementation | ⏳ Pending | Swap imports in SSBSecretHandshake.m |
| 7.3 | Linux Build Config | ⏳ Pending | Link against libcrypto |
