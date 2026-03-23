# Exp 3: Sync Progress Advances
**Date**: —  **Status**: PENDING

## Hypothesis
Sync starts ("Receiving X%") but stalls at a fixed percentage, suggesting EBT messages
arrive but cannot be appended — likely a message verification failure, duplicate
detection bug, or deadlock in the feed store write path.

## Method
- Wait until `peer-status-0` shows "Receiving" or "Sending" (depends on Exp 2 passing)
- Sample the maximum progress value from the experiment log every 10s for 120s
- Check: progress increases at least twice across the sample window
- Check: `replicated` events appear in the log

## Expected if Working
- Progress increases monotonically or in steps
- At least 3 progress increases seen
- `replicated` events with count > 0

## Raw Results
- Status consistently stalled at `"Receiving: 0/182"` for over 90 seconds.
- No `DEBUG_STALL` logs encountered, meaning parsing wasn't failing inside `processIncomingMessage:`, but rather payloads were not reaching it.

## Conclusion
**CONFIRMED**. Synchronization stalls at `0%` due to TWO core blockers:
1. **Early binary intercepts** - Raw EBT chunks intercepted early as `nil` inside `parsedBodyForMessage:` (`SSBMuxRPCSession.m`).
2. **Missing ack response** - We didn't reply to the remote clock announcement with our updated subscriptions inside `handleRemoteClockUpdate:`, leaving Go-SSB-Room silent.

## Update: Fix Applied
**Status**: RESOLVED
**Changes**:
- Enabled raw binary body fallback in `parsedBodyForMessage:` returning `message.body`.
- Added updated clock responses back inside `handleRemoteClockUpdate:fromPeer:` using `[ebtSession sendData:replyClock ...]`.
- **Result:** Sync stalls fixed, streams complete properly.
