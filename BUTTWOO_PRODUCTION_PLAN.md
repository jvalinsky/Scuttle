# Buttwoo Production Plan

Two spec deltas block interoperability with any other Buttwoo implementation:

1. **Phase A — BLAKE3 hash** (`blake3.c` + one call-site change)
2. **Phase B — BIPF wire format** (`SSBButtwoo.m` + test helper rewrite)

Both are self-contained. Phase A can ship independently; Phase B is the larger change.
`SSBBIPF.h/m` and `SSBBIPFTests.m` already exist, which cuts Phase B scope considerably.

---

## Phase A — BLAKE3 hash (3 files, ~350 lines of new C)

### Background

`SSBButtwoo.m:82` calls `blake2b256()` as a placeholder. The spec requires BLAKE3-256.
BLAKE3 is not in CommonCrypto or any bundled library; we write it ourselves following
the same pattern as `blake2b.c`.

BLAKE3 structure relevant to Buttwoo (max message size 8192 bytes = up to 8 × 1024-byte chunks):

- **Compression function** — ChaCha-style quarter-rounds with BLAKE3's IV and message schedule
- **Chunk hashing** — each 1024-byte input block processed with CHUNK_START / CHUNK_END flags
- **Merging (parent nodes)** — pairs of 32-byte chaining values combined via compression
  with the PARENT flag; for ≤ 8 chunks this is at most a 3-level binary tree
- **Root finalization** — final compression sets ROOT flag; first 32 bytes of output = digest

For ≤ 1024 bytes (single chunk) the tree degenerates: no merging step, just
CHUNK_START + CHUNK_END + ROOT flags on the single block. This covers the vast majority
of Buttwoo messages in practice.

### Files

#### A1 — `Sources/blake3.h`

```c
int blake3_256(uint8_t out[32], const void *in, size_t inlen);
```

Mirror the `blake2b.h` layout: public-domain header, one function, thread-safe note.

#### A2 — `Sources/blake3.c`

Scalar-only, RFC-style. Sections:

```
1. IV (8 × uint32)                              ~10 lines
2. SIGMA permutation table (7 rows × 16)        ~10 lines
3. Quarter-round G macro                        ~8 lines
4. compress() — one 64-byte block              ~30 lines
5. chunk_state struct + init/update/finalize    ~80 lines
6. hasher struct  + init/update/finalize        ~100 lines
   - update splits input into 1024-byte chunks
   - finalize builds the Merkle tree over up to 8 chunk CVs
     (hard-limit matches kMaxMessageSize = 8192)
7. blake3_256() — top-level wrapper             ~15 lines
```

Total: ~350 lines. No SIMD, no streaming beyond what `hasher_update` needs.

Domain separation flag constants (from the spec):

| Flag name    | Value  |
|-------------|--------|
| CHUNK_START | 1 << 0 |
| CHUNK_END   | 1 << 1 |
| PARENT      | 1 << 2 |
| ROOT        | 1 << 3 |

#### A3 — `Sources/SSBButtwoo.m` (one-line change)

```objc
// Before
#import "blake2b.h"
…
if (blake2b256(digest, input.bytes, input.length) != 0) {

// After
#import "blake3.h"
…
if (blake3_256(digest, input.bytes, input.length) != 0) {
```

Also update the comment in `SSBButtwoo.h:16` to say BLAKE3 (remove "SHA-256 placeholder").

#### A4 — `Tests/SSBButtwooTests.m` — add one known-answer test

Add `testDeterministicKey_knownVector` using a BLAKE3 test vector from the spec:

```
input:  0x00 × 32 (zero author key) || 0x0000000000000001 (seq=1, big-endian)
output: (compute from reference implementation during implementation)
```

This guards against regressions and confirms the C implementation matches the spec.

#### A5 — Xcode project

Add `blake3.c` to the `SSBNetwork` compile sources target (same membership as `blake2b.c`).

---

## Phase B — BIPF wire format (2 files changed, ~120 lines rewritten)

### Background

`SSBButtwoo.m` currently uses `SSBBencode` to parse and build messages.
`SSBBIPF.h/m` already exists with a complete, tested encode/decode API.
The ObjC types returned by `SSBBIPF.decode:consumed:` match what the validation
code already expects:

