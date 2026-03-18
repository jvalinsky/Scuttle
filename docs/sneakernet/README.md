# SSB Sneakernet: Offline Message Exchange

**Sneakernet Mode** is a high-performance offline message exchange system for Secure Scuttlebutt (SSB) implemented in ScuttleKit. It allows users to share individual, cryptographically verifiable messages using QR codes without an internet connection.

## Why Sneakernet?

Traditional SSB requires downloading an entire feed history to verify the latest message. This is impossible for "sneakernet" (e.g., scanning a QR at a conference or in a disaster zone). 

By leveraging the **Bamboo feed format**, we provide **Lipmaa Inclusion Proofs** that allow a scanner to trust a single message instantly, even if they have never seen the author before.

## Documentation Suite

1.  **[Mathematical Theory (THEORY.md)](THEORY.md)**: Explains the skip-list properties of Lipmaa links and $O(\log n)$ verification.
2.  **[Protocol Specification (PROTOCOL.md)](PROTOCOL.md)**: Details the binary encoding and the `ssb:bamboo-proof:` URI scheme.
3.  **[User Experience Guide (UX_GUIDE.md)](UX_GUIDE.md)**: Describes how to use the "Share QR" and "Scan QR" features in the app.

## Key Features

- **Authenticated Exchange**: Every scanned message is verified using Ed25519 signatures and hash-chain integrity.
- **Constant-Time Verification**: No need to sync GBs of data to "Follow" someone.
- **Zero-Trust Friendly**: The receiver only needs to trust the Author's Root Hash (Sequence 1) to verify any subsequent message.
