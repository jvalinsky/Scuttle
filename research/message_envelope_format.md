# Message Envelope Format Research

Cross-repo findings on EBT message envelope structure: {key, value} shape, signature inclusion, KVT wrapper conventions.

**Scuttle reference**: `Sources/SSBRoomClient.m:1868-1935`, `Sources/SSBMessageCodec.m`

<!-- Template for new entries:
---
## [YYYY-MM-DD HH:MM] Finding Title
**deciduous**: node_ID [observation] "node title"
**confidence**: 0-100
**source**: file path or repo URL
**evidence**: observed behavior
**implication**: what this means for the bug

[Details...]
-->

---
## [2026-03-22 13:00] CRITICAL: EBT envelope format is WRONG — peers expect raw value, not {key,value}
**deciduous**: 361 [observation] "CONFIRMED: EBT envelope {key,value} is WRONG — peers expect raw value object"
**confidence**: 95
**source**: go-ssb `plugins/ebt/handler.go:174-203`; tildefriends `src/ssb.rpc.c:1075,1176-1187`
**evidence**: go-ssb's EBT handler tries to unmarshal incoming data as frontier (clock) update first. On failure, it looks for `"author"` field DIRECTLY on the JSON body — not nested under `"value"`. tildefriends calls `_tf_ssb_connection_send_history_stream` with `keys=false` (raw value only), and on receive checks `JS_GetPropertyStr(context, args, "author")` at the top level. Scuttle sends `@{@"key": msg.key, @"value": valueDict}` — the `author` field is nested under `value`, invisible to peers.
**implication**: **100% of Scuttle's outbound EBT messages are silently dropped by go-ssb and tildefriends.** The peer can't find `"author"` at the top level, so the message is not recognized as a message. Fix: send `valueDict` directly (the signed message dict), not wrapped in `{key, value}`.

---
## [2026-03-22 13:00] Missing V8 internal binary transform in message key computation
**deciduous**: 363 [observation] "Missing V8 internal binary transform in message key computation"
**confidence**: 90
**source**: Scuttle `SSBMessageCodec.m:324-334`; go-ssb `message/legacy/verify.go:123-131`, `message/legacy/replace.go:80-103`
**evidence**: go-ssb's `Verify` calls `InternalV8Binary(enc)` which converts to UTF-16LE then drops every other byte before SHA256 hashing. Scuttle SHA256-hashes raw UTF-8 bytes directly. For pure ASCII, both produce identical results. For non-ASCII (emoji, accented chars, CJK), hashes differ.
**implication**: Latent bug. Message keys are wrong for any message containing non-ASCII content. Duplicate detection fails, `previous` field mismatches. For ASCII-only content (majority of messages), this is invisible.

---
## [2026-03-22 13:00] Content key ordering uses alphabetical sort — may break signature verification
**deciduous**: 364 [observation] "Content key ordering uses alphabetical sort — may break signature verification"
**confidence**: 80
**source**: Scuttle `SSBMessageCodec.m:180`; go-ssb `message/legacy/encode.go:267-271`
**evidence**: `jsonEncodeObject:indent:` sorts dictionary keys alphabetically. Top-level fields (previous, author, etc.) are hard-coded in correct order in `encodeLegacyValue`, but the `content` dictionary's keys get alphabetically sorted. NSDictionary doesn't preserve insertion order. go-ssb preserves original key ordering via `ReadObjectCB`.
**implication**: When Scuttle re-serializes a message for verification, content keys may be reordered, changing the signed bytes and invalidating signatures. This could cause valid incoming messages to fail `verifyMessage:`.

---
## [2026-03-22 13:00] createHistoryStream missing seq field in syncLocalFeed
**deciduous**: 361 [observation] "CONFIRMED: EBT envelope {key,value} is WRONG"
**confidence**: 85
**source**: Scuttle `SSBRoomClient.m:1187` vs `SSBRoomClient.m:2033`; go-ssb `plugins/gossip/fetch.go:146-149`
**evidence**: `syncLocalFeed` uses `{id, limit, reverse, live}` with no `seq`. `replicateFeed:fromPeer:` correctly includes `seq: maxSequence+1`. go-ssb always sets `q.Seq = int64(latestSeq + 1)`.
**implication**: Performance bug, not correctness. `syncLocalFeed` re-fetches from beginning every time (up to limit 100). The EBT code path (`replicateFeed`) is correct.
