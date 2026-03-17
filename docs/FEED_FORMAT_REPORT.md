# SSB Feed Format Report
## Code Review + Ecosystem App Analysis

*Generated from codebase analysis of `/Sources/SSB{GabbyGrove,Buttwoo,Bamboo,BendyButt,IndexFeed,Metafeed}.*
*plus SSB ecosystem research.*

---

## Part 1: Feed Format Overview

The SSB ecosystem has evolved from a single feed format (Classic) to a family of six distinct
formats, each designed for different trade-offs between performance, encoding size, cross-language
portability, and application architecture. This codebase implements five of them via a pluggable
`SSBFeedCodec` protocol with automatic self-registration via `+load`.

---

## Part 2: Code Review of Implementations

### 2.1 Protocol & Registry — `SSBFeedCodec.h`, `SSBFeedCodecRegistry`

**Status: ✅ Good**

The `SSBFeedCodec` protocol is clean and well-scoped: two methods
(`verifyMessageData:error:` and `computeMessageKeyFromData:error:`) plus two read-only format
properties. Self-registration via `+load` is idiomatic and requires no external bootstrap.

`SSBFeedCodecRegistry` uses a concurrent `dispatch_queue_t` with `dispatch_barrier_async` for
writes and `dispatch_sync` for reads — correct reader-writer pattern. One subtle point:
`dispatch_barrier_async` is fire-and-forget, so a codec is not guaranteed to be visible
immediately after its `+load` returns. In practice this is fine since `+load` runs during
`dyld` initialization, well before any application code queries the registry.

---

### 2.2 GabbyGrove (`SSBGabbyGrove.m`)

**Status: ⚠️ Not Interoperable — BLAKE2b Placeholder**

#### Format
Protobuf wire encoding (varint tags, length-delimited bytes fields). Fields:
`author(1)`, `sequence(2)`, `previous(3)`, `lipmaa(4)`, `contentHash(5)`,
`content(6)`, `isEndOfFeed(7)`, `signature(8)`.

#### Correctness

| Area | Finding |
|------|---------|
| Varint encoding | ✅ Correct LEB128 implementation; round-trips verified |
| Protobuf parsing | ✅ Handles both wire types (varint, length-delimited) |
| Ed25519 signing | ✅ Correct: signed payload is bytes 0…sigFieldOffset-1, verified via `crypto_sign_open` |
| Lipmaa validation | ✅ Correctly requires lipmaa field when `lipmaaSeq(n) != n-1` |
| `blake2b256:` | ❌ **Uses SHA-256 (CommonCrypto) instead of BLAKE2b-256** |
| Forward compat | ❌ Unknown wire types cause parse failure instead of skip (breaks protobuf extensibility) |

#### Critical Issue — Hash Algorithm
```objc
// SSBGabbyGrove.m:104 — TODO comment is accurate but unfixed
// TODO: Replace SHA-256 with BLAKE2b-256 per RFC 7693 once a BLAKE2b dependency is added
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);  // ← wrong algorithm
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}
```

`computeMessageKey:` calls `blake2b256:`, so every message key produced by this codec is a
SHA-256, not a BLAKE2b-256. No other SSB implementation (JS `ssb-classic`, go-ssb, ssb-rs)
will recognize these keys. **Messages created with this codec cannot be exchanged on the SSB
network.**

#### Minor Issues
- `signatureFieldOffset` is initialized to `data.length` (not 0), so the `== 0` guard on
  line 253 is unreachable — harmless but misleading.
- `validateMessage:nil` would crash without the `messageData.length == 0` guard — the nil
  check is implicit via Objective-C messaging nil returning 0.

---

### 2.3 Buttwoo (`SSBButtwoo.m`)

**Status: ⚠️ Not Interoperable — BLAKE2b Placeholder**

#### Format
Bencode outer list `[payloadBytes, sigBFE]`, where `payloadBytes` is itself a bencode list
`[authorBFE, seq, prevBFE, timestamp, content]`. Delegates bencode to `SSBBencode`.

#### Correctness

| Area | Finding |
|------|---------|
| Bencode parsing | ✅ Correct delegation to `SSBBencode` |
| BFE type/format validation | ✅ Validates author (type=Feed, format=ButtwooV1) and previous (nil or ButtwooV1 msg) |
| Ed25519 signature | ✅ Signs `payloadBytes` (the bencode encoding of the payload list) |
| `computeDeterministicKey:` | ❌ **Uses SHA-256 instead of BLAKE2b-256 for author‖seq hash** |
| Max message size | ℹ️ 8192-byte cap is reasonable but undocumented in spec |

#### Critical Issue — Deterministic Key
```objc
// SSBButtwoo.m:82
CC_SHA256(input.bytes, (CC_LONG)input.length, digest);  // should be BLAKE2b
```
Buttwoo's key innovation is deterministic message IDs: `BLAKE2b(pubkey || seq_be64)`. A peer
can therefore request message N from author A without knowing its hash in advance. With SHA-256
substituted, the IDs differ from every other implementation's and the determinism property is
preserved internally but incompatible externally.

#### Positive Notes
- Correct `memcmp` after `crypto_sign_open` (double-checks the opened message equals payload).
- `kMaxMessageSize` prevents memory exhaustion during bencode parsing.

---

### 2.4 Bamboo (`SSBBamboo.m`)

**Status: ❌ Two Critical Bugs — Hash Placeholder + Lipmaa Calculation**

#### Format
Fixed-width binary struct (no self-describing encoding):

```
seq=1 layout  (177 bytes):
  [0-31]   author pubkey
  [32-63]  log_id
  [64]     is_end_of_log  (0 or 1)
  [65-72]  seq_number  (big-endian uint64)
  [73-104] payload_hash  (32 bytes)
  [105-112] payload_size  (big-endian uint64)
  [113-176] Ed25519 signature  (signs bytes 0-112)

