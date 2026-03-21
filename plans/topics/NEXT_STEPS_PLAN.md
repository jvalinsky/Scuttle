# Next Steps Plan — SSBNetwork Feed Codec Work

## Current State (as of commit `ebb7998`)

Branch: `claude/review-objc-macos-patterns-8cw3p`

**Completed:**
- All 22 ObjC pattern issues verified fixed
- Multi-format feed codecs (Phases 1-7): SSBGabbyGrove, SSBBamboo, SSBButtwoo, SSBBendyButt, SSBIndexFeed
- Test suite (Phase 8): GabbyGrove, Buttwoo, Bamboo, BendyButt, FeedCodecRegistry
- BLAKE2b-256 implementation bundled + applied to 4 codecs (Phase 9)
- Feed format report with code review + app suitability analysis

**Remaining issues (prioritized):**

---

## ✅ Phase 10 — Verify BendyButt Hash Algorithm (1 file, quick)

**Issue:** Research indicates `ssbc/bendy-butt-spec` defines message IDs as SHA-256 of the
bencoded `[payload, signature]` bytes — not BLAKE2b-256. Phase 9 applied BLAKE2b-256
uniformly; if the spec really is SHA-256 here, we need to revert.

**Work:**
1. Fetch `ssbc/bendy-butt-spec` README / spec document (web fetch)
2. If SHA-256: revert `SSBBendyButt.m computeMessageKey:` to `CC_SHA256`; remove `blake2b.h`
   import from that file; update any tests that check BendyButt message key length/value
3. If BLAKE2b: no change needed; add a comment citing the spec line

**Scope:** 1 source file, 1 test file (SSBBendyButtTests if it exists, or add a test).

---

## ✅ Phase 11 — Fix SSBMetafeed Seed Encryption (1 file)

**Issue:** The nonce bug (zero nonce) was already fixed — `SecRandomCopyBytes` is in place.
The remaining bug is the wrong curve primitive:

```objc
// Line 321 — WRONG: computes DH(ephemeral_sk, recipient_pk) = shared secret
crypto_scalarmult_curve25519(ephemeralPubKey, ephemeralKeys.bytes, recipientKey.bytes);

// CORRECT: derives ephemeral public key from ephemeral secret key
crypto_scalarmult_curve25519_base(ephemeralPubKey, ephemeralKeys.bytes);
```

The ephemeral *public key* must then be prepended to the ciphertext so the recipient can
reconstruct the DH shared secret. The current implementation stores a shared secret where the
public key should go, making round-trip decryption impossible.

**Work:**
1. Replace the `crypto_scalarmult_curve25519` call with `crypto_scalarmult_curve25519_base`
2. Compute the actual shared secret separately:
   `crypto_scalarmult_curve25519(sharedSecret, ephemeralSK, recipientPK)`
3. Use shared secret as the key for `crypto_secretbox_xsalsa20poly1305`
4. Prepend ephemeral public key (32 bytes) to the ciphertext so decryptor can reconstruct
5. Remove the unused 96-byte `senderKeys` buffer (dead code)
6. Add/update a round-trip encryption test

**Scope:** 1 source file (`SSBMetafeed.m`), 1 test addition.

---

## ✅ Phase 12 — Fix Bamboo Entry ID (1 file)

**Issue:** `computeEntryID:` returns 96 bytes (BLAKE2b(first 32 bytes of entry) ‖ signature).
The Bamboo reference implementation defines an entry ID as **BLAKE2b-256 of the full entry
bytes** — a clean 32-byte value. The 96-byte design is non-standard and incompatible.

**Work:**
1. Replace `computeEntryID:` body with `return [self hashData:entryData]` — BLAKE2b-256
   of the complete entry (all bytes including signature)
2. Update `SSBBamboo.h` header comment (says "64 bytes" → "32 bytes")
3. Update `SSBBambooTests.m`:
   - `testComputeEntryID_validEntry_returns96Bytes` → `returns32Bytes`, assert `length == 32`
   - `testComputeEntryID_structure` → verify the 32-byte ID equals `[SSBBamboo hashData:entryData]`
   - Remove the "first 32 bytes = hash of author" assertion (no longer applicable)
