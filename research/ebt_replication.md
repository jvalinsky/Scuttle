# EBT Replication Research

Cross-repo findings on EBT protocol behavior: clock exchange, version negotiation, notes encoding, bilateral handling.

**Scuttle reference**: `Sources/SSBRoomClient.m:1597-1935`

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
## [2026-03-22 13:00] CRITICAL: go-ssb and tildefriends both use bit-shifted EBT notes
**deciduous**: 358 [observation] "CONFIRMED: go-ssb and tildefriends both use bit-shifted EBT notes (seq<<1|flag)"
**confidence**: 99
**source**: go-ssb `ebt.go:32-81`, tildefriends `src/ssb.ebt.c:190-192,242`
**evidence**: go-ssb `Note.MarshalJSON()` encodes as `(seq << 1) | receive_flag` where receive_flag is INVERTED (0=wants, 1=doesn't). `UnmarshalJSON` decodes with `Seq = i >> 1`, `Receive = !(i & 1 == 1)`. tildefriends identical: `sequence >> 1` on receive, `(value << 1) | (receive ? 0 : 1)` on send. Special value `-1` = don't replicate.
**implication**: **Bidirectional sync failure confirmed.** Scuttle reads bit-shifted values as plain ints (2x inflation) AND sends plain ints that peers decode with `>>1` (2x deflation + wrong receive flag from LSB parity).

Example: peer has seq=5, wants to receive → sends note `(5<<1)|0 = 10`. Scuttle reads `remoteSeq=10`, thinks peer already has messages 1-10, skips sending messages 6-10 that peer actually needs.

Outgoing: Scuttle sends `5` for seq=5. Peer decodes `5>>1 = 2`, `5&1 = 1` → receive=false. Peer thinks Scuttle has seq 2 and does NOT want updates. Peer stops sending.

---
## [2026-03-22 13:00] EBT version 3 confirmed correct
**deciduous**: 359 [observation] "CONFIRMED: EBT version 3 is correct"
**confidence**: 99
**source**: go-ssb `sbot/replicate_negotiation.go:49`, `plugins/ebt/handler.go:87`, tildefriends `src/ssb.rpc.c:1221`
**evidence**: go-ssb sends `{"version": 3}` and rejects anything != 3. tildefriends sends v3. Scuttle sends `@{@"version": @3, @"format": @"classic"}`.
**implication**: Hypothesis #3 (version mismatch) DISPROVEN. Version negotiation is correct.

---
## [2026-03-22 13:00] Clock sent as stream data is correct
**deciduous**: 360 [observation] "CONFIRMED: Clock sent as stream data is correct approach"
**confidence**: 95
**source**: go-ssb `plugins/ebt/handler.go:109-130`
**evidence**: go-ssb `sendState()` writes clock via `json.NewEncoder(tx).Encode(currState)` — stream data on duplex, NOT in initial args. Initial args only contain `{"version": 3}`. Scuttle does the same: `sendData:clock forRequest:requestID isEnd:NO`.
**implication**: Hypothesis #5 (clock delivery method) DISPROVEN. The clock values themselves are the problem, not how they're delivered.
