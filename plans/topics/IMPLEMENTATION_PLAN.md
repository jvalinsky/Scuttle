# Scuttle Implementation Plan

## Overview

Two parallel workstreams:

1. **JITDB** — critical correctness and concurrency bugs must be fixed before JITDB
   can be used reliably for anything
2. **Metafeed features** — wiring the existing SSBMetafeed/codec infrastructure
   into the app layer (bootstrap, seed backup, key rotation, multi-device)

The JITDB work is a prerequisite for the lipmaa/partial-sync work in Part 2,
but the metafeed phases can proceed independently.

---

## Part 1: JITDB Fixes

### Phase A — Critical correctness (do first, blocks everything)

#### A1 · Fix sequence number semantics (`SSBJITDB.m:86`)

The log currently uses **byte offset** as the sequence number passed to index
operations. Indexes (bitsets, prefix arrays) are inherently record-oriented
(bit N = record N), so the two spaces must be decoupled.

**Fix:**
- Add a record count `_recordCount` (atomic uint64) to `SSBLog`
- `appendRecord:completion:` increments it after a successful write and returns
  the new record index to the caller
- `SSBJITDB.appendMessage:` receives the record index and passes *that* to index
  operations — not the byte offset
- `fetchMessageAtSequence:` takes a record index, looks up byte offset via a
  separate offset-map (see A2), then reads from the log

#### A2 · Add offset map to `SSBLog` (`SSBLog.m`)

To support record-indexed access, `SSBLog` needs a compact array of byte offsets:

```
_offsetMap: uint64_t[] stored as a separate mmapped file (log.offsets)
```

- On `appendRecord:`, append the write offset to `_offsetMap` before the write
- `readRecordAtIndex:(uint64_t)index` uses `_offsetMap[index]` to seek directly
- On startup, validate `_offsetMap.count == _recordCount`; if mismatch, rebuild
  by scanning the length-prefixed log (O(n) but only on corruption)

#### A3 · Fix non-atomic offset read (`SSBLog.m:50,53`)

```objc
// WRONG — non-atomic read then atomic write:
uint64_t writeOffset = _currentOffset;
atomic_fetch_add(&_currentOffset, data.length);

// CORRECT — single atomic fetch-and-add returns the old value:
uint64_t writeOffset = atomic_fetch_add(&_currentOffset, data.length);
```

#### A4 · Fix `dispatch_data_t` use-after-free (`SSBLog.m:49-79`)

`dispatch_data_create_map` maps a buffer whose lifetime is tied to the
`dispatch_data_t` object. Discarding the object (`#pragma unused(contiguous)`)
while holding a pointer into it is a use-after-free.

**Fix:** copy the bytes before releasing the map reference:
```objc
dispatch_data_t contiguous = dispatch_data_create_map(data, &buffer, &size);
NSData *nsData = [NSData dataWithBytes:buffer length:size]; // copies bytes
(void)contiguous; // now safe to release; nsData owns its copy
```

#### A5 · Fix race condition in index lazy-creation (`SSBJITDB.m:194-210`)

`bitsetIndexForKey:capacity:` and `prefixIndexForField:capacity:` do an
unguarded check-then-set on `_bitsetIndexes` / `_prefixIndexes`. Two concurrent
appends can race to create the same index.

**Fix:** All index access must go through the existing `dbQueue`:
- Make `bitsetIndexForKey:` and `prefixIndexForField:` private; never call them
  outside of a `dispatch_sync(dbQueue, …)` block
- Document this invariant with `DISPATCH_ASSERT_QUEUE` at the top of each method

---

### Phase B — Correctness (do second)

#### B1 · Fix inverted query initialization (`SSBJITDB.m:106-159`)

The query starts with a universe bitset (`[result not]`) and *clears* bits for
non-matches. This is semantically backwards and requires scanning the entire log
for every unindexed field.

**Correct model — intersection-first:**
1. Start with `result = nil` (unknown)
2. For each indexed constraint:
   - If `result == nil`: copy the index bitset as the starting set
   - Else: `[result andWithBitset:indexBitset]`
3. If `result == nil` after all indexes (no indexed constraints): start with an
   all-ones bitset of size `_recordCount` (full scan fallback)
4. For each unindexed constraint: scan only the records where `result` has a
   set bit, clear bits that don't match

#### B2 · Fix `saveIndexes` never called (`SSBJITDB.m:53-62`)

`saveIndexes` is defined but never invoked, so indexes are lost on every restart.

**Fix:**
- Call `saveIndexes` at the end of every successful `appendMessage:completion:`
  (batched with a dirty flag + coalescing timer to avoid per-record I/O)
- Call `saveIndexes` synchronously in a `close` method (add to `SSBJITDB.h`)
- Have `SRRoomManager` call `[jitdb close]` in `applicationWillTerminate:`

#### B3 · Fix index invalidation at startup (`SSBJITDB.m:36-51`)

After loading persisted indexes, compare the indexed record count against the
log's actual record count. If they differ, reindex the new records:

