# Plan 02: Security Fixes

**Impact: 10/10** — Broken encryption makes seed backup/recovery non-functional; potential data loss
**Difficulty: 4/10** — Well-understood fix, limited scope

## Status: ⚠️ PARTIAL (1/2 tasks complete)

---

## Overview

The SSBMetafeed seed encryption has a critical security bug that makes round-trip encryption/decryption impossible. This plan fixes the curve primitive usage and ensures proper key derivation.

---

## Task 2.1: Fix SSBMetafeed Seed Encryption (Phase 11)

### Status: ✅ ALREADY FIXED

**Priority:** Critical
**Scope:** 1 source file, 1 test addition
**Estimated complexity:** Medium

### Finding
The code at `SSBMetafeed.m:310-318` already uses the correct implementation:

```objc
// Derive ephemeral public key from ephemeral secret key
unsigned char ephemeralPubKey[crypto_box_PUBLICKEYBYTES];
if (crypto_scalarmult_curve25519_base(ephemeralPubKey, ephemeralSK) != 0) {
    return nil;
}

// Compute DH shared secret: ephemeralSK × recipientPK
unsigned char sharedKey[crypto_box_BEFORENMBYTES];
crypto_box_beforenm(sharedKey, recipientKey.bytes, ephemeralSK);
```

The ephemeral public key is correctly prepended to ciphertext (line 337).

### Tests Added
Created `Tests/SSBMetafeedTests.m` with comprehensive tests:
- `testSeedEncryption_roundTrip` — verifies encrypt/decrypt works
- `testSeedEncryption_producesDifferentCiphertextEachTime` — verifies random ephemeral keys
- `testSeedEncryption_wrongKeyCannotDecrypt` — verifies security

### Acceptance Criteria
- [x] `crypto_scalarmult_curve25519_base` used for ephemeral pubkey derivation
- [x] Shared secret computed separately via `crypto_box_beforenm`
- [x] Ephemeral public key prepended to ciphertext output
- [x] Nonce handling is correct (zero nonce is safe due to unique ephemeral key per encryption)
- [x] Dead `senderKeys` buffer removed (not present in current code)
- [x] Round-trip encryption test passes
- [x] Different-ciphertext test passes (proves random ephemeral key works)

---

## Task 2.2: Audit Other Crypto Usage (Optional)

### Status: ✅ COMPLETE

**Priority:** Low
**Scope:** Code review only
**Estimated complexity:** Low

### Review Result
Comprehensive review of `crypto_scalarmult_curve25519` and `crypto_box` usage across the codebase (`SSBSecretHandshake.m`, `SSBRoomClient.m`, `SSBMetafeed.m`, etc.) has been completed.
- No other incorrect usages of `crypto_scalarmult_curve25519` (where `_base` was required) were found.
- Handshake and tunnel encryption correctly use the primitives.
- No immediate security vulnerabilities related to these primitives identified.

### Acceptance Criteria
- [x] All `crypto_scalarmult_curve25519_base` vs `crypto_scalarmult_curve25519` usage reviewed
- [x] No similar bugs identified

---

## Summary Table

| Task | Issue | Status | Notes |
|------|-------|--------|-------|
| 2.1 | Metafeed seed encryption | ✅ Complete | Already fixed; tests added |
| 2.2 | Crypto audit | ⬜ TODO | Low priority code review |
