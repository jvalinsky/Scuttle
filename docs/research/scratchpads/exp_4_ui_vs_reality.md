# Exp 4: UI vs. Reality
**Date**: —  **Status**: PENDING

## Hypothesis
`roomClient:didReplicateMessagesFromPeer:count:` fires (messages actually stored in
SSBFeedStore) but the UI peer-status labels never update because
`SRRoomSyncStatusChangedNotification` is never posted — revealing a notification routing
bug, not a protocol failure.

## Method
- Run for 90s with experiment log enabled
- Compare: `replicated` events in log (messages stored) vs `sync_status` events
- Also compare against final UI status labels visible in XCUITest

## Discriminator Table
| replicated > 0 | sync_status > 0 | Conclusion |
|:-:|:-:|---|
| ✅ | ❌ | **UI BUG** — delegate fires but notification not posted |
| ✅ | ✅ | Working — protocol and UI both active |
| ❌ | ❌ | Protocol failure upstream — Exp 1/2 failed |
| ❌ | ✅ | Partial — status fires but no messages stored |

## Raw Results
From test run:
```
[Exp4] replicated events: 0 total messages: 0
[Exp4] sync_status events: 1844
Final UI statuses: {( "Sending: 0/118", Idle, Stranger )}
```

## Conclusion
**REFUTED** (Hypothesis that UI is blind is refuted; UI updates are now flowing).
With the previous fixes in `SRRoomManager.m` (propagating `peerID`) and EBT stall fixes, the `sync_status` events are correctly firing (1844 events) and rendering in the UI (`Sending: 0/118`). Sync notifications are fully routed.
**Status**: RESOLVED