| Wire field        | BIPF type | Decoded ObjC type |
|-------------------|-----------|-------------------|
| author/prev/sig   | bytes     | `NSData`          |
| sequence/timestamp| int       | `NSNumber`        |
| content           | bytes     | `NSData`          |
| outer / payload   | list      | `NSArray`         |

So the type-checking guards in `validateMessage:` and `computeMessageKey:` require
no changes — only the codec import and decode/encode calls change.

### Wire format comparison

| Layer         | Bencode (current)              | BIPF (spec)                     |
|---------------|--------------------------------|---------------------------------|
| Outer message | `l<payloadBytes><sigBFE>e`     | BIPF list `[payloadBytes, sigBFE]` |
| Payload bytes | bencode byte-string in outer   | BIPF bytes value in outer list  |
| Payload list  | `l<author><seq><prev><ts><c>e` | BIPF list `[author,seq,prev,ts,c]` |

The signature is over `payloadBytes` in both cases — the raw serialised payload,
not the outer wrapper. This invariant is preserved.

### Files

#### B1 — `Sources/SSBButtwoo.m`

Replace import:
```objc
// Before
#import "SSBBencode.h"
// After
#import "SSBBIPF.h"
```

Rewrite `validateMessage:` decode section (~30 lines):
```objc
// Before
NSUInteger offset = 0;
id decoded = [SSBBencode decode:messageData offset:&offset];

// After
NSUInteger consumed = 0;
id decoded = [SSBBIPF decode:messageData consumed:&consumed];
```

Same pattern repeated for the inner payload decode. All structural checks and
BFE-byte inspection (`SSBBFE` calls) are unchanged — they operate on the NSData
values returned, not on the wire format.

Rewrite `computeMessageKey:` decode section (~20 lines): same mechanical change.

#### B2 — `Tests/SSBButtwooTests.m`

Rewrite `BTWBuildValidSeq1Message` helper (~25 lines):
```objc
// Before
NSData *payloadBytes = [SSBBencode encodeList:payloadList];
…
return [SSBBencode encodeList:outerList];

// After
NSData *payloadBytes = [SSBBIPF encodeList:payloadList];
…
return [SSBBIPF encodeList:outerList];
```

Replace import `SSBBencode.h` → `SSBBIPF.h`. No test assertions change — the
helpers produce different bytes but the same logical structure, and `validateMessage:`
now accepts BIPF.

Add one round-trip test verifying that `BTWBuildValidSeq1Message` output can be
decoded by `SSBBIPF.decode:consumed:` and the fields match expectations.

---

## Sequencing

```
A1 → A2 → A3 → A4 → A5   (can land as one commit: "feat: BLAKE3 hash for Buttwoo")
B1 → B2                   (one commit: "feat: BIPF wire encoding for Buttwoo")
```

Phase B depends on Phase A only in the sense that both should land together for
a fully spec-compliant implementation. They touch different parts of `SSBButtwoo.m`
and can be developed in parallel if needed.

---

## What does NOT change

- `SSBBIPF.h/m` — no modifications needed
- `SSBBFE.h/m` — BFE byte layout is encoding-independent
- `SSBFeedCodecRegistry` — codec registration is unchanged
- All other codecs (BendyButt, Bamboo, GabbyGrove, IndexFeed) — unaffected
- Xcode scheme / test targets — only `blake3.c` is added to compile sources

---

## Known-answer test vectors

### BLAKE3

The BLAKE3-team repo publishes a `test_vectors.json` file. For the Buttwoo use case
the input is always `authorKey(32) || seqBE(8)` = 40 bytes. During implementation,
compute the expected digest with the reference `b3sum` tool:

```sh
echo -n "$(python3 -c "import sys; sys.stdout.buffer.write(b'\x00'*32 + (1).to_bytes(8,'big'))")" | b3sum --no-names
```

Use that 64-hex-char string as the expected value in `testDeterministicKey_knownVector`.

### BIPF

The existing `SSBBIPFTests.m` already covers encode/decode round-trips.
The new test in `SSBButtwooTests.m` (B2 above) covers the Buttwoo-specific usage.