4. Update any comments in `FEED_FORMAT_REPORT.md` that mention 96 bytes

**Scope:** 1 source file, 1 test file, 1 doc file.

---

## ✅ Phase 13 — GabbyGrove Forward Compatibility (1 file)

**Issue:** The protobuf parser returns `NO` for any unknown wire type. Protobuf's extensibility
contract requires that parsers skip fields with unknown wire types they can handle, and fail
only on truly undecodable wire types.

**Protobuf wire types:**
- `0` = varint — handled ✅
- `1` = 64-bit fixed — **not handled** (skip 8 bytes)
- `2` = length-delimited — handled ✅
- `3` = start group — deprecated, safe to skip with end-group matching
- `4` = end group — deprecated
- `5` = 32-bit fixed — **not handled** (skip 4 bytes)
- `6`, `7` — reserved, safe to fail on

**Work:**
1. Add cases for wire types 1 (skip 8 bytes) and 5 (skip 4 bytes) in `parseMessage`
2. Keep `return NO` only for types 3, 4, 6, 7 (undecodable without special handling)
3. Add tests: a message with an unknown `type=1` or `type=5` field before the signature
   should still validate correctly

**Scope:** 1 source file (`SSBGabbyGrove.m`), 1 test addition.

---

## ✅ Phase 14 — BLAKE3 for Buttwoo (optional / lower priority)

**Issue:** The Buttwoo spec uses BLAKE3 for message IDs. Phase 9 used BLAKE2b-256 as an
approximation. BLAKE3 is not available in CommonCrypto or tweetnacl; a minimal implementation
would need to be bundled (similar to how `blake2b.c` was added).

**Options:**
A. Bundle a minimal BLAKE3 implementation (the reference `blake3.c` from `BLAKE3-team/BLAKE3`
   is public domain, ~800 lines of C) and replace BLAKE2b-256 in `SSBButtwoo.m`
B. Document the BLAKE2b-256 approximation as a known delta and defer BLAKE3 until another
   implementation in the ecosystem ships it

**Recommendation:** Option B for now — BLAKE2b-256 is cryptographically stronger than SHA-256
and the Buttwoo format has no production deployments yet, so the interoperability risk is low.
Revisit when `ssbc/ssb-buttwoo` JS implementation ships BLAKE3.

---

## ✅ Phase 15 — BIPF Wire Format for Buttwoo (deferred)

**Issue:** The Buttwoo spec uses BIPF (Binary In-Place Format) encoding, not bencode. The
codebase uses bencode, which matches an older draft of the spec.

**Recommendation:** Defer. BIPF requires a new codec implementation (`SSBbipf.h`/`SSBIPF.m`
would need to be replaced/augmented). This is a larger engineering effort and the format has
no production users yet. Once Buttwoo is closer to production adoption, revisit.

---

## Summary Table

| Phase | Issue | Severity | Scope |
|-------|-------|----------|-------|
| 10 | BendyButt hash: SHA-256 vs BLAKE2b per spec | Medium | 1 file |
| 11 | Metafeed wrong curve primitive (`_base` missing) | High | 1 file |
| 12 | Bamboo entry ID: 96-byte non-standard → 32-byte | Medium | 2 files |
| 13 | GabbyGrove skip unknown wire types | Low | 1 file |
| 14 | Buttwoo BLAKE3 (spec delta) | Low | deferred |
| 15 | Buttwoo BIPF encoding (spec delta) | Low | deferred |

**Recommended order:** 10 → 11 → 12 → 13 (14 and 15 deferred).

Phase 10 informs 11 indirectly (establishes the precedent for spec-exact vs. pragmatic hash
choices). Phase 11 is the only remaining security issue. Phase 12 is a correctness fix with
clear spec reference. Phase 13 is a robustness improvement.
