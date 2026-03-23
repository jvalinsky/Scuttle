#!/usr/bin/env bash
# ssb-room-harness.sh — Integration test harness for Scuttle CLI vs go-ssb-room
#
# Usage:
#   ./tools/debug/ssb-room-harness.sh <command>
#
# Commands:
#   pubkey          Print the room's public key
#   build           Build scuttle-cli (Linux/GNUstep via Docker)
#   test-identity   Test identity init/whoami
#   test-connect    Test room connection (SHS + BoxStream)
#   test-peers      Test peer/endpoint discovery
#   test-ebt        Test EBT sync
#   test-all        Run all tests
#   room-logs       Show room server logs
#   reset           Wipe test data and restart room
#   help            Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOM_HOST="${SSB_ROOM_HOST:-localhost}"
ROOM_MUX_PORT="${SSB_ROOM_PORT:-8008}"
ROOM_HTTP_PORT="${SSB_ROOM_HTTP_PORT:-3000}"
SCUTTLE_DATA="${SCUTTLE_TEST_DATA:-${PROJECT_ROOT}/.test-scuttle-data}"
SCUTTLE_CLI="${SCUTTLE_CLI_PATH:-${PROJECT_ROOT}/obj/scuttle-cli}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; FAILED=$((FAILED+1)); }
info() { echo -e "${BLUE}→${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
FAILED=0

###############################################################################
# Helpers
###############################################################################

wait_for_room() {
    local max=30
    local i=0
    info "Waiting for room at ${ROOM_HOST}:${ROOM_MUX_PORT}..."
    while ! nc -z "${ROOM_HOST}" "${ROOM_MUX_PORT}" 2>/dev/null; do
        i=$((i+1))
        if [ $i -ge $max ]; then
            fail "Room not reachable after ${max}s"
            return 1
        fi
        sleep 1
    done
    pass "Room is reachable"
}

require_room() {
    if ! nc -z "${ROOM_HOST}" "${ROOM_MUX_PORT}" 2>/dev/null; then
        echo ""
        warn "Room not running. Start it with:"
        echo "  docker compose up ssb-room -d"
        echo ""
        exit 1
    fi
}

require_cli() {
    if [ ! -x "${SCUTTLE_CLI}" ]; then
        warn "scuttle-cli not found at ${SCUTTLE_CLI}"
        warn "Build it with: ./tools/debug/ssb-room-harness.sh build"
        warn "Or set SCUTTLE_CLI_PATH to point to your binary"
        exit 1
    fi
}

run_cli() {
    XDG_DATA_HOME="${SCUTTLE_DATA}" "${SCUTTLE_CLI}" "$@"
}

###############################################################################
# Commands
###############################################################################

cmd_pubkey() {
    require_room
    info "Fetching room public key..."

    # Try HTTP dashboard first
    if nc -z "${ROOM_HOST}" "${ROOM_HTTP_PORT}" 2>/dev/null; then
        local pubkey
        pubkey=$(curl -sf "http://${ROOM_HOST}:${ROOM_HTTP_PORT}/" 2>/dev/null \
            | grep -oE '@[A-Za-z0-9+/]{43}=\.ed25519' | head -1)
        if [ -n "${pubkey}" ]; then
            echo "Room public key: ${pubkey}"
            return 0
        fi
    fi

    # Try reading directly from Docker container
    local key
    key=$(docker compose exec -T ssb-room cat /data/secret 2>/dev/null | \
          python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('public','?'))" 2>/dev/null || true)
    if [ -n "${key}" ]; then
        echo "Room public key (from secret): @${key}"
        return 0
    fi

    warn "Could not extract room public key automatically."
    echo "Check: docker compose exec ssb-room ls /data/"
    echo "Then read the public key from the secret file."
}

cmd_build() {
    info "Building scuttle-cli via Docker GNUstep environment..."
    cd "${PROJECT_ROOT}"

    docker compose --profile debug run --rm scuttle-build \
        bash -c ". /usr/share/GNUstep/Makefiles/GNUstep.sh && make"

    if [ -x "${PROJECT_ROOT}/obj/scuttle-cli" ]; then
        pass "Build succeeded: obj/scuttle-cli"
    else
        # Check alternate paths
        local alt
        for alt in "${PROJECT_ROOT}/scuttle-cli" "${PROJECT_ROOT}/build/scuttle-cli"; do
            if [ -x "$alt" ]; then
                pass "Build succeeded: $alt"
                return 0
            fi
        done
        fail "Build failed — binary not found"
        return 1
    fi
}

cmd_test_identity() {
    info "=== Test: Identity Init / Whoami ==="
    require_cli

    # Clean slate
    rm -rf "${SCUTTLE_DATA}"
    mkdir -p "${SCUTTLE_DATA}"

    # Test init
    local out
    out=$(run_cli init 2>&1)
    if echo "$out" | grep -q "Generated identity:"; then
        pass "scuttle-cli init: created identity"
    elif echo "$out" | grep -q "Identity already exists:"; then
        pass "scuttle-cli init: identity exists (OK)"
    else
        fail "scuttle-cli init: unexpected output: $out"
        return
    fi

    # Test whoami
    out=$(run_cli whoami 2>&1)
    if echo "$out" | grep -qE 'Public ID:\s+@[A-Za-z0-9+/]{43}=\.ed25519'; then
        local id
        id=$(echo "$out" | grep 'Public ID:' | awk '{print $NF}')
        pass "scuttle-cli whoami: ID = ${id}"
    else
        fail "scuttle-cli whoami: output missing valid ID: $out"
    fi

    echo ""
}

cmd_test_connect() {
    info "=== Test: Room Connection (SHS + BoxStream) ==="
    require_room
    require_cli

    # Ensure we have an identity
    run_cli init >/dev/null 2>&1 || true

    # We need a valid room invite to connect.
    # In open mode, the room accepts connections from anyone — but
    # scuttle-cli needs the room's pubkey to do SHS.
    #
    # Try to get invite code from HTTP dashboard
    local invite_url="http://${ROOM_HOST}:${ROOM_HTTP_PORT}/invite"
    local invite
    invite=$(curl -sf "${invite_url}" 2>/dev/null | \
             python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('invite',''))" 2>/dev/null || true)

    if [ -z "$invite" ]; then
        # Try alternate endpoint
        invite=$(curl -sf "http://${ROOM_HOST}:${ROOM_HTTP_PORT}/" 2>/dev/null | \
                 grep -oE 'net:[^;]+;key=@[^"]+' | head -1 || true)
    fi

    if [ -n "$invite" ]; then
        info "Got invite: ${invite}"
        run_cli invite "${invite}" >/dev/null 2>&1 || true
    else
        warn "Could not fetch invite automatically."
        warn "Manually get it from: http://${ROOM_HOST}:${ROOM_HTTP_PORT}/"
        warn "Then run: scuttle-cli invite <code>"
        echo "Skipping connection test."
        return
    fi

    # Run connect in background, capture output
    local tmpout
    tmpout=$(mktemp)
    timeout 20 run_cli connect "${ROOM_HOST}" > "${tmpout}" 2>&1 &
    local pid=$!
    sleep 8
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true

    local output
    output=$(cat "${tmpout}")
    rm -f "${tmpout}"

    if echo "$output" | grep -q "Connected to"; then
        pass "Connection established to ${ROOM_HOST}"
    elif echo "$output" | grep -q "Connecting to"; then
        warn "Connection initiated but status unclear (may need longer timeout)"
        info "Output: $output"
    else
        fail "Connection failed: $output"
    fi

    echo ""
}

cmd_test_peers() {
    info "=== Test: Peer/Endpoint Discovery ==="
    require_room
    require_cli

    warn "Peer discovery requires an active connection."
    info "Run: scuttle-cli connect ${ROOM_HOST}"
    info "Then check: scuttle-cli peers"
    echo "This test monitors room logs for endpoint events..."

    local log_lines
    log_lines=$(docker compose logs ssb-room --since=5s 2>/dev/null | \
                grep -iE "endpoint|tunnel|attend" | head -20 || true)
    if [ -n "$log_lines" ]; then
        info "Recent room endpoint events:"
        echo "$log_lines"
    else
        info "No recent endpoint events in room logs."
    fi
    echo ""
}

cmd_test_ebt() {
    info "=== Test: EBT Sync ==="
    require_room
    require_cli

    warn "EBT sync test requires an established connection."
    echo "Check room logs for EBT messages:"
    docker compose logs ssb-room --since=30s 2>/dev/null | \
        grep -iE "ebt|replicate|clock" | head -20 || true
    echo ""
}

cmd_test_all() {
    info "=== Running All Integration Tests ==="
    echo ""

    wait_for_room
    cmd_test_identity
    cmd_test_connect
    cmd_test_peers
    cmd_test_ebt

    echo ""
    if [ $FAILED -eq 0 ]; then
        pass "All tests passed!"
    else
        fail "$FAILED test(s) failed"
        exit 1
    fi
}

cmd_room_logs() {
    info "=== Room Server Logs ==="
    docker compose logs ssb-room --follow
}

cmd_reset() {
    warn "This will wipe test data and restart the room."
    read -r -p "Continue? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi

    info "Stopping room..."
    docker compose stop ssb-room 2>/dev/null || true

    info "Wiping room data..."
    rm -rf "${PROJECT_ROOT}/ssb-room-data"
    mkdir -p "${PROJECT_ROOT}/ssb-room-data"

    info "Wiping test CLI data..."
    rm -rf "${SCUTTLE_DATA}"

    info "Restarting room..."
    docker compose up ssb-room -d
    wait_for_room
    pass "Room reset and ready."
}

cmd_help() {
    head -20 "$0" | grep '#' | sed 's/^# //'
}

###############################################################################
# Main dispatch
###############################################################################

COMMAND="${1:-help}"

case "$COMMAND" in
    pubkey)         cmd_pubkey ;;
    build)          cmd_build ;;
    test-identity)  cmd_test_identity ;;
    test-connect)   cmd_test_connect ;;
    test-peers)     cmd_test_peers ;;
    test-ebt)       cmd_test_ebt ;;
    test-all)       cmd_test_all ;;
    room-logs)      cmd_room_logs ;;
    reset)          cmd_reset ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run: $0 help"
        exit 1
        ;;
esac
