# EBT Sync Failure Hypotheses

Ranked by likelihood. Append-only: new findings go at the bottom.
Mark entries CONFIRMED or DISPROVEN with evidence when tested.

<!-- Template for new entries:
---
## [YYYY-MM-DD HH:MM] Hypothesis Title
**deciduous**: node_ID [option] "node title"
**rank**: N
**confidence**: 0-100
**status**: UNTESTED | CONFIRMED | DISPROVEN
**suspect_location**: file:line
**evidence_for**: what supports this hypothesis
**evidence_against**: what contradicts it
**test_plan**: how to verify

[Details...]
-->

---
## [2026-03-22 12:00] MuxRPC Request ID Sign Convention Bug
**deciduous**: 353 [option] "Hypothesis: MuxRPC request ID sign convention bug"
**rank**: 1
**confidence**: 75
**status**: DISPROVEN (wire format correct, design difference not a bug)
**suspect_location**: SSBMuxRPCSession.m:100-118, SSBMuxRPC.m:34, SSBRoomClient.m:1634
**evidence_for**: This is documented as the single most common interop bug across SSB implementations. The MuxRPC spec requires caller=positive, responder=negative request IDs. Our `SSBMuxRPC.m:34` casts `int32_t` to `uint32_t` before byte-swapping — bit pattern is preserved but needs verification against go-muxrpc. Additionally, `SSBRoomClient.m:1634` passes `requestID:0` in the EBT callback, losing the real request ID for initiated streams.
**evidence_against**: Bilateral EBT at line 1744 correctly negates the incoming reqID. The `(uint32_t)` cast preserves the sign bit through the round-trip.
**test_plan**: Compare our serialized 9-byte header against go-muxrpc `codec/packet.go` for identical request IDs. Add a test that captures outbound packet headers and verifies sign matches spec for both initiator and responder cases.

The MuxRPC protocol uses a 9-byte header: 1 byte flags, 4 bytes body length (BE uint32), 4 bytes request number (BE int32). The critical invariant: caller sends positive IDs, responder uses the negative of the caller's ID. A duplex stream (like EBT) uses the same |request number| in both directions. If this is wrong, responses get routed to nowhere — the peer receives our messages but can't correlate them.

---
## [2026-03-22 12:00] EBT Note Bit-Shift Encoding Mismatch
**deciduous**: 354 [option] "Hypothesis: EBT note bit-shift encoding mismatch"
**rank**: 2
**confidence**: 70
**status**: CONFIRMED — go-ssb ebt.go:32-81 and tildefriends ssb.ebt.c:190-242 both use bit-shifting
**suspect_location**: SSBRoomClient.m:1843
**evidence_for**: The EBT spec encodes notes as `sequence << 1 | receiveFlag`. Our code at line 1843 does `remoteSeq = [remoteClock[author] integerValue]` treating notes as plain integers. If peers send bit-shifted values (e.g., seq=5 becomes note=11), we'd interpret `11` as the sequence number instead of `5`, making every comparison wrong by approximately 2x.
**evidence_against**: Our own clock is also sent as plain integers (line 1663), so if the peer also doesn't bit-shift, both sides agree. Need to verify what go-ssb actually sends.
**test_plan**: Read go-ssb `plugins/ebt/handler.go` and check how notes are encoded/decoded. If they use bit-shifting, this is confirmed. Add a test that encodes/decodes EBT notes with bit-shifting and verifies against our current code.

The EBT note encoding formula: `note = (sequence << 1) | receive_flag`. The receive flag (lowest bit) indicates whether the peer wants to receive that feed. Sequence in the note = latest message the peer HAS, so the sender should start from `(note >> 1) + 1`.

---
## [2026-03-22 12:00] EBT Version 3 Rejected by Peers
**deciduous**: 355 [option] "Hypothesis: EBT version 3 rejected by peers expecting version 2"
**rank**: 3
**confidence**: 60
**status**: DISPROVEN — all implementations use version 3
**suspect_location**: SSBRoomClient.m:1618
**evidence_for**: Our code sends `@{@"version": @3, @"format": @"classic"}`. Most Go/JS implementations may use version 2. If the peer rejects version 3, the duplex stream opens but no data flows — the clock IS sent (line 1663) but the peer may silently ignore it.
**evidence_against**: EBT v3 is the current spec version. Need to verify what go-ssb and patchwork actually expect.
**test_plan**: Check go-ssb and patchwork for the EBT version they send/accept. If they only support v2, this explains the stall.

