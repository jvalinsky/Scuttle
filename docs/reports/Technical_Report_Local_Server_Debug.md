# Technical Report: Local Server Connection Debugging

## 1. Problem Statement
The ScuttleKit GUI application was failing to list peers when connecting to a local `ssb-room-golang` server running in Docker. Initial logs showed that the Secret Handshake (SHS) was succeeding, but Subsequent MuxRPC communication was intermittent or failed entirely, resulting in an empty peer list.

## 2. Infrastructure Overview
The connection stack consists of:
1. **TCP (Network.framework)**: The underlying transport.
2. **SSBSecurityFramer**: Handles the Secret Handshake and BoxStream (XSalsa20-Poly1305) encryption/decryption.
3. **SSBMuxRPCFramer**: Handles the Scuttlebutt MuxRPC framing (9-byte header + body).
4. **SSBRoomClient**: High-level logic for Room v2 and legacy protocols.

## 3. Key Issues Identified

### A. Race Condition: SHS vs. MuxRPC
**Issue**: As soon as `nw_connection` reached the `ready` state, `SSBRoomClient` initiated the MuxRPC `manifest` and `whoami` requests. However, `SSBSecurityFramer` still needed to complete the SHS handshake before it could encrypt data.
**Effect**: Early MuxRPC packets were sent unencrypted or during a transitional state, causing the server to terminate the session.

### B. Framing Stalls & Partial Packets
**Issue**: The previous framer implementations used a simple `while` loop that assumed entire packets were always available in the buffer.
**Effect**: If a 9-byte MuxRPC header or a 34-byte BoxStream header was split across TCP segments, the framer would return 0, but sometimes fail to request the specific number of bytes needed for the next call. This led to "stalled" connections where no further `handleInput` calls were triggered.

### C. Incorrect Length Reporting
**Issue**: Confusion over whether `BoxStream` headers included the 16-byte MAC in the reported length led to `SSBSecurityFramer` requesting 18 bytes when it actually needed 34 (2 bytes length + 16 bytes MAC + 16 bytes overhead).

## 4. Implemented Solutions

### I. Output Buffering (Security Layer)
We introduced a `pendingOutputBuffer` in `SSBSecurityContext`. 
- **Behavior**: Any data sent by the upper layers (MuxRPC) while the handshake is in progress is queued.
- **Trigger**: Once the SHS handshake completes and the state transitions to `READY`, the buffer is automatically flushed and encrypted.
- **Benefit**: Ensures protocol-level synchronization without requiring the `SSBRoomClient` to wait for complex state callbacks.

### II. Stateful Parsing State Machines
Both `SSBSecurityFramer` and `SSBMuxRPCFramer` were refactored into robust state machines:
- **States**: `Header` and `Body`.
- **Mechanism**: The framer now explicitly tells `Network.framework` how many bytes it needs (e.g., `return 9` for a header). It only delivers data and moves to the `Body` state when exactly that many bytes are available.
- **Atomicity**: This ensures that partial packets are handled gracefully by the system rather than being misparsed by our code.

### III. Protocol Branching
We verified that `SSBRoomClient` correctly branches between:
- **Room v2**: `room.attendants` (source stream).
- **Legacy**: `tunnel.endpoints` (source stream).
This ensures compatibility with various versions of `ssb-room-golang`.

## 5. Verification Methodology
- **`local_test` binary**: A dedicated Objective-C CLI tool was used to iterate quickly without the GUI overhead.
- **Docker MuxRPC Tracing**: Enabled `-logs debug` in the `ssb-room-golang` server to inspect raw `rx`/`tx` MuxRPC traces.
- **Diagnostic Logging**: Implemented `[ROOM_DIAG]` prefixes for critical lifecycle events (connection states, message delivery).

## 6. Conclusion
The combination of **Output Buffering** in the security layer and **Stateful Parsing** in the framing layer has stabilized the connection. The client now reliably completes the initial RPC handshake and maintains long-lived source streams for peer discovery.
