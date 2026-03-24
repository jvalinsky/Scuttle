# The Mathematical Theory of Bamboo Sneakernet

This document explains the cryptographic foundation that makes single-message QR exchange possible in Secure Scuttlebutt (SSB).

## The Problem: Linear Verification

In "Classic" SSB (JSON format), feeds are simple linked lists. To verify message $N$, you MUST possess all messages from $1$ to $N-1$. 

- If a user has $100,000$ messages, you would need to download and hash all of them before you can trust the latest "Identity" message.
- This is physically impossible via a QR code, as it would require thousands of scans.

## The Solution: Lipmaa Links ($O(\log n)$)

The **Bamboo** feed format uses a skip-list structure based on the **Lipmaa sequence**. Every message $N$ ($N > 1$) contains two backlinks:

1.  **Predecessor Link:** Hash of message $N-1$ (standard linked list).
2.  **Lipmaa Link:** Hash of a carefully chosen older message that provides a shortcut back to the root.

### Lipmaa Sequence Calculation
The Lipmaa link for sequence $n$ points to $n - 3^k$, where $3^k < n$ is the largest power of 3.

```objc
+ (NSInteger)lipmaaSequenceFor:(NSInteger)seq {
    if (seq <= 1) return 1;
    NSInteger pow3 = 1;
    while (pow3 * 3 < seq) pow3 *= 3;
    return seq - pow3;
}
```

### Logarithmic Efficiency
Because each link "skips" large segments of the feed, the shortest path from *any* message $N$ to message $1$ (the Root) is **logarithmic** in length.

| Feed Size ($N$) | Max Proof Steps ($O(\log n)$) | Proof Size (Hashes) |
| :--- | :--- | :--- |
| 1,000 | ~7 | 224 bytes |
| 100,000 | ~11 | 352 bytes |
| 1,000,000 | ~13 | 416 bytes |

## Proof of Inclusion

When we share a message via QR, we don't just send the message; we send a **Proof Packet**. 

1.  **Target Message:** The actual signed content.
2.  **Lipmaa Path:** An ordered list of hashes for each "skip" in the path back to sequence 1.
3.  **Root Hash:** The known-valid hash for the author's first message.

**Verification Process:**
1.  Verify the signature of the **Target Message** using the author's public key.
2.  Extract the `lipmaa_link` from the target message.
3.  Check that this link matches the first hash in the **Lipmaa Path**.
4.  Follow the path until you reach the **Root Hash**.

**Result:** The scanner has mathematically proven that the target message belongs to the author's chain, even without seeing any intermediate messages.
