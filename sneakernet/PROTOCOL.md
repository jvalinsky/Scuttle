# Bamboo Proof Protocol Specification

This document defines the binary encoding and URI scheme used for offline message exchange in ScuttleKit.

## URI Scheme

All sneakernet-enabled QR codes MUST use the following URI scheme:

```
ssb:bamboo-proof:<Base64URL_Encoded_Binary_Packet>
```

**Note:** We use Base64URL (no padding, `+` replaced with `-`, `/` replaced with `_`) to maximize compatibility with scanning libraries and URL-safe contexts.

## Binary Serialization

The payload is a binary blob produced by `NSKeyedArchiver` (with `NSSecureCoding` enabled). 

### High-Level Structure

| Field | Type | Description |
| :--- | :--- | :--- |
| **Target Message** | `Data` | Raw binary of the Bamboo entry ($177–241$ bytes). |
| **Lipmaa Path** | `Array<Data>` | Concatenated 32-byte hashes ($H \times 32$ bytes). |
| **Root Hash** | `Data` | 32-byte hash of the sequence 1 message. |
| **Author PubKey** | `Data` | 32-byte Ed25519 public key of the author. |

## Data Sizes

A typical Bamboo Proof for a message at sequence $1,000,000$:

| Component | Size (Bytes) |
| :--- | :--- |
| Bamboo Message | $241$ |
| Lipmaa Path (13 hashes) | $416$ |
| Root Hash | $32$ |
| Author PubKey | $32$ |
| Archiving Overhead | ~$50$ |
| **Total Binary** | **~771 Bytes** |

**Base64 Overhead (33%):** Approx. **1,025 characters** in the QR code.

## QR Code Configuration

For optimal reliability across all devices, the QR generator uses:

- **Correction Level:** `M` (Medium - handles 15% data loss).
- **Scale:** Adjusted to a minimum of $400 \times 400$ pixels for high density.
- **Filter:** `CIQRCodeGenerator`.

## Why Not Classic JSON?

A single classic SSB message can exceed $8,192$ bytes. For QR exchange, the **Bamboo** binary format is mandatory because it:
1.  Encapsulates the signature *within* the binary layout.
2.  Provides fixed-offset access to the Lipmaa Link.
3.  Is approximately $10 \times$ more space-efficient than equivalent JSON.