seq>1 layout  (241 bytes):
  adds lipmaa_link [73-104] and backlink [105-136]
  payload_hash at [137-168], payload_size [169-176]
  signature at [177-240]
```

#### Bug 1 — Lipmaa Calculation (SSBBamboo.m:111-150)

The code has an extended comment block showing the developer was uncertain about the correct
formula. The implementation produces wrong results for `seq >= 4`:

```
Trace for seq=4:
  pow3 starts at 1
  while (1*3 < 4): pow3 = 3
  while (3*3 < 4): false → stop
  pow3(3) >= seq(4)? No → no division
  return 4 - 3 = 1   ← actually correct for Bamboo

Trace for seq=9:
  while (1*3 < 9): pow3 = 3
  while (3*3 < 9): pow3 = 9   ← 9*3=27 < 9? NO → stop at 3
  Actually: 1*3=3 < 9 → pow3=3; 3*3=9 < 9? No → stop, pow3=3
  return 9 - 3 = 6   ← correct
```

After careful trace, **the lipmaa values are actually correct for tested cases**. However,
the code comment on lines 131-137 contains incorrect analysis of `lipmaa(5)`, and the
implementation's condition `while (pow3 * 3 < seq)` produces `pow3 = largest power of 3
strictly less than seq`, which matches the Bamboo spec. The implementation is correct but
the surrounding commentary is misleading and should be cleaned up.

#### Bug 2 — Entry ID Size Ambiguity (SSBBamboo.m:267-275)

```objc
// Entry ID = SHA-256(first 32 bytes) || signature = 32 + 64 = 96 bytes
// Header says "64 bytes" — implementation returns 96, acknowledged as ambiguity
```

The header comment says "Message IDs are 64 bytes" but the implementation returns 96.
The code comment acknowledges this. The Bamboo spec (reference Go implementation) uses
`BLAKE2b(entry_bytes)` (32 bytes) as the entry ID, not hash‖sig. **This implementation
is non-standard.**

#### Bug 3 — Hash Algorithm
Same as GabbyGrove and Buttwoo: `hashData:` uses SHA-256 instead of BLAKE2b.

#### Positive Notes
- Binary layout constants (`kAuthorOffset`, `kSeqOffset`, etc.) make the fixed-width
  parsing readable.
- Entry size guards prevent out-of-bounds reads.
- Ed25519 verification via `crypto_sign_open` is correct.

---

### 2.5 BendyButt (`SSBBendyButt.m`)

**Status: ⚠️ Not Interoperable — Hash Placeholder; Content Signing Ambiguous**

#### Format
Same bencode structure as Buttwoo but with dual-signature capability: the outer message
signature uses the *author* Ed25519 key; the content can optionally be signed by a separate
*content key* (HMAC-SHA512). This is the exclusive format for metafeed management messages.

#### Correctness

| Area | Finding |
|------|---------|
| Bencode parsing | ✅ Correct |
| Author signature | ✅ Ed25519 over bencode payload bytes |
| Content signing | ✅ HMAC-SHA512 with "bendybutt" prefix, 32-byte output |
| Message key | ❌ SHA-256 instead of BLAKE2b-256 |
| Previous BFE | ✅ Validates nil or BendyButtV1 message format |

#### Message Key Issue
```objc
// SSBBendyButt.m ~line 399 (approximate — large file)
CC_SHA256(messageData.bytes, (CC_LONG)messageData.length, digest);
```
The JS reference (`ssb-bendy-butt`) computes message keys as BLAKE2b of the full bencode wire
bytes. SHA-256 substitution breaks cross-implementation compatibility.

#### Content Signing Note
`verifyContentSignature:onContent:author:` passes `author` (Ed25519 pubkey) as the HMAC key.
The BendyButt spec actually uses a *separate 32-byte secret key* for content signing — the
author pubkey would not normally be used as an HMAC key. This is semantically incorrect but
doesn't affect the message-level Ed25519 verification.

---

### 2.6 IndexFeed (`SSBIndexFeed.m`)

**Status: ✅ Mostly Good (delegates to Classic codec)**

Index feeds use Classic JSON wire format signed with Ed25519 — they are not a new wire format
but a structural layer on top of Classic. The codec correctly:

- Delegates `verifyMessageData:` to `SSBMessageCodec verifyMessage:` (Classic verification).
- Uses SHA-256 for `computeMessageKeyFromData:` — **correct** for Classic format (unlike the
  above codecs where SHA-256 was wrong).
- Provides rich helpers for creating index queries, add-derived messages, and URI construction.

#### Minor Issues
- The deprecated `createQueryWithAuthor:messageType:channel:` method sets `type` twice when
  converting to the new `isPrivate` parameter (minor inefficiency).
- The `generateNonce` helper at line ~442 is not called from any visible code path.
- A custom `sha256:` hash construction is used for seed derivation in some paths instead of
  HKDF — unclear if this matches the IndexFeed spec exactly.

---

### 2.7 Metafeed (`SSBMetafeed.m`)

**Status: ❌ Seed Encryption Broken**

Metafeed management is architecturally important: it creates the root BendyButt feed, manages
the tree of subfeeds, and provides seed encryption for account recovery.

#### Critical — Seed Encryption (lines ~290-339)

```objc
// Zero nonce — deterministic, leaks information
memset(nonce, 0, crypto_box_NONCEBYTES);

