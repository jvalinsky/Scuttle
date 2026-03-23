# go-ssb-room Protocol Reference

## Room Server Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `open` | Anyone connects, no invite needed | Testing |
| `community` | Invite required, anyone can create | Default |
| `restricted` | Admin-only invites | Production |

## Key RPC Methods

### `room.metadata` (async)
Returns room capabilities and public key.
```json
{
  "name": "Scuttle Test Room",
  "roomId": "@<pubkey>.ed25519",
  "features": ["tunnel", "alias", "httpAuth"]
}
```

### `tunnel.endpoints` (source)
Subscribe to attendant list changes. Emits arrays of peer IDs.
```json
["@peer1.ed25519", "@peer2.ed25519"]
```

### `tunnel.connect` (duplex)
Open a tunnel to another peer attending the room.
```json
// Request
{"portal": "@room.ed25519", "target": "@peer.ed25519", "origin": "@me.ed25519"}
```

### `tunnel.announce` (async)
Announce yourself as present in the room.
```json
// Typically called after connection, before endpoint subscription
{}
```

## Invite Code Format

```
net:<host>:<port>~shs:<room-pubkey-base64>
```

Example:
```
net:localhost:8008~shs:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
```

With invite token (community mode):
```
net:localhost:8008~shs:<pubkey>?invite=<token>
```

## Connection Flow

```
Client                          go-ssb-room
  |                                 |
  |--- TCP connect :8008 ---------->|
  |                                 |
  |=== Secret Handshake (320 bytes)=|
  |--- client_hello (64) ---------->|  ephemeral pubkey + HMAC(network_key, ephem_pk)
  |<-- server_hello (64) -----------|  server ephemeral + HMAC(network_key, server_ephem_pk)
  |--- client_auth (112) ---------->|  box(auth_msg, server_pk, ephem_shared)
  |<-- server_accept (80) ----------|  box(accept_msg, ephem_shared)
  |                                 |
  |=== BoxStream (encrypted) =======|
  |--- shs.rpc(manifest) ---------->|  get server RPC manifest
  |<-- rpc response ----------------|
  |--- room.metadata() ------------>|
  |<-- {name, roomId, features} ----|
  |--- tunnel.endpoints() subscribe>|
  |<-- [peer1, peer2, ...]  --------|  (stream of endpoint events)
  |                                 |
  |=== Per-Peer Tunnel ==============|
  |--- tunnel.connect(peer2) ------>|
  |<== duplex stream to peer2 ======|
  |  |-- SHS with peer2 over tunnel |
  |  |-- MuxRPC with peer2          |
  |  |-- ebt.replicate() ---------->|
  |  |<-- peer clock .............. |
  |  |-- send our clock ----------->|
  |  |<-- messages .................|
```

## Network Key (SSB_NETWORK_ID)

The SSB main network key (used in SHS):
```
d4a1cb88a66f02f8db635ce26441cc5dac1b08420ceaac230839b755845a9ffb
```

This is the `HMAC-SHA512-256` key for the handshake authentication.
go-ssb-room uses this by default for the main SSB network.

## BoxStream Frame Format

After SHS, all data is BoxStream encrypted:

```
[2 bytes: payload_length (big-endian)]
[16 bytes: auth tag for header]
[N bytes: encrypted payload]
[16 bytes: auth tag for payload]
```

Goodbye frame: 18 bytes of zeros.

## MuxRPC Packet Format

Each packet inside BoxStream:

```
[4 bytes: flags+length (big-endian)]
  bit 31: isStream
  bit 30: isEnd/Error
  bit 28-29: body type (0=binary, 1=utf8, 2=json)
  bits 0-27: body length
[4 bytes: request ID (big-endian, negative = response)]
[N bytes: body]
```
