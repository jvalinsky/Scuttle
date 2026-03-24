# SSB EBT Sync Debugging — Reusable Session Prompt

You are debugging SSB EBT replication failure in **Scuttle**, an Objective-C SSB client for macOS. The client connects to rooms, lists peers, tunnels to peers, and begins EBT replication, but **full message sync never completes**. The connection either stalls, errors partway through replication, or silently stops receiving messages. This is reproducible across multiple peers, confirming the issue is in our client's protocol logic.

## Session Start: Context Recovery

Run these steps at the beginning of every session:

```bash
# 1. Decision graph state
deciduous nodes | grep -E "goal|decision|outcome|observation" | tail -30
deciduous edges | tail -20

# 2. Git state
git log --oneline -10
git status
```

Then read these scratchpads (skip if they don't exist yet):
- `docs/research/hypotheses.md` — current hypothesis ranking
- `docs/research/session_traces.md` — packet trace findings
- `docs/research/ebt_replication.md` — EBT findings
- `docs/research/muxrpc_duplex_streams.md` — MuxRPC findings
- `docs/research/message_envelope_format.md` — envelope findings
- `docs/research/cross_repo_findings.md` — cross-repo synthesis

## Phase Auto-Detection

Check conditions **in order**. Execute the **first** matching phase:

| Condition | Phase |
|-----------|-------|
| `hypotheses.md` has no ranked entries | **Phase 0**: Establish Baseline |
| `session_traces.md` has no trace entries | **Phase 0.5**: Instrument & Reproduce |
| Any layer scratchpad has < 3 cross-repo entries | **Phase 1**: Protocol Audit |
| No hypothesis marked CONFIRMED or DISPROVEN | **Phase 2**: Hypothesis Testing |
| A hypothesis is CONFIRMED | **Phase 3**: Fix Implementation |
| All tests pass after fix | **Done** |

---

## Phase 0: Establish Baseline

**Goal**: Identify the exact failure boundary and generate initial hypotheses.

### Steps

1. **Read the EBT replication code**:
   - `Sources/SSBRoomClient.m` lines 1597-1935 (entire `#pragma mark - Replication (EBT)` section)
   - Focus on: `startEBTReplicationWithSession:`, `handleEBTMessage:`, `handleBilateralEBT:`, `handleRemoteClockUpdate:`, `sendPendingMessagesForClock:`, `ebtEnvelopeForMessage:`, `processIncomingMessage:`

2. **Read the MuxRPC session code**:
   - `Sources/SSBMuxRPCSession.m` lines 60-130 (`sendRequest:`, `sendData:forRequest:isEnd:`)
   - `Sources/SSBMuxRPC.m` lines 22-63 (`serialize`, `parseHeader:` — header byte layout)

3. **Run existing E2E tests**:
   ```bash
   /build-test  # Run full test suite, note EBT test results
   ```

4. **Create deciduous goal node**:
   ```bash
   deciduous add goal "Debug EBT sync failure" -c 50 --prompt-stdin << 'PROMPT'
   [paste the verbatim user prompt that initiated this debugging session]
   PROMPT
   ```

5. **Write initial hypotheses** to `docs/research/hypotheses.md` (append, never edit prior entries).
   Generate >= 3 hypotheses based on the 8 suspect locations below. Seed with at minimum:
   - MuxRPC request ID sign convention (most common SSB interop bug)
   - EBT note bit-shift encoding mismatch
   - EBT version 3 vs expected 2

6. **Create deciduous option nodes** for each hypothesis:
   ```bash
   deciduous add option "Hypothesis: [title]" -c N -f "docs/research/hypotheses.md"
   deciduous link <goal_id> <option_id> -r "Candidate root cause"
   ```

### Checkpoint
`hypotheses.md` has >= 3 ranked entries with `status: UNTESTED`.

---

## Phase 0.5: Instrument & Reproduce

**Goal**: Capture a full session trace and identify the exact packet where sync diverges.

### Steps

1. **Add hex-dump logging at 3 protocol boundaries** (if not already present):
   - **Post-SHS**: raw box-stream encrypted bytes in `SSBSecurityFramer.m`
   - **Post-unbox**: decrypted MuxRPC frames (9-byte header + body) in `SSBMuxRPCFramer.m`
   - **Post-parse**: decoded request/response objects in `SSBMuxRPCSession.m`

   Use the diagnostic format at each boundary:
   ```
   [MUX] [IN/OUT] flags={flags} len={len} req={req} body_preview={first_64_bytes}
   ```
   Include millisecond-resolution timestamps and a **correlation ID** per connection.

2. **Capture a full session trace** from connection start to failure point. Run the app and connect to a peer. Log to a file.

3. **If possible**, run the same session against a known-good client (go-sbot or Patchwork) and diff the packet traces. The exact packet where traces diverge pinpoints the bug.

4. **Identify the last successful packet** and first failed/missing packet:
   - If we stopped receiving → box-stream or transport issue
   - If we received but didn't process → MuxRPC dispatcher/routing issue (check request ID sign)
   - If we processed but didn't store → verification or feed store issue

5. **Record findings** in `docs/research/session_traces.md` with deciduous observation nodes.

### Checkpoint
`session_traces.md` has >= 1 trace entry identifying the failure boundary.

---

## Phase 1: Cross-Repo Protocol Audit

**Goal**: Compare Scuttle's protocol implementation against reference codebases.

### Prerequisites
Clone reference repos if not already present:
```bash
ls /tmp/ssb-research/go-ssb 2>/dev/null || (
  mkdir -p /tmp/ssb-research && cd /tmp/ssb-research
  git clone --depth 1 https://github.com/ssbc/sips
  git clone --depth 1 https://github.com/ssbc/go-ssb
  git clone --depth 1 https://github.com/ssbc/go-muxrpc
  git clone --depth 1 https://github.com/ssbc/go-secretstream
  git clone --depth 1 https://github.com/soapdog/patchwork
  git clone --depth 1 https://github.com/planetary-social/planetary-desktop
  git clone --depth 1 https://github.com/sunrise-choir/sunrise-social-android-app
)
# tildefriends is at /tmp/tildefriends (local mirror — not cloneable via network)
```

### Launch 3 Parallel Research Agents

**AGENT 1 — MuxRPC & Request ID Sign Convention** (writes to `docs/research/muxrpc_duplex_streams.md`):

This is the **#1 priority** — request ID sign convention is the single most common SSB interop bug.

MuxRPC header spec: 9-byte header = 1 byte flags + 4 bytes body length (big-endian uint32) + 4 bytes request number (big-endian int32). Caller sends positive IDs, responder uses the **negative** of the caller's ID. A duplex stream uses the same |request number| in both directions.

| Question | Scuttle Location | Compare Against |
|----------|-----------------|-----------------|
| Request ID sign convention: initiator positive, responder negative? | `SSBMuxRPCSession.m:100-118` — `sendData:forRequest:` uses raw requestID | go-muxrpc `codec/packet.go`, `codec/reader.go`, `codec/writer.go` |
| Header serialization: `int32_t` → wire format | `SSBMuxRPC.m:34` — casts to `uint32_t` before byte-swap | go-muxrpc `codec/packet.go` |
| Duplex stream flag bits for data sends? | `SSBMuxRPCSession.m:101` — `SSBMuxRPCFlagStream` | go-muxrpc `codec/packet.go` |
| JSON flag set for clock dictionaries? | `SSBMuxRPCSession.m:111` — `SSBMuxRPCFlagTypeJSON` | go-muxrpc codec |
| How are duplex stream messages routed on receive? | `SSBMuxRPCSession.m:173-261` — `handleIncomingMessage` | go-muxrpc incoming message routing |
| Bilateral EBT: callback passes `requestID:0` | `SSBRoomClient.m:1634` — loses real reqID | go-ssb bilateral EBT handling |

Also check: when both an initiated AND bilateral EBT stream exist on the same session, can `handleEBTMessage` (line 1672) distinguish them? Currently `reqID=0` (from callback) vs real reqID (from `receiveRequestBlock`).

**AGENT 2 — EBT Protocol & Note Encoding** (writes to `docs/research/ebt_replication.md`):

EBT note encoding is **critical**: the spec uses bit-shifting where `sequence << 1 | receiveFlag`. The receive flag (lowest bit) indicates whether the peer wants to receive that feed. Our code at `SSBRoomClient.m:1843` reads notes as plain integers — if peers send bit-shifted values, all sequence comparisons are wrong by 2x.

| Question | Scuttle Location | Compare Against |
|----------|-----------------|-----------------|
| EBT note encoding: plain int or bit-shifted? | `SSBRoomClient.m:1843` — `[remoteClock[author] integerValue]` | go-ssb `plugins/ebt/handler.go`, `ebt.go` |
| What EBT version is sent? | `SSBRoomClient.m:1618` — `@{@"version": @3}` | go-ssb `plugins/ebt/handler.go` |
| Is clock sent as stream data or in args? | `SSBRoomClient.m:1637,1663` — args then sendData | go-ssb EBT handler |
| How are negative clock values interpreted? | `SSBRoomClient.m:1772-1785` — `seq < 0` = "don't want" | go-ssb EBT notes, sips spec |
| Bilateral EBT response format? | `SSBRoomClient.m:1724-1753` | go-ssb bilateral |

Also read `sips/*.md` for the authoritative EBT spec (especially note encoding).

**AGENT 3 — Message Envelope & Verification** (writes to `docs/research/message_envelope_format.md`):

| Question | Scuttle Location | Compare Against |
|----------|-----------------|-----------------|
| EBT envelope shape: `{key, value}` or other? | `SSBRoomClient.m:1868-1879` | go-ssb `message/legacy.go` |
| Does `value` include signature? | `SSBRoomClient.m:1906` — `includeSignature:YES` | go-ssb message codec |
| Incoming message verification assumptions? | `SSBRoomClient.m:1897` — `verifyMessage:val` | go-ssb verify |
| What if peer sends non-classic format? | `SSBRoomClient.m:1897` — only classic verify | patchwork JS (via `ssb-ebt` npm dep), go-ssb |
| createHistoryStream seq semantics? | `SSBRoomClient.m:1187` — missing `seq` field entirely | go-ssb `plugins/gossip/fetch.go` |
| Message signing canonical JSON encoding? | `SSBMessageCodec.m` — verify key ordering | go-ssb `message/legacy.go`, SHS test vectors |

Note: Patchwork's replication logic lives in npm dependencies (`ssb-ebt`, `ssb-replication-scheduler`, `packet-stream`), NOT in the patchwork repo itself. Check `node_modules/` or trace imports.

### After All Agents Complete

Synthesize cross-cutting findings into `docs/research/cross_repo_findings.md`.
Update hypothesis rankings in `docs/research/hypotheses.md` based on new evidence.

### Checkpoint
Each of the 3 layer scratchpads has >= 3 cross-repo comparison entries.

---

## Phase 2: Hypothesis Testing

**Goal**: Confirm or disprove the top-ranked hypothesis.

### Steps

1. Read `docs/research/hypotheses.md` — identify the #1 ranked hypothesis.
2. Read the relevant layer scratchpad for supporting evidence.
3. Design a **minimal** test:
   - If format/protocol issue: add wire-level assertion to `Tests/SSBEBTReplicationE2ETests.m`
   - If timing/state issue: add protocol trace logging via `os_log_debug`
   - If request ID sign issue: capture outbound packet headers and verify sign matches spec
4. Run the test:
   ```bash
   /build-test
   ```
5. Record result:
   ```bash
   # If CONFIRMED:
   deciduous add decision "Root cause: [description]" -c 90 -f "docs/research/hypotheses.md"
   deciduous link <option_id> <decision_id> -r "Hypothesis confirmed by test"

   # If DISPROVEN:
   deciduous add outcome "Disproved: [hypothesis]" -c 90
   deciduous link <option_id> <outcome_id> -r "Hypothesis disproved"
   ```
6. Append result to `docs/research/hypotheses.md` — update the entry's `status` field.
7. If disproven, move to hypothesis #2 and repeat.

### Checkpoint
At least one hypothesis has `status: CONFIRMED` or `status: DISPROVEN`.

---

## Phase 3: Fix Implementation

**Goal**: Fix the confirmed root cause and add regression coverage.

### Steps

1. Read the full deciduous chain:
   ```bash
   deciduous nodes | grep -E "goal|decision|outcome"
   deciduous edges | tail -20
   ```
2. Read the confirmed hypothesis entry in `docs/research/hypotheses.md`.
3. Implement the fix. Consider whether to:
   - Apply a **targeted fix** in `SSBRoomClient.m` (fast, minimal risk)
   - Extract **SSBEBTReplicator** class from the God Object (addresses architecture + fix)
4. Add a regression test to `Tests/SSBEBTReplicationE2ETests.m`.
5. Run the full suite:
   ```bash
   /build-test
   ```
6. Commit and record:
   ```bash
   git add [specific files]
   git commit -m "fix: [description of EBT sync fix]"
   deciduous add action "Fixed EBT sync: [description]" -c 95 --commit HEAD -f "Sources/SSBRoomClient.m"
   deciduous add outcome "EBT sync working" -c 95 --commit HEAD
   deciduous link <decision_id> <action_id> -r "Implementing fix"
   deciduous link <action_id> <outcome_id> -r "Fix verified"
   ```

### Checkpoint
All tests pass. Deciduous graph has complete chain: goal -> options -> decision -> action -> outcome.

---

## 8 Suspect Locations (Prioritized)

| # | File:Line | What | Why Suspicious |
|---|-----------|------|----------------|
| 1 | `SSBMuxRPCSession.m:100-118`, `SSBMuxRPC.m:34` | MuxRPC request ID sign convention | **Most common SSB interop bug.** Caller sends positive, responder negates. `SSBMuxRPC.m:34` casts `int32_t` to `uint32_t` for byte-swap. Also: `SSBRoomClient.m:1634` callback passes `requestID:0`, losing the real ID. |
| 2 | `SSBRoomClient.m:1843` | EBT note values treated as plain integers | EBT spec uses bit-shifted encoding: `seq << 1 \| receiveFlag`. If peers send bit-shifted notes, every sequence comparison is wrong by 2x. |
| 3 | `SSBRoomClient.m:1618` | EBT version: `@3` | Most Go/JS impls use version 2. Peer may silently reject unknown version. |
| 4 | `SSBRoomClient.m:1637,1663` | Clock sent as stream data after `sendRequest:args:` | Some impls expect clock IN the `args` array, not as a subsequent stream message. |
| 5 | `SSBRoomClient.m:1868-1879` | Envelope shape `{key, value}` | Some impls expect `{key, value, timestamp}` or a different structure entirely. |
| 6 | `SSBRoomClient.m:1897` | `verifyMessage:val` assumes classic ed25519 format | Non-classic messages (gabbygrove, bamboo) silently dropped by verification. Encoding flag also differs by feed format (JSON for classic, binary for bendy-butt/gabby-grove). |
| 7 | `SSBRoomClient.m:1187` | createHistoryStream missing `seq` field | Args are `{id, limit, reverse, live}` — no `seq`, so it fetches from beginning every time. Should be `latestSeq + 1`. |
| 8 | `SSBBoxStream.m:38-43,88-90` | Box-stream nonce counter drift | **Verified correct** — nonce advances by 2 per packet (header + body). Low priority but keep as fallback hypothesis. |

---

## Structured Logging Spec

Add structured logging at **3 protocol boundaries** with correlation IDs:

### Boundary 1: Post-SHS (Box-Stream Layer)
```
[BOX] [IN/OUT] conn={correlationID} bytes={length} nonce={current_nonce_hex_first_8}
```
Location: `SSBSecurityFramer.m`

### Boundary 2: Post-Unbox (MuxRPC Frame Layer)
```
[MUX] [IN/OUT] conn={correlationID} flags={flags_hex} len={bodyLen} req={reqNum} body_preview={first_64_bytes_hex}
```
Location: `SSBMuxRPCFramer.m` (already has `SSBMuxRPCEmitTrace` — extend with hex preview)

### Boundary 3: Post-Parse (RPC Session Layer)
```
[RPC] [IN/OUT] conn={correlationID} req={reqNum} type={JSON|string|binary} method={name_if_request} parsed_preview={first_128_chars}
```
Location: `SSBMuxRPCSession.m`

### Triage Guide
When sync stalls, check the **last log line** at each boundary:
- Last `[BOX]` but no matching `[MUX]` → box-stream decryption failure or framing issue
- Last `[MUX]` but no matching `[RPC]` → MuxRPC dispatcher routing issue (likely request ID sign)
- Last `[RPC]` but no `appendMessage` → verification failure or feed store issue

---

## Tiered E2E Test Plan

### Tier 1 — Must Have (sync correctness)
- [ ] Two clients connect and fully replicate a single feed with 10 messages. Both sides have identical logs at the end.
- [ ] Two clients replicate bidirectionally — each has messages the other doesn't. After sync, both are identical.
- [ ] A client with an empty database connects to a peer with 100+ messages and fully catches up.
- [ ] A client disconnects mid-sync and reconnects — replication resumes from where it left off, no duplicates, no gaps.

### Tier 2 — Should Have (robustness)
- [ ] Blob want/have negotiation completes and the blob is transferred.
- [ ] EBT frontier exchange produces the correct set of feed requests.
- [ ] Multiple concurrent feeds replicate without interference.
- [ ] A feed with >1000 messages replicates completely (tests streaming/chunking).

### Tier 3 — Nice to Have (hardening)
- [ ] Interop test against a live go-sbot instance.
- [ ] Fuzz testing of MuxRPC packet parsing (truncated headers, oversized bodies, negative lengths).
- [ ] Test against malformed/malicious packets.

---

## Key Files Quick Reference

| File | Lines | Purpose |
|------|-------|---------|
| `Sources/SSBRoomClient.m` | 1597-1935 | EBT replication (God Object) |
| `Sources/SSBMuxRPCSession.m` | 60-261 | RPC send/receive, duplex streams, message routing |
| `Sources/SSBMuxRPC.m` | 22-63 | 9-byte header serialize/parse |
| `Sources/SSBMuxRPCFramer.m` | all | Wire-level MuxRPC Network.framework framer |
| `Sources/SSBBoxStream.m` | all | Box-stream encrypt/decrypt, nonce management |
| `Sources/SSBSecurityFramer.m` | all | SHS + BoxStream as Network.framework framer |
| `Sources/SSBTunnelConnection.m` | all | Room tunnel -> P2P bridge |
| `Sources/SSBMessageCodec.m` | all | Classic message sign/verify/canonical JSON |
| `Sources/SSBFeedStore.m` | all | SQLite storage, localClock, appendMessage |
| `Tests/SSBEBTReplicationE2ETests.m` | all | E2E test harness |

---

## Scratchpad Rules

1. **APPEND ONLY** — never edit or delete prior entries
2. Every entry must reference a **deciduous node ID** (create the node first, then write the entry)
3. Every deciduous node must include `-f "docs/research/SCRATCHPAD.md"` for the **bidirectional link**
4. Use the entry template defined in each scratchpad file's header
5. Timestamps use `YYYY-MM-DD HH:MM` format

## Deciduous Rules

1. Create nodes **BEFORE** doing work (goals, actions)
2. Create outcome nodes **AFTER** work completes
3. **Link immediately** — every non-root node must be linked to its parent within the same step
4. Follow the canonical flow: `goal -> options -> decision -> actions -> outcomes`
5. Use `--commit HEAD` after any git commit
6. Use `--prompt-stdin` for verbatim user prompts on root goal nodes

---

## Agent Search Priorities Per Repo

| Repo | Language | Location | Search For | Key Paths |
|------|----------|----------|------------|-----------|
| go-ssb | Go | `/tmp/ssb-research/go-ssb` | EBT version, note encoding, envelope format, clock exchange | `plugins/ebt/handler.go`, `ebt.go`, `plugins/gossip/fetch.go`, `message/legacy.go` |
| go-muxrpc | Go | `/tmp/ssb-research/go-muxrpc` | Flag bits, reqID sign convention, duplex lifecycle, header format | `codec/packet.go`, `codec/reader.go`, `codec/writer.go`, `packer.go` |
| sips | Markdown | `/tmp/ssb-research/sips` | Authoritative protocol specs (EBT, MuxRPC, BFE, Metafeeds) | `001.md`–`011.md` |
| tildefriends | C | `/tmp/tildefriends` | Full-stack C reference | grep `ebt`, `muxrpc` in `src/*.c` |
| patchwork | JS | `/tmp/ssb-research/patchwork` | EBT, message format (replication in `ssb-ebt`, `packet-stream` npm deps) | `lib/plugins/`, `node_modules/ssb-ebt/`, `node_modules/packet-stream/` |
| planetary-desktop | JS | `/tmp/ssb-research/planetary-desktop` | Planetary's fork — different dep versions | `app/` directory |
| go-secretstream | Go | `/tmp/ssb-research/go-secretstream` | SHS/BoxStream reference (low priority) | `secrethandshake/state.go`, `boxstream/box.go`, `boxstream/unbox.go` |
| sunrise-social | Kotlin/Rust | `/tmp/ssb-research/sunrise-social-android-app` | Mobile EBT implementation | `android-patchql/`, `app/` |

## Protocol Quick Reference

### MuxRPC Header (9 bytes)
```
[flags:1][body_length:4 BE uint32][request_number:4 BE int32]
```
- Flags byte: bit 0-2 = body type (string=1, JSON=2, binary=0), bit 3 = stream, bit 4 = end/error
- Caller: positive request numbers. Responder: **negative** of caller's ID.
- Duplex: same |request number| in both directions.

### EBT Note Encoding
```
note = (sequence << 1) | receive_flag
```
- `receive_flag = 1`: peer wants to receive this feed
- `receive_flag = 0`: peer does NOT want this feed
- Sequence in the note = latest message the peer HAS
- Sender should start from `(note >> 1) + 1`
- A note of `-1` means "do not replicate this feed at all"

### createHistoryStream Args
```json
{"id": "@feedRef", "seq": latestSeq + 1, "live": false, "limit": -1}
```
- `seq` = first message to send (NOT last message you have — that's `latestSeq`)
- `limit: -1` = unlimited

### Box-Stream Packet
```
[header_mac:16][header_box:18][body:N]
```
- Header box decrypts to: `[body_length:2 BE uint16][body_mac:16]`
- Each packet uses 2 nonce values (header nonce, body nonce = header + 1)
- Stream nonce advances by 2 after each packet
