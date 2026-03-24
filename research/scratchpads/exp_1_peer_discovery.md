# Exp 1: Peer Discovery
**Date**: 2026-03-23  **Status**: COMPLETED

## Hypothesis
After joining the room, `SRRoomManagerDidUpdateEndpointsNotification` never fires OR fires
with an empty list, so zero peer rows ever appear in the peer list table.

## Method
- Launch app with `-SSBUITestMode -SSBAutoJoinRoom <invite> -SSBExperimentLogPath <path>`
- Navigate: Network strip → Select Room → Peers sidebar
- Wait up to 60s for endpoints events with count > 0 in log
- Read experiment log for results

## Expected if Working
- Experiment log has ≥1 `endpoints` event with `count > 0`

## Raw Results
From log run `scuttle_exp_8AE2E6C8...jsonl`:
```json
{"host":"ssbroom.techpriesthub.xyz","event":"connection","connected":true}
{"peers":["@N0SepRf9rs...","@vkdMlsuB..."],"host":"ssbroom.techpriesthub.xyz","event":"endpoints","count":2}
{"status":"Connecting...","author":"@N0SepRf9rs...","event":"sync_status","progress":0}
{"status":"Receiving: 0/77","author":"@NCkKeNXJ...","event":"sync_status","progress":0}
```
*No `"event":"replicated"` events found in the log.*

## Conclusion
**REFUTED**. Peer discovery and endpoints retrieval are working perfectly on the Techpriest room. State machine enters `Receiving` phase for hundreds of feeds, but lack of `replicated` events suggests data never appends or stalls. Moving to EXP2/3.