// Incorrect curve operation:
crypto_scalarmult_curve25519(ephemeralPubKey, ephemeralKeys.bytes, recipientKey.bytes);
// ^ This computes shared_secret = DH(ephemeral_sk, recipient_pk), not the ephemeral pubkey
```

Two bugs:
1. **Zero nonce**: The same seed encrypted for the same recipient always produces identical
   ciphertext. Anyone who can observe two ciphertexts can confirm they're the same seed.
2. **Wrong curve primitive**: `crypto_scalarmult_curve25519` computes a DH shared secret, not
   an ephemeral public key. The actual ephemeral pubkey should be derived via
   `crypto_scalarmult_curve25519_base`.

These bugs make the seed backup/recovery mechanism non-functional for round-trip use.

#### Dead Code
The 96-byte `senderKeys` buffer constructed at lines ~309-315 is never used after
construction (the variable is not read again).

#### Positive
- Non-cryptographic metafeed message construction (`addDerivedFeed:`, `tombstoneFeed:`) is
  correct and follows the message dictionary structure defined by `ssb-meta-feeds-spec`.

---

### 2.8 BFE (`SSBBFE.m`)

**Status: ✅ Good**

Binary Field Encodings correctly encodes/decodes all feed, message, blob, encryption-key,
signature, encrypted, generic, and identity types. Thread-safe (stateless class methods).

Minor notes:
- `detectType:` returns `(SSBBFEType)-1` for short/invalid data. Switch statements
  without a `default` case over this return value would silently misbehave.
- Base64 URL→standard conversion has a fallback that could mask bugs by accepting both
  padded and unpadded formats.
- Sigil parsing splits on the *last* dot, which is correct for `.ed25519` / `.sha256` but
  could theoretically misbehave with non-standard suffix strings.

---

### 2.9 Summary Code Review Table

| Codec | Wire Format | Ed25519 | Hash Algorithm | Status |
|-------|------------|---------|----------------|--------|
| Classic (delegated) | JSON | ✅ | SHA-256 ✅ | — |
| GabbyGrove | Protobuf | ✅ | SHA-256 ❌ (needs BLAKE2b) | Not interoperable |
| BendyButt | Bencode | ✅ | SHA-256 ❌ (needs BLAKE2b) | Not interoperable |
| Buttwoo | Bencode | ✅ | SHA-256 ❌ (needs BLAKE2b) | Not interoperable |
| Bamboo | Binary struct | ✅ | SHA-256 ❌ (needs BLAKE2b) | Not interoperable |
| IndexFeed | JSON (Classic) | ✅ | SHA-256 ✅ | Functional |
| Metafeed | BendyButt | ✅ | Mixed | Encryption broken |
| BFE | Type-prefixed bytes | — | — | ✅ Good |

**The single fix that would make all four wire-format codecs interoperable is adding a
BLAKE2b-256 dependency (e.g., libsodium, which is already a transitive dep via tweetnacl)
and replacing `CC_SHA256` in the four `blake2b256:`/`hashData:`/`computeDeterministicKey:`
methods.**

---

## Part 3: Feed Format App Suitability Analysis

### 3.1 Classic SSB Feed

**Wire format:** Canonical JSON, Ed25519, SHA-256 message keys, linear chain (each message
links to previous via `key` field).

#### Real-world Usage
The original format used by every SSB client from 2015 onward:
- **Patchwork**, **Patchbay**, **Patchfoo** — Classic-only; these are the "legacy" desktop clients
- **Manyverse** — Classic for its main social feed (metafeeds wraps Classic subfeeds)
- **Planetary (iOS)** — Built on go-ssb; uses Classic for all user content
- **Āhau** — Classic for all genealogy/group content; SSB-CRUT is Classic messages with tangle metadata
- **git-ssb** — Distributed git over Classic messages
- **ssb-npm** — Package registry over Classic messages

#### Ideal Application Profile
| Characteristic | Why Classic fits |
|----------------|-----------------|
| Social / microblogging | JSON content is human-readable; `type:"post"` convention is established |
| Follow graph, contact management | `type:"contact"` messages form the trust graph |
| Apps that need broad ecosystem compat | Every SSB client can read Classic |
| Server/desktop (powerful hardware) | JSON parsing overhead is acceptable |
| Historically active communities | Existing social graph lives in Classic feeds |

#### When NOT to Use Classic
- Embedded / IoT (120-byte LoRa packets can't hold JSON)
- Multi-device (one keypair → one feed; metafeeds solve this)
- When parsing in non-JS languages (V8 number formatting in canonical JSON is a known pain point)
- When storage is at a premium (JSON is verbose)

---

### 3.2 GabbyGrove (`ggfeed-v1`)

**Wire format:** Protobuf-style binary, BLAKE2b-256 message keys, HMAC-SHA256 content
authentication, lipmaa skip links (same as Bamboo).

#### Real-world Usage
- Proposed as a specification draft (`ssb-spec-drafts` PR #1) by Helge Krueger (cryptix)
- Go reference implementation: `~cryptix/go-gabbygrove` on sourcehut
- Briefly available as a hidden debug option in **Planetary iOS** (proof of concept only)
- **Never shipped in production** by any client for peer-to-peer replication

#### Design Motivation
GabbyGrove was the first serious attempt to replace Classic with a non-JS-centric format:
1. **Cross-language portability** — protobuf is universally implemented; no V8 number quirks
2. **Content authentication** — separate HMAC-SHA256 hash of content lets peers verify
   content integrity independently of the author signature
3. **Partial replication** — lipmaa links enable O(log n) skip-list traversal to verify
   any message without downloading the whole feed
4. **Compact encoding** — binary protobuf is ~30-50% smaller than equivalent JSON

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| Mobile (bandwidth-constrained sync) | ✅ Smaller messages = faster sync |
| Multi-language ecosystem | ✅ Protobuf libraries exist for every language |
| Apps needing content integrity proof | ✅ HMAC-SHA256 content hash separable from author sig |
| Partial replication (skip old messages) | ✅ Lipmaa links |
| Privacy-sensitive apps | ✅ Content hash can verify without revealing content |

#### Limitations
- More complex to implement than Classic (protobuf parsing, lipmaa)
- Never achieved critical mass — ecosystem didn't adopt it, making it a stranded format
- Superseded functionally by BendyButt + Metafeeds for the use cases it targeted

---

### 3.3 BendyButt (`bendybutt-v1`)

**Wire format:** Bencode binary, BLAKE2b message keys, dual signature (author Ed25519 +
optional content HMAC-SHA512). **The exclusive format for metafeed management messages.**

#### Real-world Usage
- **Manyverse** — deployed in production for metafeed management (root metafeed + shards tree)
  since the NLnet-funded private groups work in late 2022 forced adoption
- **go-ssb** — `ssbc/go-metafeed` library handles BendyButt for metafeed management
- **ssb-db2** — pluggable format backend supports BendyButt alongside Classic
- Rust: `ssbc/ssb-bendy-butt-rs`

BendyButt is **not used for social content** — it is strictly the *metafeed management layer*.
A root BendyButt feed contains messages like `add-derived` (adding a subfeed) and
`tombstone` (removing a subfeed). User posts live in Classic or Buttwoo subfeeds.

#### Design Motivation
The critical architectural feature: the content portion of a BendyButt message can be signed
by a *different* keypair than the message author. This allows a **parent metafeed to
cryptographically authorize the creation of a child subfeed** without the child's key signing
its own birth announcement. This is essential for the metafeed tree to be tamper-evident.

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| Multi-device identity | ✅ Metafeeds are the solution; BendyButt is required |
| Private groups (ssb-tribes2) | ✅ Group feeds are BendyButt-managed subfeeds |
| Account migration / key rotation | ✅ Tombstone messages authorize key handoff |
| Data sovereignty platforms (Āhau) | ✅ Metafeed tree can represent family/group ownership |
| Desktop and mobile SSB clients | ✅ Manyverse, go-ssb have production implementations |

#### Limitations
- **Only meaningful in the context of metafeeds** — no application writes user content in BendyButt
- Requires understanding the metafeed shards tree structure
- BLAKE2b dependency (placeholder SHA-256 in this codebase)

---

### 3.4 Buttwoo (`buttwoo-v1`)

**Wire format:** Bencode binary, BLAKE2b message keys, deterministic message ID
(`BLAKE2b(author_pubkey || seq_bigendian)`). No lipmaa links.

#### Real-world Usage
- Specification: `ssbc/ssb-buttwoo-spec`
- JS implementation: `ssbc/ssb-buttwoo`
- **Not yet deployed** in any production SSB client
- Intended as the eventual successor format for social content (to replace Classic)

#### Design Motivation
Buttwoo solves a specific replication problem: with Classic, you cannot request "message #5
from @alice" without already knowing its SHA-256 hash. With Buttwoo's deterministic IDs, any
peer can compute `BLAKE2b(alice_pubkey || 5)` and request exactly that message. This enables:

1. **Random-access replication** — request any message by (author, seq) without a prior index
2. **Efficient resumption** — after a gap, sync from a known sequence rather than scanning
3. **Simpler partial sync** — omit lipmaa complexity (unlike GabbyGrove/Bamboo) since random
   access doesn't require skip links

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| High-churn mobile social feeds | ✅ Deterministic IDs enable efficient gap-fill |
| Large communities (many authors) | ✅ No need to hold full feed index to request a message |
| Bandwidth-limited sync | ✅ Bencode is more compact than JSON |
| Apps where partial replication matters | ✅ Pairs naturally with index feeds |
| Future SSB clients (post-metafeed) | ✅ Designed as the long-term Classic replacement |

#### Limitations
- Not deployed yet — no interoperability tested in production
- Deliberately omits lipmaa, so skip-list verification isn't possible (tradeoff vs. Bamboo)
- Requires BLAKE2b (not available in CommonCrypto on Apple platforms without adding a dep)

---

### 3.5 Bamboo

**Wire format:** Fixed-width binary, BLAKE2b hashing, lipmaa skip links, Ed25519 signature
over all preceding fields (deterministic field positions, not self-describing).

#### Real-world Usage
- Specification: `bamboo` GitHub repo (originally by Aljoscha Meyer)
- Go, Rust, JS implementations exist in the wider ecosystem
- **p2panda** — uses a Bamboo-inspired append-only log as its core data structure; p2panda
  is a Rust+TypeScript stack targeting community apps over LoRa/BLE/USB
- **tinySSB** — uses a 120-byte constrained format (BLE/LoRa) that shares Bamboo's design
  philosophy of fixed-size packets and lipmaa skip links
- **Not adopted** by main SSB clients (Manyverse, Planetary) which went with Buttwoo instead

#### Design Motivation
Bamboo's fixed binary layout was specifically designed for:
1. **Resource-constrained environments** — no dynamic parsing needed; field positions are
   calculated by sequence number
2. **Lipmaa skip links** — enables O(log n) verification of any entry without downloading
   the full log (critical for LoRa/BLE where every byte costs power)
3. **Cross-language ease** — fixed offsets + binary = trivial to implement in C, Rust, Go

Bamboo is the format that influenced tinySSB and p2panda, even if the exact wire format
differs in those projects.

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| IoT / embedded (LoRa, BLE) | ✅ Fixed-width parsing, minimal allocation |
| Offline-first mesh networks | ✅ Log integrity verifiable without full download |
| Environmental monitoring | ✅ Sensor readings as append-only log entries |
| Community mesh radio (amateur, disaster relief) | ✅ Works at low bandwidth |
| Academic / research (distributed systems teaching) | ✅ tinySSB used at Uni Basel |
| Post-internet applications (p2panda) | ✅ Designed for unreliable transport |

#### Limitations
- More complex format than Buttwoo (lipmaa link management)
- Fixed offsets make it inflexible to add fields (unlike protobuf or bencode)
- Not adopted by social SSB clients, limiting ecosystem support
- Entry ID definition is ambiguous (this codebase acknowledges it; returns 96 bytes vs
  spec-implied 32 or 64)

---

### 3.6 Indexed Feed (`indexed-v1`)

**Not a standalone feed format.** An index feed is a Classic-format subfeed whose
messages contain pointers (keys) to messages in another feed. It enables partial replication
by allowing peers to sync the index without downloading the full content feed.

#### Real-world Usage
- Specification: `ssbc/ssb-index-feeds-spec` (SIP 3, 2021-10-11)
- JS implementation: `ssbc/ssb-index-feeds`
- Proof-of-concept tested in the NGI Pointer benchmark fork of Manyverse
  (`ssb-ngi-pointer/manyverse-with-index-feeds-archived`)
- **Required by ssb-tribes2 (private groups)** as of late 2022, driving Manyverse adoption
- Used inside the metafeed tree at a specific shard for efficient replication

#### Design Motivation
Without index feeds, replicating any subset of messages requires downloading the full feed
to maintain the hash chain. Index feeds break this by mirroring references:

```
Content feed:  msg#1, msg#2(post), msg#3, msg#4(post), msg#5(contact), ...
Index feed:    ptr→msg#2, ptr→msg#4       (only posts)
```

A peer wanting only posts from @alice downloads only the index feed + the pointed messages.

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| Mobile clients (limited storage) | ✅ Download posts only, skip blobs/contacts |
| Large follow graphs | ✅ Don't download full feeds of accounts you barely follow |
| Private groups | ✅ Group message index enables efficient group feed replication |
| Search indexing | ✅ Type-filtered index speeds full-text search |
| Long-lived accounts (thousands of messages) | ✅ Don't replay entire history to onboard |

#### Limitations
- Requires metafeed support (index feeds live in the metafeed tree)
- Creates index maintenance overhead (each index must be kept current)
- Still uses Classic wire format (not binary-compact)

---

### 3.7 Metafeeds (BendyButt root + Classic/Buttwoo subfeeds)

**Not a wire format but a tree architecture** built on top of BendyButt. A single root
BendyButt feed owns a tree of subfeeds, each with a declared `feedpurpose` and keypair.

#### Real-world Usage
- Specification: `ssbc/ssb-meta-feeds-spec` (SIP 2, 2021-10-11)
- Deployed in Manyverse (production, ~late 2022) driven by ssb-tribes2 dependency
- go-ssb: `ssbc/go-metafeed`
- ssb-db2 supports the shards tree structure
- **Āhau** co-funded the fusion-identity spec which builds on metafeeds

#### Ideal Application Profile
| Characteristic | Fit |
|----------------|-----|
| Multi-device social apps | ✅ Each device gets its own keypair under one identity |
| Private group messaging | ✅ Group feed is a managed subfeed |
| Data sovereignty / indigenous data apps | ✅ Āhau uses subfeed-per-purpose for family data |
| Decentralized moderation | ✅ Index subfeeds can encode moderation state |
| Long-running identities (key rotation) | ✅ Tombstone old subfeed, add new one |

---

## Part 4: Format Selection Guide

```
Use Case                              → Recommended Format
─────────────────────────────────────────────────────────
Social posts, broad SSB compat        → Classic
Multi-device identity (same user)     → Metafeeds + BendyButt (management) + Classic/Buttwoo (content)
Private group messaging               → Metafeeds + Index feeds + ssb-tribes2
IoT / LoRa / BLE sensor log          → Bamboo (or tinySSB 120-byte)
Mobile with partial replication       → Buttwoo (content) + Index feeds
Cross-language / non-JS runtime      → GabbyGrove or Buttwoo (both avoid JS quirks)
Embedded C with fixed memory         → Bamboo (fixed offsets, no dynamic parse)
Data sovereignty / offline-first     → Classic or Buttwoo + Metafeeds
Academic / teaching distributed sys  → tinySSB (simplified Bamboo-inspired)
```

---

## Part 5: Key Findings & Recommendations

### 5.1 Critical: Add BLAKE2b Dependency

Every new-format codec (GabbyGrove, Buttwoo, Bamboo, BendyButt) has a `// TODO: Replace
SHA-256 with BLAKE2b-256` placeholder. Until this is resolved, the codebase cannot exchange
messages with any other SSB implementation.

**Recommended fix:** Add `libsodium` (already used transitively via tweetnacl) and use
`crypto_generichash` (BLAKE2b). The change is isolated to four single-function
implementations; the codec protocol and registry require no changes.

```objc
// Replace all four placeholder implementations with:
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t out[32];
    crypto_generichash(out, 32, data.bytes, data.length, NULL, 0);
    return [NSData dataWithBytes:out length:32];
}
```

### 5.2 High: Fix Metafeed Seed Encryption

The `encryptSeed:` method uses a zero nonce and an incorrect curve primitive. Fix:
1. Generate random nonce via `SecRandomCopyBytes`
2. Derive the ephemeral public key via `crypto_scalarmult_curve25519_base`
3. Prepend the ephemeral public key to ciphertext so decryptor can reconstruct the shared secret

### 5.3 Medium: GabbyGrove Forward Compatibility

Replace `return NO` for unknown wire types with `continue` (skip unknown field). This makes
the parser forward-compatible with future GabbyGrove spec extensions.

### 5.4 Medium: Bamboo Entry ID Clarification

The 96-byte entry ID (SHA-256(first 32) ‖ sig) is non-standard. The Bamboo Go reference
uses `BLAKE2b(full_entry_bytes)` as the 32-byte entry ID. After adding BLAKE2b, align with
the reference implementation.

### 5.5 Low: SSBMetafeed Dead Code

Remove the unused 96-byte `senderKeys` buffer at lines ~309-315. It is allocated and
populated but never read.

---

*Report generated from codebase at commit `233771d` on branch `claude/review-objc-macos-patterns-8cw3p`.*
