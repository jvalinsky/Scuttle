---
name: ssb-room-debug
description: Debug and test the Scuttle CLI against a live go-ssb-room instance running in Docker. Covers connection testing, Secret Handshake tracing, MuxRPC inspection, peer discovery, and EBT sync verification.
---

# SSB Room Debug Harness

This skill provides tools and workflows for testing the Scuttle CLI implementation
against a live `go-ssb-room` server running in Docker.

## When to Use This Skill

Use this skill when you are:
- Testing `scuttle-cli connect` against a real SSB room
- Debugging Secret Handshake failures
- Inspecting MuxRPC message framing
- Verifying peer discovery (tunnel/connect endpoint)
- Testing EBT sync correctness
- Comparing our implementation against go-ssb-room behavior
- Working on the GNUstep Linux port and need integration tests

## Quick Start

```bash
# 1. Start the room
docker compose up ssb-room -d

# 2. Wait for it to be healthy
docker compose ps ssb-room

# 3. Get the room's public key
tools/debug/ssb-room-harness.sh pubkey

# 4. Build scuttle-cli (Linux/GNUstep)
tools/debug/ssb-room-harness.sh build

# 5. Run a full connection test
tools/debug/ssb-room-harness.sh test-connect

# 6. Run all integration tests
tools/debug/ssb-room-harness.sh test-all
```

## Harness Scripts

All scripts live in `tools/debug/`:

| Script | Purpose |
|--------|---------|
| `ssb-room-harness.sh` | Main entrypoint - orchestrates all tests |
| `trace-handshake.sh` | Capture and decode SHS handshake bytes |
| `inspect-muxrpc.sh` | Decode MuxRPC frames from pcap |
| `check-ebt-sync.sh` | Verify EBT sync messages are correct |
| `room-info.sh` | Print room public key and capabilities |

## Test Scenarios

### 1. Identity Init + Whoami

```bash
tools/debug/ssb-room-harness.sh test-identity
```

Verifies:
- `scuttle-cli init` creates a valid Ed25519 keypair
- `scuttle-cli whoami` outputs a valid `@<pubkey>.ed25519` ID
- Metafeed root is bootstrapped

### 2. Room Connection (SHS + BoxStream)

```bash
tools/debug/ssb-room-harness.sh test-connect
```

Verifies:
- TCP connection to room on port 8008
- Secret Handshake completes (3-step: hello, auth, accept)
- BoxStream encryption is established
- `shs.rpc.manifest` call succeeds

### 3. Endpoint Discovery (Peer List)

```bash
tools/debug/ssb-room-harness.sh test-peers
```

Verifies:
- `tunnel.endpoints` subscription works
- Attendant events are received
- `tunnel.connect` can establish tunnel to a peer

### 4. EBT Sync

```bash
tools/debug/ssb-room-harness.sh test-ebt
```

Verifies:
- `ebt.replicate` RPC is called with correct clock format
- Messages are received and stored correctly
- Bilateral replication works (both sides send clocks)

## Network Tracing

### Capture SHS Handshake

```bash
# In one terminal: start trace
tools/debug/trace-handshake.sh capture

# In another: run connection
scuttle-cli connect localhost

# Stop and decode
tools/debug/trace-handshake.sh decode
```

### Inspect with tcpdump

```bash
# Trace all port 8008 traffic
docker compose exec ssb-room sh -c "tcpdump -i any -w /tmp/ssb.pcap port 8008 &"
# ... run tests ...
docker compose cp ssb-room:/tmp/ssb.pcap ./debug-capture.pcap
```

## Room Configuration

The Docker room runs in `open` mode, meaning:
- Anyone can connect without an invite (for testing)
- HTTP dashboard at http://localhost:3000
- MuxRPC at localhost:8008
- Room public key is derived from `/data/secret` inside the container

## Getting the Room Public Key

```bash
# Via HTTP API (if dashboard enabled)
curl -sf http://localhost:3000/room | jq .

# Via harness script
tools/debug/ssb-room-harness.sh pubkey

# Direct - read from container
docker compose exec ssb-room cat /data/secret 2>/dev/null || \
  docker compose exec ssb-room ls /data/
```

## Protocol Layers Tested

```
┌─────────────────────────────────────────────┐
│  scuttle-cli commands (init, connect, peers) │  ← CLI layer
├─────────────────────────────────────────────┤
│  SSBRoomClient (tunnel.endpoints, ebt)       │  ← App layer
├─────────────────────────────────────────────┤
│  SSBMuxRPCSession (framing, multiplexing)    │  ← RPC layer
├─────────────────────────────────────────────┤
│  SSBBoxStream (symmetric encryption)         │  ← Crypto layer
├─────────────────────────────────────────────┤
│  SSBSecretHandshake (key exchange)           │  ← Handshake
├─────────────────────────────────────────────┤
│  TCP/IP to go-ssb-room:8008                  │  ← Transport
└─────────────────────────────────────────────┘
```

## Known Failure Modes

| Symptom | Likely Cause | Debug Step |
|---------|--------------|------------|
| Handshake stalls at step 1 | Wrong room pubkey in invite | `harness.sh pubkey` to verify |
| Handshake fails at step 2 | Local identity corrupted | `scuttle-cli init` (fresh) |
| MuxRPC manifest call hangs | BoxStream decrypt error | trace-handshake.sh decode |
| No peers in endpoint list | Room in `community` mode | Check docker-compose mode flag |
| EBT clock rejected | Clock format wrong | check-ebt-sync.sh |
| Tunnel connect fails | Peer not attending room | test-peers first |

## GNUstep-Specific Issues

When building with GNUstep on Linux:

| Issue | File | Status |
|-------|------|--------|
| `os/log.h` missing | `SSBLogCompat.h` | Shim exists |
| `CommonCrypto` missing | `SSBCommonCryptoCompat.h` | Shim exists |
| `Security.framework` missing | `SSBKeychain_Linux.m` | Linux impl exists |
| `dispatch_data_t` differences | Various | Use `#ifdef __APPLE__` guards |
| `NSURLSession` differences | `SSBURLSessionShim.m` | Shim exists |

## References

- [ROOM_PROTOCOL.md](references/ROOM_PROTOCOL.md) - go-ssb-room protocol details
- [SHS_PROTOCOL.md](references/SHS_PROTOCOL.md) - Secret Handshake spec
- [MUXRPC_FRAMES.md](references/MUXRPC_FRAMES.md) - MuxRPC wire format