```objc
- (void)loadIndexes {
    // ... existing load code ...
    uint64_t indexedCount = [self storedIndexedRecordCount];
    uint64_t logCount     = _log.recordCount;
    if (indexedCount < logCount) {
        [self reindexFromRecord:indexedCount toRecord:logCount];
    }
}
```

Store `indexedCount` as a small metadata file (`index.meta`) alongside the index
files.

#### B4 · Fix `SSBPrefixIndex` CRC32 collisions (`SSBPrefixIndex.m:30-52`)

CRC32 has ~1-in-4B collision probability per pair, which is unacceptable for
author IDs (there are at most tens of thousands of authors, but false positives
in author filtering are data-corrupting bugs, not just performance issues).

**Fix:** Replace CRC32 with the low 32 bits of a FNV-1a 64-bit hash of the
UTF-8 string. FNV-1a is a single loop with no external dependency:

```c
static uint32_t fnv1a32(const char *s) {
    uint64_t h = 14695981039346656037ULL;
    while (*s) { h ^= (uint8_t)*s++; h *= 1099511628211ULL; }
    return (uint32_t)(h ^ (h >> 32));
}
```

This reduces collision probability to ~1-in-4B but is deterministic and fast.
Update both `addValue:atSequence:` and `filterBitset:withValue:`.

#### B5 · Fix `SSBBitset` capacity mismatch in `andWithBitset:` (`SSBBitset.m:52-60`)

If `other.capacity > self.capacity`, the loop reads past `self`'s buffer. Add a
guard:

```objc
- (void)andWithBitset:(SSBBitset *)other {
    size_t count = MIN(_buffer.length, other.data.length) / sizeof(simd_ulong4);
    // ... existing loop ...
}
```

Also handle the tail bytes (when `buffer.length % sizeof(simd_ulong4) != 0`) by
masking the remaining bytes after the SIMD loop.

---

### Phase C — Performance / completeness (do third)

#### C1 · Coalesce index saves with a dirty flag

Rather than writing all index files after every append, set a `_dirty` flag and
flush on a 250ms debounce timer (reset on each append). This reduces I/O from
O(messages) to O(bursts).

#### C2 · Add batch append API

```objc
- (void)appendMessages:(NSArray<NSDictionary *> *)messages
            completion:(void(^)(NSError *))completion;
```

Updates indexes in a single pass, then calls `saveIndexes` once at the end.
Used during initial EBT replication which can deliver thousands of messages in
a burst.

#### C3 · Add bounds check to `fetchMessageAtSequence:` (`SSBJITDB.m:161`)

```objc
if (sequence >= _log.recordCount) {
    completion(nil, [NSError …]);
    return;
}
```

---

## Part 2: Metafeed Feature Roadmap

The existing `SSBMetafeed`, `SSBBendyButt`, and `SSBFeedCodecRegistry`
infrastructure is ready. What's missing is the app-layer integration.

### Phase 1 — Metafeed bootstrap

**Goal:** Every identity has a root metafeed. Generated once at account creation
(or migrated from an existing classic identity).

**Changes:**

1. **`SSBKeychain`** — add two new items:
   - `ssb_metafeed_seed` (32 bytes, random) — master secret from which all
     sub-feed keys are derived via HKDF
   - `ssb_metafeed_root_id` (string) — canonical metafeed ID for quick lookup

2. **`SRRoomManager.generateIdentity`** — after generating the Ed25519 keypair,
   call `[SSBMetafeed generateSeed]` and `[SSBMetafeed createRootMetafeedFromSeed:]`.
   Store both in the keychain. Publish a `metafeed/announce` message on the
   classic feed so peers can discover the root.

3. **`SRRoomManager.resetAccount`** — wipe `ssb_metafeed_seed` and
   `ssb_metafeed_root_id` alongside the existing identity wipe.

4. **`SSBFeedStore`** — add a `metafeed_messages` table (or use the existing
   `messages` table filtered by `feed_format = SSBBFEFeedFormatBendyButt`) to
   store BendyButt-signed metafeed messages.

5. **Migration** — for existing installs with no metafeed seed, generate one on
   first launch and publish the announce message silently.

---

### Phase 2 — Seed backup and recovery (SIP-004)

**Goal:** The user can back up their metafeed seed, encrypted to a trusted
contact's key, so they can recover their identity tree after device loss.

**Changes:**

1. **`SRSeedBackupViewController`** (new) — a sheet presented from Preferences:
   - Shows the user's root metafeed ID
   - Text field to enter a trusted contact's SSB ID
   - "Back Up" button calls `[SSBMetafeed encryptSeedForBackup:toFeed:feedKeys:]`
     (already implemented) and publishes the result as a `metafeed/seed` BendyButt
     message on the metafeed

2. **`SRSeedRecoveryViewController`** (new) — shown during first-launch setup if
   the user has no identity:
   - Accepts a backup message (pasted JSON or scanned QR)
   - Calls `[SSBMetafeed decryptSeedFromMessage:feedKeys:]` to recover the seed
   - Re-derives the full metafeed tree from the recovered seed

3. **`SRRoomManager`** — watch for incoming `metafeed/seed` messages addressed
   to the local identity; decrypt and offer the user a "Restore identity?" prompt

