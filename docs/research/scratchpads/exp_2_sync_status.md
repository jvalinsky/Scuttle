# Exp 2: Sync Status Changes
**Date**: 2026-03-23  **Status**: COMPLETED

## Hypothesis
Peers appear in the list (Exp1 passes) but every peer-status label stays empty — meaning the UI fails to bind or render the underlying state changes.

## Method
- Launch app with robust `-waitForEndpointsWithCountGreaterThanZero`
- Navigate: Network strip → Select Room → Peers sidebar
- Poll for 90s collecting all unique `StaticText` values from table cells
- Read experiment log for `sync_status` events

## Expected if Working
- At least one non-empty status string appears in the UI (e.g. "Receiving", "Sending", "Ready")

## Raw Results
From log run `scuttle_exp_A3705DF1...`:
```
[Exp2] peerCount=2 statuses=(
    "",
    ""
)
...
[Exp2] Seen UI statuses: {()}
[Exp2] sync_status log events: 5
```
*The UI statuses remained empty strings throughout the 90-second polling period, even though 5 `sync_status` events were written to the log.*

## Conclusion
**CONFIRMED**. While safe data exchanges are occurring (logged events), the UI is completely blind to them. Status labels stay blank (""). This points directly to a notification routing or UI cell rendering bug (`SRPeerListViewController` or `SRRoomManager` event propagation).

## Update: Fix Applied
**Status**: RESOLVED
**Changes**:
- Propagated `peerID` down through `SSBRoomClientDelegate` and Posted notifications inside `SRRoomManager.m`.
- Updated `SRPeerListViewController.m`'s `syncStatusChanged:` to map labels and values by `peerID` rather than author.
- **Result:** Statuses successfully transit to non-blank states (`Ready`, `Idle`, or `Receiving`).
