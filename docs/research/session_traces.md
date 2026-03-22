# Session Traces Research

Hex-dump and packet trace findings from live debugging sessions. Used in Phase 0.5 (Instrument & Reproduce) to identify the exact packet where sync diverges.

**Logging boundaries**:
1. Post-SHS: raw box-stream encrypted bytes
2. Post-unbox: decrypted MuxRPC frames (9-byte header + body)
3. Post-parse: decoded request/response objects

**Diagnostic format**: `[MUX] [IN/OUT] flags={flags} len={len} req={req} body_preview={first_64_bytes}`

**Triage guide** — when sync stalls, the last log line reveals:
- Stopped receiving packets → box-stream or transport issue
- Received but not processed → MuxRPC dispatcher/routing issue
- Processed but not stored → verification or feed store issue

<!-- Template for new entries:
---
## [YYYY-MM-DD HH:MM] Trace Session Title
**deciduous**: node_ID [observation] "node title"
**confidence**: 0-100
**peer**: peer ID or "go-sbot" / "patchwork" for known-good comparison
**last_successful_packet**: direction, reqID, flags, body preview
**first_failed_packet**: direction, reqID, flags, body preview (or "none — stream stopped")
**triage**: box-stream | dispatcher | verification | unknown

[Hex dump or packet log excerpt...]
-->
