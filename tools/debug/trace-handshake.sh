#!/usr/bin/env bash
# trace-handshake.sh — Capture and decode SSB Secret Handshake bytes
#
# The SSB Secret Handshake (SHS) is a 3-step protocol:
#   Step 1 (Client Hello):  64 bytes  — ephemeral pubkey + network HMAC
#   Step 2 (Server Hello):  64 bytes  — server ephemeral + network HMAC
#   Step 3 (Client Auth):  112 bytes  — encrypted auth box
#   Step 4 (Server Accept): 80 bytes  — encrypted server accept box
#
# Total: 320 bytes for the handshake phase.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CAPTURE_FILE="${PROJECT_ROOT}/.debug/shs-capture.pcap"
DECODE_OUTPUT="${PROJECT_ROOT}/.debug/shs-decode.txt"

mkdir -p "${PROJECT_ROOT}/.debug"

ROOM_HOST="${SSB_ROOM_HOST:-localhost}"
ROOM_PORT="${SSB_ROOM_PORT:-8008}"

usage() {
    echo "Usage: $0 <capture|decode|watch>"
    echo ""
    echo "  capture  Start tcpdump capture of port ${ROOM_PORT}"
    echo "  decode   Decode captured bytes and print analysis"
    echo "  watch    Watch room logs filtered for handshake events"
}

cmd_capture() {
    echo "→ Capturing SHS traffic on port ${ROOM_PORT}..."
    echo "  Output: ${CAPTURE_FILE}"
    echo "  Press Ctrl+C to stop."
    echo ""
    tcpdump -i lo -w "${CAPTURE_FILE}" "tcp port ${ROOM_PORT}" 2>/dev/null || \
    tcpdump -i any -w "${CAPTURE_FILE}" "tcp port ${ROOM_PORT}"
}

cmd_decode() {
    if [ ! -f "${CAPTURE_FILE}" ]; then
        echo "No capture file found. Run: $0 capture first."
        exit 1
    fi

    echo "→ Decoding SHS handshake from ${CAPTURE_FILE}..."
    echo ""

    # Extract raw TCP payload using tcpdump -A
    tcpdump -r "${CAPTURE_FILE}" -A -x 2>/dev/null | \
    python3 - << 'PYEOF'
import sys, re

# Read hex dump lines
packets = []
current = []
for line in sys.stdin:
    # tcpdump -x hex lines look like:  "\t0x0000:  4500 ..."
    m = re.match(r'\s+0x[0-9a-f]+:\s+([0-9a-f\s]+)', line)
    if m:
        hex_bytes = m.group(1).replace(' ', '')
        current.append(hex_bytes)
    elif current:
        packets.append(''.join(current))
        current = []

if current:
    packets.append(''.join(current))

# Try to identify SHS phases based on byte counts
SHS_PHASES = [
    (64,  "Client Hello (ephemeral pubkey + HMAC)"),
    (64,  "Server Hello (server ephemeral + HMAC)"),
    (112, "Client Auth (encrypted box)"),
    (80,  "Server Accept (encrypted accept)"),
]

print("=== Secret Handshake Analysis ===")
print(f"Total packets captured: {len(packets)}")
print("")

for i, pkt in enumerate(packets[:10]):  # First 10 packets
    try:
        raw = bytes.fromhex(pkt)
        # Skip IP+TCP headers (typical: 20+20=40 bytes, but may vary)
        if len(raw) < 40:
            continue
        payload_len = len(raw) - 40
        if payload_len <= 0:
            continue
        print(f"Packet {i+1}: {payload_len} bytes payload")
        for expected_len, phase_name in SHS_PHASES:
            if payload_len == expected_len:
                print(f"  ✓ Matches: {phase_name}")
                print(f"  Hex: {pkt[80:80+32]}...")
                break
        else:
            if payload_len < 400:  # Show small packets
                print(f"  (not a SHS phase — may be BoxStream or other)")
    except Exception as e:
        pass

print("")
print("Note: SHS handshake = 64+64+112+80 = 320 bytes total")
print("After handshake, all data is BoxStream encrypted (24-byte headers + payload)")
PYEOF
    tee "${DECODE_OUTPUT}"
}

cmd_watch() {
    echo "→ Watching room logs for handshake events..."
    echo "  (Filter: connect, handshake, auth, error)"
    echo ""
    docker compose logs ssb-room --follow 2>/dev/null | \
        grep -iE --line-buffered "connect|handshake|auth|error|peer|room|shs" || true
}

case "${1:-}" in
    capture) cmd_capture ;;
    decode)  cmd_decode ;;
    watch)   cmd_watch ;;
    *)       usage; exit 1 ;;
esac