4. **`SRPreferencesViewController`** — add "Back Up Identity Seed…" button

---

### Phase 3 — Key rotation

**Goal:** The user can rotate a compromised sub-feed key without losing their
social graph (follows, followers, published content).

**Changes:**

1. **`SRRoomManager.revokeSubfeed:(NSString *)feedID reason:(NSString *)reason`**
   (new) — calls `[SSBMetafeed createMetafeed:tombstoneFeed:reason:]` on the
   root metafeed and publishes the signed BendyButt tombstone message.

2. **`SRRoomManager.replaceSubfeed:(NSString *)oldFeedID`** (new):
   - Derives a new sub-feed key from the metafeed seed with an incremented nonce
   - Calls `createMetafeed:addDerivedFeed:purpose:nonce:` to publish the new
     feed announcement
   - Tombstones the old feed

3. **`SSBFeedStore`** — add `isTombstoned:(NSString *)feedID` query that checks
   the BendyButt metafeed messages for a tombstone entry for the given feed ID.
   Tombstoned feeds are excluded from timeline queries.

4. **`SSBRoomClient`** — when EBT sends us the clock for a tombstoned feed, reply
   with sequence = -1 (EBT "do not want") to signal we no longer replicate it.

5. **`SRPreferencesViewController`** — "Rotate Feed Key…" option, confirmation
   dialog explaining the consequences.

---

### Phase 4 — Multi-device posting (Buttwoo)

**Goal:** A user can post from multiple devices (phone, second Mac) under a
single identity. Each device has its own Buttwoo sub-feed; an index feed
aggregates them into a single timeline view.

**New components:**

1. **`SRDeviceManager`** (new service in `App/Logic/`):
   - `registerThisDevice` — derives a Buttwoo sub-feed for the current device
     using `deviceName + UUID` as the nonce, publishes an `add/derived` metafeed
     message
   - `registeredDevices` — returns the list of known device feeds by scanning
     `add/derived` metafeed messages with purpose = `SSBMetafeedPurposeV1`
   - `deregisterDevice:(NSString *)feedID` — tombstones the device's sub-feed

2. **`SSBIndexFeed` integration** — after registering all device feeds, create a
   BendyButt index feed that points to all Buttwoo device feeds. The index feed
   is what peers replicate to get the full cross-device timeline.

3. **`SSBFeedStore.timelineWithLimit:`** — update to union messages across all
   known device feeds for a given root metafeed ID, not just the single classic
   feed.

4. **`SRRoomManager`** — when connecting to a room, include all known device feed
   IDs in the EBT clock (not just the classic feed).

5. **`SRDevicePairingViewController`** (new) — QR-code based pairing flow:
   - Device A shows a QR with the metafeed seed (encrypted to Device B's ephemeral
     key via SIP-004)
   - Device B scans, decrypts, re-derives the full metafeed tree
   - Device B registers itself, Device A's timeline now includes Device B's posts

6. **`SRPreferencesViewController`** — "Manage Devices…" entry that presents
   `SRDevicePairingViewController` and a list of registered devices with
   deregister buttons.

---

### Phase 5 — Lipmaa partial sync

**Goal:** Use the skip-list structure of GabbyGrove and Bamboo feeds to verify
feed integrity without downloading every message — important for large feeds over
slow connections.

**Changes:**

1. **`SSBRoomClient.verifyFeedIntegrity:author:format:`** (new):
   - For GabbyGrove/Bamboo feeds: walk the lipmaa chain backwards from the tip
   - Request only the messages at positions `tip`, `lipmaa(tip)`,
     `lipmaa(lipmaa(tip))`, … (O(log n) messages to verify the chain)
   - Full download only needed for content consumption, not integrity verification

2. **`SSBFeedStore`** — `lipmaaMessageForAuthor:sequence:format:` — given an
   author and a sequence number, return the stored message at the lipmaa-linked
   predecessor sequence (computed via `GabbyGrove.lipmaaSeq` or
   `SSBBamboo.lipmaaSequenceFor:`).

3. **`SRRoomManager`** — before marking a feed as "fully synced", run the lipmaa
   chain verification. If it passes, mark as verified. If it fails, quarantine
   the entire feed and show an error in the UI.

4. **`SRFeedViewController`** — show a "verified" or "unverified" indicator for
   GabbyGrove/Bamboo feeds based on the feed's verification state in the store.

---

## Implementation Order

```
Part 1 (JITDB):    A1 → A2 → A3 → A4 → A5   (critical, do first)
                   B1 → B2 → B3 → B4 → B5   (correctness, do second)
                   C1 → C2 → C3              (performance, do third)

Part 2 (Metafeed): Phase 1 (bootstrap)        ← enables everything below
                   Phase 2 (seed backup)      ← can do in parallel with 3+4
                   Phase 3 (key rotation)     ← depends on Phase 1
                   Phase 4 (multi-device)     ← depends on Phase 1
                   Phase 5 (lipmaa sync)      ← depends on JITDB Part 1 + Phase 1
```

Part 1 Phases A and B are blockers for production use of JITDB anywhere.
Part 2 Phase 1 (metafeed bootstrap) is a blocker for all other Part 2 phases.
