# MuxRPC Duplex Streams Research

Cross-repo findings on MuxRPC framing: flag bits, request ID sign convention, duplex stream lifecycle, JSON vs binary body types.

**Scuttle reference**: `Sources/SSBMuxRPCSession.m:100-118`, `Sources/SSBMuxRPCFramer.m`

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
## [2026-03-22 13:00] MuxRPC request ID sign convention is correct in Scuttle
**deciduous**: 362 [observation] "MuxRPC reqID sign convention appears correct in Scuttle"
**confidence**: 90
**source**: go-muxrpc `packer.go:72`, `codec/writer.go`, `rpc_server.go:265-296`; tildefriends `src/ssb.c:933`, `src/ssb.rpc.c:1107,1152`
**evidence**: go-muxrpc negates request IDs on READ (packer.go:72: `hdr.Req = -hdr.Req`) so higher-level code doesn't think about sign. On WRITE, the sign goes through as-is. Wire convention: initiator=positive, responder=negative. Scuttle handles this at the application layer: bilateral EBT at line 1744 negates (`-reqID`), `sendData:forRequest:` passes raw. The `(uint32_t)` cast in `SSBMuxRPC.m:34` preserves the bit pattern correctly — `-5` as `int32_t` → `0xFFFFFFFB` as `uint32_t` → same bytes on wire. tildefriends does the identical cast.
**implication**: Hypothesis #1 (reqID sign convention) is likely NOT the primary cause. The wire format is correct. Minor concern: `requestID:0` in EBT callback (line 1634) could cause issues if bilateral EBT request arrives via the callback path, but this is an unlikely edge case.

---
## [2026-03-22 13:00] go-muxrpc negates on read, Scuttle does not — design difference not bug
**deciduous**: 362 [observation] "MuxRPC reqID sign convention appears correct in Scuttle"
**confidence**: 95
**source**: go-muxrpc `packer.go:72`, Scuttle `SSBMuxRPC.m:56-59`
**evidence**: go-muxrpc `NextHeader()` flips sign after reading from wire — a convenience so higher-level code always sees "my requests positive, their requests negative." Scuttle passes through as-is, requiring application code to manage sign. Both approaches produce correct wire format.
**implication**: Not a bug, but makes Scuttle more fragile. Every callsite must manually manage sign. go-ssb's EBT handler never touches request IDs because the framework handles it via pre-configured stream objects.

---
## [2026-03-22 13:00] sendData:forRequest: does not validate request ID sign
**deciduous**: 362 [observation] "MuxRPC reqID sign convention appears correct in Scuttle"
**confidence**: 80
**source**: Scuttle `SSBMuxRPCSession.m:100-118`; go-muxrpc `rpc_server.go:296`, `rpc_client.go:263`
**evidence**: Scuttle blindly passes whatever requestID to the message constructor. go-muxrpc binds the correct ID to the stream at creation time — the sink always knows its own request ID.
**implication**: Fragility concern but not a current bug since all current callers pass correct signs.
