# SSB Encoding Formats

## Overview

| Format | File | Type | Use |
|--------|------|------|-----|
| Bencode | `SSBBencode.m` | Textual | Classic SSB |
| BIPF | `SSBBIPF.m` | Binary | Modern (SIP-011) |
| BFE | `SSBBFE.m` | Binary | Type prefixes |

## Bencode (Classic SSB)

**File:** `Sources/SSBBencode.m`

A simple text-based encoding used in classic SSB.

### Types

**Integer:**
```
i123e    → 123
i-45e    → -45
```

**String:**
```
5:hello  → "hello"
0:       → ""
```

**List:**
```
l5:helloi123ee  → ["hello", 123]
```

**Dictionary:**
```
d3:foo5:hello3:bari123ee  → {"foo": "hello", "bar": 123}
```

### Implementation

```objc
// Encode
+ (NSData *)encode:(id)obj {
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [@"i" stringByAppendingString:[obj stringValue]];
    } else if ([obj isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"%lu:%@", (unsigned long)len, obj];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        // ...
    }
}

// Decode
+ (id)decode:(NSData *)data {
    // Tokenize and parse
}
```

## BIPF (Binary In-Place Format)

**File:** `Sources/SSBBIPF.m`

A compact binary encoding for modern SSB (SIP-011).

### Wire Types (3-bit)

| Wire Type | Value | Meaning |
|-----------|-------|---------|
| 0 | String | varint length + UTF-8 |
| 1 | Bytes | varint length + raw bytes |
| 2 | Int | signed varint |
| 3 | Double | IEEE 754 double |
| 4 | List | varint count + elements |
| 5 | Dict | varint count + key-value pairs |
| 6 | Boolean | 0 = false, 1 = true |
| 7 | Null | no value |

### Encoding

```objc
// BIPF encode string
// Tag: (type << 5) | (length % 32) for length < 32
// Or: 0x1F followed by varint length, then type << 5

uint8_t tag = (wireType << 5) | (length & 0x1F);
[data appendBytes:&tag length:1];
if (length >= 32) {
    // Write varint length
    writeVarint(data, length);
}
[data appendBytes:str length:length];
```

### Varint Encoding

BIPF uses unsigned LEB128 (Little Endian Base 128):

```c
// Write varint
void writeVarint(NSMutableData *data, uint64_t value) {
    while (value >= 128) {
        uint8_t byte = (value & 0x7F) | 0x80;
        [data appendBytes:&byte length:1];
        value >>= 7;
    }
    uint8_t byte = value & 0x7F;
    [data appendBytes:&byte length:1];
}
```

## BFE (Binary Format Encoding)

**File:** `Sources/SSBBFE.m`

Type/format prefixes for all SSB identities and encrypted data.

### Prefix Structure

```
┌──────────────┬────────────────┐
│ Type (1 byte)│ Format (1 byte)│
└──────────────┴────────────────┘
```

### Type Table

| Type | Name | Example |
|------|------|---------|
| 0 | Feed | `@<base64>.ed25519` |
| 1 | Message | `%<base64>.sha256` |
| 2 | Blob | &<base64>.sha256 |
| 3 | Encrypted |boxing... |
| 4 | Signature | ⎔<base64> |
| 5 | Cipher | ?

### Format Table

| Format | Type | ID |
|--------|------|-----|
| ed25519 | Feed | 0 |
| secp256k1 | Feed | 1 |
| ring | Feed | 2 |
| v1 | Message | 0 |
| v2 | Message | 1 |
| alt256 | Blob | 0 |
| alt1 | Blob | 1 |

### BFE Encoding

```objc
// Encode feed ID
+ (NSData *)encodeFeedID:(NSData *)pubkey {
    // Type = 0 (Feed), Format = 0 (ed25519)
    uint8_t prefix[2] = {0x00, 0x00};
    NSMutableData *result = [NSMutableData dataWithBytes:prefix length:2];
    [result appendData:pubkey];
    return result;
}

// Decode feed ID
+ (NSDictionary *)decodeFeedID:(NSData *)data {
    if (data.length < 2) return nil;
    uint8_t type = ((uint8_t*)data.bytes)[0];
    uint8_t format = ((uint8_t*)data.bytes)[1];
    if (type != 0 || format != 0) return nil;
    
    NSData *pubkey = [data subdataWithRange:NSMakeRange(2, 32)];
    return @{@"format": @"ed25519", @"key": pubkey};
}
```

## Usage in Scuttle

| Encoding | Used By | Purpose |
|----------|---------|---------|
| Bencode | BendyButt | Message encoding |
| BIPF | Buttwoo | Message encoding |
| BFE | All | Identity encoding |
| Bencode | MuxRPC | RPC encoding |
