# SSB Feed Formats

SSB supports multiple feed formats for message encoding. Each has different characteristics and use cases.

## Overview

| Format | Encoding | Hash | Signature | Status |
|--------|----------|------|-----------|--------|
| BendyButt | Bencode | SHA-256 | HMAC-SHA512 | Current |
| Buttwoo | BIPF | BLAKE3 | Ed25519 | Modern |
| Bamboo | Binary | BLAKE2b | Ed25519 | Legacy |
| GabbyGrove | Protobuf | BLAKE2b | Ed25519 | Research |

## BendyButt

**File:** `Sources/SSBBendyButt.m`

**Structure:**
```
message = [payload, signature_bfe]
payload = [author_bfe, sequence, previous_bfe, timestamp, content_section]
signature = HMAC-SHA512("bendybutt", payload)
```

**Key Features:**
- Message keys: SHA-256 of `[payload, signature]`
- Content signing: HMAC-SHA512 with "bendybutt" prefix
- Supports encrypted content (Box1 format)

**Message Key Computation:**
```objc
// SSBBendyButt.m - messageKey calculation
NSMutableData *toHash = [NSMutableData dataWithData:payload];
[toHash appendData:signature];
NSData *key = ssb_hash_sha256(toHash);
```

## Buttwoo (SIP-011)

**File:** `Sources/SSBButtwoo.m`

**Structure:**
```
message = [payload, signature_bfe]
payload = [author_pubkey, sequence, previous_msgid, timestamp, content]
signature = Ed25519_detached(payload)
```

**Key Features:**
- BIPF encoding (binary)
- Message keys: BLAKE3-256 of `author_pubkey || sequence_BE`
- Deterministic, efficient

**Message Key Computation:**
```objc
// SSBButtwoo.m - message key using BLAKE3
uint8_t key[32];
blake3_hasher hasher;
blake3_hasher_init(&hasher);
blake3_hasher_update(&hasher, authorPubkey.bytes, 32);
// sequence as big-endian
uint8_t seqBE[4]; seqBE[0] = (seq >> 24) & 0xFF; // ...
blake3_hasher_update(&hasher, seqBE, 4);
blake3_hasher_final(&hasher, key);
```

## Bamboo

**File:** `Sources/SSBBamboo.m`

**Structure:**
```
author (32 bytes) | log_id (32 bytes) | is_end (1) | lipmaa (32) | 
seq (4) | payload_hash (32) | payload_size (4) | signature (64)
```

**Key Features:**
- Binary encoding (no tag bytes)
- Lipmaa links for skip-chain traversal
- Payload hash for integrity

## GabbyGrove

**File:** `Sources/SSBGabbyGrove.m`

**Structure:** Protocol Buffers with varint encoding

**Key Features:**
- Author: 32-byte Ed25519 key
- Sequence: varint
- Previous: optional 32-byte hash
- Lipmaa: optional 32-byte hash
- ContentHash: BLAKE2b-256

**Message Hash:**
```objc
// SSBGabbyGrove.m - content hash
+ (nullable NSData *)blake2b256:(NSData *)data {
    uint8_t digest[32];
    blake2b256(digest, data.bytes, data.length);
    return [NSData dataWithBytes:digest length:32];
}
```

## Choosing a Format

| Use Case | Recommended Format |
|----------|-------------------|
| New feed | Buttwoo (SIP-011) |
| Legacy compatibility | Bamboo |
| Encrypted content | BendyButt |
| Research/experimental | GabbyGrove |

## Feed Codec Registry

**File:** `Sources/SSBFeedCodecRegistry.m`

Scuttle uses a registry pattern to support multiple formats:

```objc
// Register formats
[SSBFeedCodecRegistry registerFormat:@"bendybutt" codec:[[SSBBendyButt alloc] init]];
[SSBFeedCodecRegistry registerFormat:@"buttwoo" codec:[[SSBButtwoo alloc] init]];
[SSBFeedCodecRegistry registerFormat:@"bamboo" codec:[[SSBBamboo alloc] init]];
[SSBFeedCodecRegistry registerFormat:@"gabbygrove-1" codec:[[SSBGabbyGrove alloc] init]];

// Get codec for format
id<SSBFeedCodec> codec = [SSBFeedCodecRegistry codecForFormat:@"buttwoo"];
```
