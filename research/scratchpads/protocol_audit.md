## 2026-03-22: Initial Brainstorming on Sync Failures

### Potential Issues identified in ScuttleKit:
1. **Canonical JSON Serialization (Classic Feed)**:
   - `SSBMessageCodec.m` uses `%g` for doubles and a custom `jsonEncodeObject:indent:` for dictionaries.
   - V8's `JSON.stringify` has very specific rules for number formatting (e.g., `-0`, scientific notation thresholds, and integer representation).
   - If our canonicalization differs by even one space or decimal point, `verifyMessage:` will fail for incoming EBT messages (which are raw values).
   - *Observation*: Node 364 in Deciduous mentions alphabetical sort might break verification—this needs to be cross-referenced with V8 specs.

2. **EBT Protocol Nuances**:
   - **Note Encoding**: We use `(seq << 1) | 0`. This matches `go-ssb` and `tildefriends` for v3.
   - **Envelope Format**: We send raw value dictionaries. Node 361 confirms peers expect this.
   - **Bilateral Race**: `SSBRoomClient.m` starts EBT on tunnel ready. If both sides start simultaneously, we need to ensure MuxRPC request IDs don't collide. `SSBMuxRPCSession` uses positive IDs for outgoing, so bilateral responses (negated) should be safe.

3. **Separation of Concerns**:
   - `SSBRoomClient.m` is a "God Object" (2700+ lines). It handles transport, MuxRPC, EBT, and UI state.
   - Logic errors are easily hidden in the complex state management of `clientQueue` and `dispatch_async` blocks.

4. **MuxRPC `EndErr` Handling**:
   - `SSBMuxRPCSession.m` handles `EndErr` by executing the callback.
   - If a peer sends a final value *with* the `EndErr` flag, we might be processing it as an error or a final result inconsistently depending on whether `isStream` is set.

5. **Blob Syncing**:
   - `SSBBlobStore.m` fetches blobs via `blobs.get`. 
   - It accumulates the entire blob in memory (`NSMutableData`). For large blobs, this could cause memory pressure or stalls.

### Exploration Plan for Reference Implementations:
- **Patchwork (JS)**: The "Gold Standard" for Classic JSON canonicalization. Must verify `ssb-keys` and `canonical-json` logic.
- **go-ssb (Go)**: Check EBT implementation in `replicate/ebt`. Note how it handles the "stranger" edge case and bilateral clock exchanges.
- **tildefriends (ObjC)**: Compare `SSBRoomClient` logic with `TFClient` or equivalent. Look for differences in `muxrpc` framer handling.

## 2026-03-22: Reference Research Findings

### Canonical JSON (Patchwork & go-ssb Audit):
1. **Key Order Preservation**: 
   - *Normative*: The protocol guide specifies that dictionary keys must be in the **same order as received** for signature verification and ID computation.
   - *ScuttleKit Bug*: `SSBMessageCodec.m` re-encodes using a fixed hardcoded order for top-level keys and **alphabetical sorting** for `content` keys.
   - *Impact*: If a peer sends a message with non-standard top-level order or non-alphabetical `content` order, ScuttleKit will fail to verify it.
   - *EBT Context*: EBT transmits raw message objects. If ScuttleKit parses them into `NSDictionary` before verification, it loses the order information.

2. **V8 Binary Transform**:
   - *Confirmed*: Both ScuttleKit and go-ssb's `InternalV8Binary` take the low byte of each UTF-16 code unit. This matches V8's `Buffer(str, 'binary')`.

3. **Number Formatting**:
   - *Risk*: ScuttleKit uses `%g`. go-ssb uses `UseNumber: true` to preserve the original string. V8 has complex rules. If a message contains a float like `1.0`, V8 might stringify it as `1`, but `%g` might produce `1`. This needs extreme care.

### EBT Protocol (go-ssb & tildefriends Audit):
1. **Simultaneous Initiation**: Both peers can send `["ebt", "replicate"]`. Responses are negated IDs. ScuttleKit handles this.
2. **Note Encoding**: `(seq << 1) | flag` is standard for v3.
3. **Replication Loop**: go-ssb uses `CreateStreamHistory` to pipe messages directly. ScuttleKit uses `sendPendingMessagesForClock:`.

### Blob Syncing:
- ScuttleKit has no automatic blob syncing in `SSBRoomClient.m`. It only checks `blobs.has`. 
- Peers normally don't "push" blobs via EBT; the client must see a mention and call `blobs.get`.

## Plan for Implementation (Narrowing Down):
1. **Fix Message Verification**:
   - Modify `SSBRoomClient.m` to pass raw `NSData` to `SSBMessageCodec` where possible.
   - Update `SSBMessageCodec` to support a more "tolerant" verification or a way to preserve incoming bytes.
2. **Refactor SSBRoomClient**:
   - Extract EBT logic into `SSBEBTHandler`.
   - Extract Blob logic into `SSBBlobSyncer`.
3. **E2E Test Suite**:
   - Implement `SSBRoomSyncTests.m` using two clients and a loopback mock.
