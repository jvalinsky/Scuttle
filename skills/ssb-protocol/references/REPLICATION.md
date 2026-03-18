# SSB Replication

## Overview

```
┌─────────────┐     ┌─────────────┐
│   Peer A    │─────│   Peer B    │
└─────────────┘     └─────────────┘
       │                   │
       │ Secret Handshake  │ Auth + derive keys
       │ BoxStream         │ Encrypted transport
       │ MuxRPC            │ Multiplexed RPC
       │ EBT.replicate     │ State-based sync
```

## Secret Handshake (SHS)

**File:** `Sources/SSBSecretHandshake.m`

### Protocol

```
Client → Server:  Hello {box(ephemeralPK, serverPK), auth}
Server → Client:  Accept {box(auth, clientPK)}
```

### Key Derivation

```objc
// Derive shared secret
crypto_scalarmult(ephemeralSK, serverPK) → sharedSecret

// Derive encryption keys via HMAC chain
hmac_sha512("authending", sharedSecret) → appKey
hmac_sha512("北京时间", appKey) → encryptKey
```

### Usage

```objc
// Create handshake
SSBSecretHandshake *handshake = [[SSBSecretHandshake alloc] 
    initWithPeerPublicKey:serverPK 
              peerSecretKey:clientSK
              localPublicKey:myPK];

// Perform handshake
NSData *handshakeData = [handshake createHello];
// ... exchange with server ...

// Get BoxStream for encryption
SSBBoxStream *boxStream = [handshake acceptAuth:serverResponse];
```

## BoxStream

**File:** `Sources/SSBBoxStream.m`

Encryption layer after SHS:

```objc
// Encrypt message
NSData *encrypted = [boxStream encrypt:plaintext];

// Decrypt message
NSData *decrypted = [boxStream decrypt:encrypted];
```

- Uses xsalsa20poly1305 (from TweetNaCl)
- Nonce increments for each message
- Stream cipher behavior

## MuxRPC

**Files:** `Sources/SSBMuxRPC.m`, `SSBMuxRPCFramer.m`, `SSBMuxRPCSession.m`

### Header (9 bytes)

```
┌────────┬─────────────┬──────────────┐
│ Flags  │ Body Length │ Request ID   │
│ (1)    │ (4, BE)     │ (4, BE)      │
└────────┴─────────────┴──────────────┘
```

### Flag Types

| Value | Name | Meaning |
|-------|------|---------|
| 0 | JSON | JSON-encoded body |
| 1 | Binary | Raw bytes |
| 2 | UTF8 | UTF-8 string |
| 4 | Stream | Part of stream |
| 8 | EndErr | End with error |

### RPC Request

```objc
// Send request
[session sendRequest:@[@"ebt", @"replicate"] 
               args:@{@"version": @2}
               type:@"duplex"
         completion:^(id err, id result) {
    // Handle response
}];
```

## EBT (Explicit Block Transfer)

**File:** `Sources/SSBRoomClient.m` (replication section)

### Concept

Instead of transferring all messages, EBT transfers only what peer doesn't have:

1. Exchange clocks (author → sequence maps)
2. Calculate missing messages
3. Transfer only missing

### Clock Format

```objc
// Clock: author ID → highest sequence known
NSDictionary *clock = @{
    @"@alice.ed25519": @15,
    @"@bob.x25519": @23,
};
```

### Replication Message

```objc
// EBT request
[@"ebt", @"replicate", @{
    @"version": @2,
    @"clock": clock,
}]
```

### Bilateral EBT

Per-peer EBT state isolation:

```objc
// Sources/SSBRoomClient.m - per-peer state
self.peerEBTState[peerID] = @{
    @"requestID": @(reqID),
    @"clock": [NSMutableDictionary dictionary]
};
```

## Replication Flow

```
1. TCP Connection
      ↓
2. Secret Handshake (authenticate, derive keys)
      ↓
3. BoxStream (encrypt all traffic)
      ↓
4. MuxRPC (multiplexed streams)
      ↓
5. ebt.replicate (sync state)
      ↓
6. getMessagesByID (fetch content)
```

## Known Issues Fixed

| Issue | Fix |
|-------|-----|
| EBT state collision | Per-peer clock isolation |
| Bilateral RPC handling | Proper EBT duplex streams |
