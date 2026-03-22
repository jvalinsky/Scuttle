# Cross-Repo Comparative Findings

Synthesis of findings across all reference implementations (go-ssb, go-muxrpc, tildefriends, patchwork, planetary, sunrise-social). Entries here summarize cross-cutting patterns that span multiple protocol layers.

**Reference repos** (cloned to `/tmp/ssb-research/`):
- go-ssb (Go) - EBT, message formats
- go-muxrpc (Go) - MuxRPC framing
- go-secretstream (Go) - SHS/BoxStream
- tildefriends (C) - Full stack reference
- patchwork (JS) - Original desktop client
- planetary-desktop (JS) - Electron client
- sunrise-social-android (Kotlin/Rust) - Mobile client
- sips (Markdown) - Protocol specifications

<!-- Template for new entries:
---
## [YYYY-MM-DD HH:MM] Finding Title
**deciduous**: node_ID [observation] "node title"
**confidence**: 0-100
**repos_compared**: repo1, repo2, ...
**pattern**: what the reference impls agree on
**scuttle_divergence**: how Scuttle differs (if at all)

[Details...]
-->

---
## [2026-03-22 13:30] Cross-Repo Audit Summary — Two Critical Bugs Found
**deciduous**: 352 [goal] "Debug EBT sync failure"
**confidence**: 95
**repos_compared**: go-ssb, go-muxrpc, tildefriends, sips
**pattern**: All reference implementations agree on EBT note encoding and message envelope format
**scuttle_divergence**: TWO critical divergences cause complete sync failure

### Root Causes Identified

**Bug A: EBT Note Bit-Shift Encoding (Bidirectional)**
- `SSBRoomClient.m:1843` reads notes as plain integers
- All peers encode as `(seq << 1) | receive_flag`
- Scuttle's outgoing clock: peers decode with `>>1`, getting half the sequence + wrong receive flag
- Scuttle's incoming clock: interprets bit-shifted values as raw sequences (2x inflation)
- **Impact**: Both sides misunderstand each other's state → no messages flow

**Bug B: EBT Envelope Format (Outbound Only)**
- `SSBRoomClient.m:1868-1879` sends `{key, value}` wrapper
- All peers expect raw signed value dict with `author` at top level
- **Impact**: 100% of outbound EBT messages silently dropped by all peers

### Confirmed Correct
- EBT version 3 ✓
- Clock delivery as stream data ✓
- MuxRPC request ID sign convention ✓
- MuxRPC 9-byte header serialization ✓
- Box-stream nonce handling ✓
- Bilateral EBT negation ✓

### Secondary Issues (not sync-breaking but should fix)
- `SSBRoomClient.m:1187`: createHistoryStream missing `seq` field (performance)
- `SSBMessageCodec.m:324-334`: missing V8 binary transform (latent for non-ASCII)
- `SSBMessageCodec.m:180`: alphabetical content key sorting (may break verification)
