# SSB Protocol File References

## Core Protocol Files

| File | Purpose |
|------|---------|
| `Sources/SSBBendyButt.m` | BendyButt feed format |
| `Sources/SSBButtwoo.m` | Buttwoo feed format (SIP-011) |
| `Sources/SSBBamboo.m` | Bamboo feed format |
| `Sources/SSBGabbyGrove.m` | GabbyGrove feed format |
| `Sources/SSBBencode.m` | Bencode encoding/decoding |
| `Sources/SSBBIPF.m` | BIPF binary encoding |
| `Sources/SSBBFE.m` | BFE type/format encoding |

## Cryptography

| File | Purpose |
|------|---------|
| `Sources/tweetnacl.h` | TweetNaCl header (Ed25519, xsalsa20poly1305) |
| `Sources/tweetnacl.c` | TweetNaCl implementation |
| `Sources/blake2b.h` | BLAKE2b header |
| `Sources/blake2b.c` | BLAKE2b implementation |
| `Sources/blake3.h` | BLAKE3 header |
| `Sources/blake3.c` | BLAKE3 implementation |
| `Sources/SSBCommonCryptoCompat.h` | CommonCrypto → OpenSSL shim |

## Replication

| File | Purpose |
|------|---------|
| `Sources/SSBSecretHandshake.m` | Secret Handshake protocol |
| `Sources/SSBBoxStream.m` | xsalsa20poly1305 stream encryption |
| `Sources/SSBMuxRPC.m` | MuxRPC message structure |
| `Sources/SSBMuxRPCFramer.m` | Network.framework framer |
| `Sources/SSBMuxRPCSession.m` | MuxRPC session management |
| `Sources/SSBRoomClient.m` | EBT replication implementation |

## Feed Storage

| File | Purpose |
|------|---------|
| `Sources/SSBFeedStore.m` | SQLite message storage |
| `Sources/SSBFeedCodecRegistry.m` | Feed format registry |
| `Sources/SSBMessageCodec.m` | Message encoding/decoding |

## Network

| File | Purpose |
|------|---------|
| `Sources/SSBNetwork.h/m` | Network management |
| `Sources/SSBConnectionFSM.h/m` | Connection state machine |
| `Sources/SSBTunnelConnection.h/m` | Tunnel connections |
| `Sources/SSBRoomClient.h/m` | Room client (includes replication) |

## Testing

| File | Purpose |
|------|---------|
| `Tests/SSBMetafeedTests.m` | Metafeed tests |
| `Tests/SSBBendyButtTests.m` | BendyButt tests |
| `Tests/SSBButtwooTests.m` | Buttwoo tests |

## Related Documentation

- `plans/PLAN_01_CRYPTO_HASH.md` - Cryptographic hash fixes
- `plans/PLAN_03_SPEC_COMPLIANCE.md` - Spec compliance
- `plans/PLAN_05_PROTOCOL.md` - Protocol improvements
- `plans/topics/GIT_SSB_PLAN.md` - Git-SSB integration plan
