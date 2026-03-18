---
name: ssb-protocol
description: Understanding and working with Secure Scuttlebutt protocols including feed formats (BendyButt, Buttwoo, Bamboo, GabbyGrove), encoding (Bencode, BIPF, BFE), encryption (Secret Handshake, BoxStream), and replication (EBT, MuxRPC).
---

# SSB Protocol Implementation for Scuttle

This skill provides expertise in the Secure Scuttlebutt (SSB) protocol implementations used in Scuttle.

## When to Use This Skill

Use this skill when you are:
- Working with message feeds, signing, or validation
- Implementing new SSB features or fixing protocol bugs
- Understanding how replication works
- Debugging message format or encoding issues
- Implementing new feed formats

## Protocol Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
├─────────────────────────────────────────────────────────────┤
│  Feed Formats: BendyButt | Buttwoo | Bamboo | GabbyGrove   │
├─────────────────────────────────────────────────────────────┤
│  Encoding: Bencode | BIPF | BFE                            │
├─────────────────────────────────────────────────────────────┤
│  Crypto: Ed25519 | BLAKE2b | BLAKE3 | HMAC-SHA512          │
├─────────────────────────────────────────────────────────────┤
│  Transport: Secret Handshake | BoxStream | MuxRPC          │
├─────────────────────────────────────────────────────────────┤
│  Network: TCP | Rooms | Tunnel                              │
└─────────────────────────────────────────────────────────────┘
```

## Key Protocols

### Feed Formats (Message Encoding)

| Format | File | Spec | Use Case |
|--------|------|------|----------|
| BendyButt | `SSBBendyButt.m` | SSB BIP | New feeds, supports encryption |
| Buttwoo | `SSBButtwoo.m` | SIP-011 | Modern format with BIPF |
| Bamboo | `SSBBamboo.m` | Legacy | Older SSB format |
| GabbyGrove | `SSBGabbyGrove.m` | Research | Future format |

### Encoding Formats

| Format | File | Description |
|--------|------|-------------|
| Bencode | `SSBBencode.m` | Classic SSB: `i123e`, `5:hello` |
| BIPF | `SSBBIPF.m` | Binary: varint tags + wire types |
| BFE | `SSBBFE.m` | Type/format prefixes for IDs |

### Cryptography

| Operation | Implementation | File |
|-----------|---------------|------|
| Ed25519 Sign | TweetNaCl | `tweetnacl.h/c` |
| Ed25519 Verify | TweetNaCl | `tweetnacl.h/c` |
| BLAKE2b-256 | Custom | `blake2b.h/c` |
| BLAKE3-256 | Custom | `blake3.h/c` |
| HMAC-SHA512 | CommonCrypto/OpenSSL | `SSBCommonCryptoCompat.h` |

### Replication

| Protocol | File | Description |
|----------|------|-------------|
| Secret Handshake | `SSBSecretHandshake.m` | Authenticated key exchange |
| BoxStream | `SSBBoxStream.m` | Symmetric encryption stream |
| MuxRPC | `SSBMuxRPC*.m` | Multiplexed RPC |
| EBT | `SSBRoomClient.m` (replication) | Explicit Block Transfer |

## Reference Files

- [FEED_FORMATS.md](references/FEED_FORMATS.md) - Feed format details
- [ENCODING_FORMATS.md](references/ENCODING_FORMATS.md) - Bencode, BIPF, BFE
- [CRYPTO.md](references/CRYPTO.md) - Cryptographic operations
- [REPLICATION.md](references/REPLICATION.md) - EBT and MuxRPC
- [FILE_REFERENCES.md](references/FILE_REFERENCES.md) - Source file locations
