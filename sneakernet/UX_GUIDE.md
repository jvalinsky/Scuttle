# Sneakernet User Guide

This guide explains how to use the "Sneakernet" offline message exchange features in the ScuttleKit app.

## Summary

Sneakernet allows you to "hand-carry" messages from one device to another using QR codes. No internet, Room, or Pub is required.

## 1. Sharing a Message

To share a message from your timeline:

1.  Find the message you want to share (e.g., your latest profile update).
2.  Click the **QR Code icon** on the message card.
    *   *Note: This icon only appears for messages in the **Bamboo** format.*
3.  A large QR code will appear on your screen. This QR contains the message and a **Lipmaa Proof** that authenticates it back to your identity.
4.  Keep this QR on your screen for the receiver to scan.

## 2. Scanning a Message

To receive a message via sneakernet:

1.  Click the **Scanner icon** (QR viewfinder) at the bottom-left of the **Sidebar**.
2.  Your camera will activate. Point it at the sender's QR code.
3.  The app will automatically:
    *   Detect the Bamboo proof.
    *   **Verify** the signature and the Lipmaa path.
    *   Import the message into your local feed store.
4.  If successful, the message will instantly appear in your timeline. You can now see the sender's latest name and avatar even if you are offline.

## 3. Offline Device Pairing

You can also use sneakernet to pair a new device (laptop/phone) without copying long strings:

1.  On the **primary device**, go to **Manage Devices** and click **Show QR**.
2.  Enter the public key of the **new device**.
3.  On the **new device**, go to the **Recovery** screen and click **Scan QR**.
4.  Point the camera at the primary device's screen.
5.  The new device will automatically decrypt the metafeed seed and complete the pairing process.

## Troubleshooting

- **No QR Icon?** The message must be in Bamboo format. ScuttleKit automatically converts your new messages to Bamboo, but older messages (classic JSON) cannot be shared this way.
- **Camera Access:** Ensure you have granted the app permission to use the camera in **System Settings > Privacy & Security > Camera**.