---
## [2026-03-22 13:30] EBT Envelope {key,value} Wrapper — Peers Expect Raw Value
**deciduous**: 365 [option] "Hypothesis: EBT envelope {key,value} wrapper — peers expect raw value"
**rank**: 1 (ELEVATED — co-primary with #2)
**confidence**: 95
**status**: CONFIRMED — go-ssb handler.go:174-203 and tildefriends ssb.rpc.c:1075,1176 both expect raw value
**suspect_location**: SSBRoomClient.m:1868-1879
**evidence_for**: go-ssb's EBT handler looks for `"author"` at the TOP LEVEL of the JSON body. tildefriends sends with `keys=false` (raw value) and receives by checking `"author"` at top level. Scuttle wraps in `{key, value}` — the `author` field is nested under `value`, invisible to peers.
**evidence_against**: None. All reference implementations agree.
**test_plan**: Send a raw value dict (without {key,value} wrapper) and verify the peer accepts it.

**This bug causes 100% of Scuttle's outbound EBT messages to be silently dropped by all peers.** The fix: in `ebtEnvelopeForMessage:`, return `valueDict` directly instead of `@{@"key": msg.key, @"value": valueDict}`.

---
## [2026-03-22 13:30] Missing V8 Internal Binary Transform in Message Key Computation
**deciduous**: 366 [option] "Hypothesis: Missing V8 binary transform in message key computation"
**rank**: 6
**confidence**: 90
**status**: CONFIRMED (latent — only affects non-ASCII messages)
**suspect_location**: SSBMessageCodec.m:324-334
**evidence_for**: go-ssb `verify.go:123-131` calls `InternalV8Binary()` which converts UTF-8 to UTF-16LE then drops every other byte before SHA256 hashing. Scuttle hashes raw UTF-8. For ASCII, results are identical. For non-ASCII (emoji, accented chars), hashes differ.
**evidence_against**: Most SSB messages are ASCII-only, making this latent.
**test_plan**: Compute message key for a message containing emoji in both methods. Compare.

---
## [2026-03-22 13:30] Content Key Alphabetical Sorting Breaks Signature Verification
**deciduous**: 367 [option] "Hypothesis: Content key alphabetical sorting breaks signature verification"
**rank**: 7
**confidence**: 80
**status**: UNTESTED (likely contributes to verification failures)
**suspect_location**: SSBMessageCodec.m:180
**evidence_for**: `jsonEncodeObject:indent:` sorts dict keys alphabetically. go-ssb preserves original key ordering. NSDictionary loses insertion order. If content keys are reordered during re-serialization, the signed bytes change and signatures fail.
**evidence_against**: If all content dicts happen to already be alphabetically ordered, this wouldn't trigger.
**test_plan**: Take a known-good signed message with non-alphabetical content keys. Re-serialize with Scuttle's codec. Check if signature verification passes.

---
## [2026-03-22 12:00] createHistoryStream Missing seq Field
**deciduous**: 356 [option] "Hypothesis: createHistoryStream missing seq field"
**rank**: 4
**confidence**: 55
**status**: CONFIRMED (performance bug only, not sync-breaking)
**suspect_location**: SSBRoomClient.m:1187
**evidence_for**: The createHistoryStream args at line 1187 are `{id, limit, reverse, live}` — no `seq` field. This means every call fetches from the beginning. The spec requires `seq: latestSeq + 1` to request only new messages. This wastes bandwidth and may cause the peer to timeout or rate-limit us.
**evidence_against**: This may only affect local feed sync (line 1187), not EBT replication which uses a different code path (line 2060). The EBT path at line 1851 correctly uses `fromSequence: remoteSeq + 1`.
**test_plan**: Verify the createHistoryStream args against go-ssb `plugins/gossip/fetch.go`. Check if the missing seq causes the peer to send ALL messages, potentially overwhelming the connection.

---
## [2026-03-22 12:00] EBT Clock Sent as Stream Data vs Expected in Args
**deciduous**: 357 [option] "Hypothesis: EBT clock sent as stream data vs expected in args"
**rank**: 5
**confidence**: 50
**status**: DISPROVEN — all implementations send clock as stream data
**suspect_location**: SSBRoomClient.m:1637,1663
**evidence_for**: Our code sends the EBT request with args `{version:3, format:classic}` (line 1637), then sends the clock as a separate `sendData:clock` call (line 1663). Some implementations might expect the clock IN the initial request args array.
**evidence_against**: The EBT protocol is a duplex stream — sending the clock as the first stream message is the standard pattern. Need to verify against go-ssb.
**test_plan**: Check go-ssb EBT handler for how it sends the initial clock — as args or as stream data.
