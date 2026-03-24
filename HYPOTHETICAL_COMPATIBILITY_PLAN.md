# HYPOTHETICAL FUTURE DIRECTION: Legacy Client Compatibility Bridge

> **NOTE:** This document describes a hypothetical architectural direction for the ScuttleKit project. It outlines how the modern, Bamboo-based "Sneakernet" features can coexist with and support legacy Secure Scuttlebutt (SSB) clients like `tildefriends`, `Patchwork`, and `Manyverse` (Classic).

---

## Overview

As ScuttleKit moves toward a high-performance, binary-first future using the **Bamboo** feed format and **Lipmaa Inclusion Proofs**, it is critical to maintain a bridge to the "Classic" SSB ecosystem. Legacy clients rely on JSON-serialized messages, the `createHistoryStream` RPC, and Multiserver-style invite codes.

This plan outlines a **Dual-Stack Identity** and **Protocol Negotiation** strategy to ensure seamless interoperability.

---

## 1. Dual-Branch Metafeeds (SIP 1)

To support both modern and legacy clients, ScuttleKit will implement a **Dual-Branch Metafeed** structure. Every user identity will manage at least two sub-feeds under their root Metafeed:

1.  **The Bamboo Branch (Modern):** High-performance, $O(\log n)$ verification, used for Sneakernet and mobile-to-mobile sync.
2.  **The Classic Branch (Legacy):** Standard JSON/Ed25519 feed, used for compatibility with `tildefriends` and legacy pubs.

### Implementation:
- **Cross-Publishing:** When a user updates their profile (name/avatar), the app will publish an `about` message to *both* branches.
- **Replication Hints:** The Metafeed `announce` message will include hints for legacy peers to only follow the Classic branch.

---

## 2. Protocol Negotiation & Fallbacks

When connecting to a peer via the **Secret Handshake (SHS)**, the client must determine the peer's capabilities.

### RPC Negotiation:
- **Capability Discovery:** Upon connection, ScuttleKit will issue a `gossip.getPeerCapabilities` or check the peer's `User-Agent`.
- **Intelligent Routing:**
    - If the peer is identified as a modern client (e.g., Sunrise Social, ScuttleKit), use **Bamboo/BendyButt** for sync.
    - If the peer is identified as a legacy client (e.g., `tildefriends`), default to **Classic JSON** and serve the Classic branch of the user's metafeed.

---

## 3. Legacy Invite & Identity QRs

The "Sneakernet" mode currently uses high-density `ssb:bamboo-proof:` URIs. To support `tildefriends` users, we will provide a **Legacy Toggle** in the UI.

### The "Compatibility" QR:
- **Invite Format:** Generate a standard Multiserver invite: `net:host:port~shs:pubkey:token`.
- **Identity Format:** Generate a "Classic ID" QR: `@pubkey.ed25519`.
- **UX Integration:** In the `SRScannerViewController`, the app will automatically detect if a scanned QR is a legacy invite or a modern Bamboo proof and route the logic accordingly (either joining a room or importing a verified message).

---

## 4. The "Bamboo-to-Classic" Transpiler (Experimental)

A hypothetical "Bridge" service within the app could dynamically "transpile" incoming Bamboo messages into a Classic JSON format for storage or sharing with legacy peers.

- **Integrity Mapping:** While the cryptographic signatures cannot be converted, the *content* can be re-signed by the user's Classic sub-feed keys to create a "Legacy Mirror" of their modern activity.

---

## 5. Summary of Interop Goals

| Feature | ScuttleKit (Modern) | tildefriends (Legacy) | Bridge Strategy |
| :--- | :--- | :--- | :--- |
| **Feed Format** | Bamboo (Binary) | Classic (JSON) | Dual-Publishing |
| **Inclusion Proof** | Lipmaa ($O(\log n)$) | None (Full Sync) | Serve Classic History |
| **Invite Scan** | `ssb:bamboo-proof:` | Multiserver String | Auto-detecting Scanner |
| **Identity** | Metafeed (SIP 1) | Single Ed25519 Key | Root Metafeed includes Classic leaf |

---

By following this direction, ScuttleKit can innovate with high-performance sneakernet features while remaining a first-class citizen in the broader, established Secure Scuttlebutt network.
