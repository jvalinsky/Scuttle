# Debug Journal - ScuttleKit RPC & EBT Sync

## 2026-03-11T19:57:53-04:00

### Current Issue
MuxRPC calls (specifically `ebt.replicate`) over established tunnels were failing. Symptoms included `muxrpc: no such command` errors or silence (no data flow) despite successful tunnel establishment.

### What was tried
1.  **Buffer MuxRPC messages**: Added logic in `SSBTunnelConnection` to hold messages until SHS handshake is complete.
2.  **Robust MuxRPC ID Matching**: Discovered that different room implementations/peers might flip the sign of request IDs in responses. Updated `SSBMuxRPCSession` to match IDs against both raw and absolute values.
3.  **Binary Payload Support**: Added `NSData` handling to `SSBRoomClient`'s `handleEBTMessage` and `processIncomingMessage` because EBT sends raw message blocks as binary rather than JSON-wrapped objects in some cases.
4.  **Standardized Logging**: Added `[RPCSession]`, `[EBT]`, and `[Tunnel]` prefixes to trace data flow through the stack.

### Build Regression during Diagnostic Logging
When adding session pointer and callback pointer logging:
- `SSBMuxRPCSession.m`: Mixed up brackets and dropped an `if (callback)` check. Also required `(__bridge void *)` for ARC compliance on block pointer logging.
- `SSBRoomClient.m`: Accidentally nested a method definition inside `replicateFromPeer:viaRoom:`.

### Results
- *Fixing Build*: Currently restoring file structure and ARC compliance.
- *Fixing SSBTunnelConnection*: Discovered `NW_MAX_FRAME_SIZE` was missing and a non-existent `nw_connection_receive_with_framer` was being used.
- *Diagnostic Findings*: `grep` shows no `[Tunnel]` or `[EBT]` logs. This suggests `onConnectionStateReady` is never called, meaning the SHS handshake over the tunnel is stalling.

### Next Plan
- Add raw byte tracing to `SSBTunnelConnection.m`'s pipe (`readFromServerConnection` and `receiveTunnelData`).
- Verify if `clientHello` is ever sent by the `clientConnection` framer.
- Verify if `serverHello` is ever received via the room session.
- MONITOR: `receiveTunnelData` is active (receiving data from Room), but `readFromServerConnection` is silent.
- **DICOVERY**: `readFromServerConnection` IS active! It sent 64 bytes (SHS `clientHello`).
- **DICOVERY**: Handshake is progressing! 64 bytes received (`serverHello`), 112 bytes sent (`clientAuthenticate`).
- **NEXT PROBLEM**: Remote peer rejects authentication immediately after 112 bytes sent (Room receives `flags=14` error response).
- **CRITICAL BUG FOUND**: `nw_connection_send` was using `is_complete: true`, likely sending a FIN packet after every chunk, causing the stream to close.
- **SUCCESS**: Changing `is_complete` to `false` allowed the handshake to complete.
- **SUCCESS**: EBT replication is now running over the tunnel session.

## 2026-03-11T21:37:37-04:00

### Progress: UI Polishing & Final Cleanup
1.  **Notification Bridge**: Added `SRRoomSyncStatusChangedNotification` to `SSBRoomClient.m` so that UI views (Peer List, Profile) can react to background sync updates without manual polling.
2.  **Granular States**: Implemented more specific lifecycle states:
    - `Connecting...`: Tunnel initialization.
    - `Handshaking...`: SHS session setup.
    - `Receiving: X/Y`: Active message replication.
    - `Ready`: Synchronization complete.
3.  **Refactoring**: Extracted `reportSyncStatus:progress:author:` in `SSBRoomClient.m` to deduplicate notification logic and ensure consistency.
4.  **Bug Fixes**: 
    - Resolved `ebtCallback` uninitialized block warning.
    - Fixed a retain cycle in `ebtCallback` logging by using a weak reference/simpler logging.

### Final Result
- Full EBT replication is functional over MuxRPC tunnels.
- The UI (Peer List and Profile Header) now correctly reflects real-time synchronization progress.
- Clean build with no warnings.

**Session Concluded.**
