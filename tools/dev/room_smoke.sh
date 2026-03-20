#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
SERVICE_NAME="${SSB_ROOM_SERVICE:-ssb-room}"
HOST="${SSB_ROOM_HOST:-127.0.0.1}"
PORT="${SSB_ROOM_PORT:-8008}"
TIMEOUT_SECONDS="${SSB_ROOM_TIMEOUT:-45}"
SERVER_PUBKEY="${SSB_ROOM_SERVER_PUBKEY:-}"
SKIP_COMPOSE=0
TRACE_DIR="${SSB_ROOM_TRACE_DIR:-}"
ROOM_IMAGE="${SSB_ROOM_IMAGE:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --host <host>              Room host (default: 127.0.0.1)
  --port <port>              Room port (default: 8008)
  --timeout <seconds>        Smoke timeout (default: 45)
  --server-pubkey <base64>   Room public key (base64 or @...ed25519)
  --trace-dir <path>         Directory for logs, traces, and build artifacts
  --service <name>           Compose service name (default: ssb-room)
  --skip-compose             Reuse an already-running room instead of starting Compose
  --help                     Show this message

Environment:
  SSB_ROOM_SERVER_PUBKEY     Same as --server-pubkey
  SSB_ROOM_IMAGE             Override the compose build with a prebuilt image
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --server-pubkey)
      SERVER_PUBKEY="$2"
      shift 2
      ;;
    --trace-dir)
      TRACE_DIR="$2"
      shift 2
      ;;
    --service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --skip-compose)
      SKIP_COMPOSE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TRACE_DIR" ]]; then
  TRACE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scuttle-room-smoke.XXXXXX")"
else
  mkdir -p "$TRACE_DIR"
fi

TRACE_FILE="$TRACE_DIR/protocol-trace.ndjson"
SUMMARY_FILE="$TRACE_DIR/summary.json"
CLIENT_LOG="$TRACE_DIR/client.log"
BUILD_LOG="$TRACE_DIR/xcodebuild.log"
COMPOSE_UP_LOG="$TRACE_DIR/docker-compose.up.log"
DOCKER_LOGS_FILE="$TRACE_DIR/docker-compose.logs.txt"
DERIVED_DATA="$TRACE_DIR/DerivedData"
CLIENT_BIN="$TRACE_DIR/room-smoke-client"
RUNTIME_DIR="$TRACE_DIR/runtime"
OVERRIDE_COMPOSE_FILE=""

write_failure_summary() {
  local reason="$1"
  local message="$2"
  python3 - "$SUMMARY_FILE" "$reason" "$message" "$TRACE_DIR" "$TRACE_FILE" "$DOCKER_LOGS_FILE" <<'PY'
import json
import sys

summary_path, reason, message, trace_dir, trace_file, docker_logs = sys.argv[1:]
payload = {
    "ok": False,
    "reason": reason,
    "message": message,
    "traceDir": trace_dir,
    "traceFile": trace_file,
    "dockerLogsFile": docker_logs,
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
print(json.dumps(payload, indent=2))
PY
}

capture_docker_logs() {
  if [[ "$SKIP_COMPOSE" -eq 1 ]]; then
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  local -a compose_cmd=(docker compose -f "$COMPOSE_FILE")
  if [[ -n "$OVERRIDE_COMPOSE_FILE" ]]; then
    compose_cmd+=(-f "$OVERRIDE_COMPOSE_FILE")
  fi
  "${compose_cmd[@]}" logs --no-color >"$DOCKER_LOGS_FILE" 2>&1 || true
}

normalize_server_pubkey() {
  python3 - "$1" <<'PY'
import sys

value = sys.argv[1].strip()
if value.startswith("@"):
    value = value[1:]
if value.endswith(".ed25519"):
    value = value[:-8]
print(value)
PY
}

find_server_pubkey_in_repo_data() {
  python3 - "$ROOT_DIR/ssb-room-data" <<'PY'
import os
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
pattern = re.compile(rb'@?([A-Za-z0-9+/]{43,44}=?)\.ed25519')

if not root.exists():
    sys.exit(1)

for path in sorted(root.rglob("*")):
    if not path.is_file():
        continue
    try:
        if path.stat().st_size > 262144:
            continue
        data = path.read_bytes()
    except OSError:
        continue
    match = pattern.search(data)
    if match:
        print(match.group(1).decode("utf-8"))
        sys.exit(0)

sys.exit(1)
PY
}

wait_for_port() {
  python3 - "$HOST" "$PORT" "$TIMEOUT_SECONDS" <<'PY'
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
timeout = float(sys.argv[3])
deadline = time.time() + timeout

while time.time() < deadline:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    try:
        sock.connect((host, port))
    except OSError:
        time.sleep(0.5)
    else:
        sock.close()
        sys.exit(0)
    finally:
        sock.close()

sys.exit(1)
PY
}

prepare_compose_override() {
  if [[ "$SKIP_COMPOSE" -eq 1 ]]; then
    return
  fi

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    write_failure_summary "missing_compose_file" "Compose file not found at $COMPOSE_FILE"
    exit 1
  fi

  if [[ -d "$ROOT_DIR/tmp-room" ]]; then
    return
  fi

  if [[ -n "$ROOM_IMAGE" ]]; then
    OVERRIDE_COMPOSE_FILE="$TRACE_DIR/docker-compose.override.yml"
    cat >"$OVERRIDE_COMPOSE_FILE" <<EOF
services:
  ${SERVICE_NAME}:
    build: null
    image: ${ROOM_IMAGE}
EOF
    return
  fi

  local submodule_context="$ROOT_DIR/third-party/go-ssb-room"
  if [[ -d "$submodule_context" ]] && [[ -n "$(find "$submodule_context" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    local dockerfile="Dockerfile.dev"
    if [[ ! -f "$submodule_context/$dockerfile" ]]; then
      dockerfile="Dockerfile"
    fi
    if [[ ! -f "$submodule_context/$dockerfile" ]]; then
      write_failure_summary "missing_room_dockerfile" "No Dockerfile.dev or Dockerfile found in $submodule_context"
      exit 1
    fi

    OVERRIDE_COMPOSE_FILE="$TRACE_DIR/docker-compose.override.yml"
    cat >"$OVERRIDE_COMPOSE_FILE" <<EOF
services:
  ${SERVICE_NAME}:
    build:
      context: ./third-party/go-ssb-room
      dockerfile: ${dockerfile}
EOF
    return
  fi

  write_failure_summary \
    "missing_room_context" \
    "docker-compose.yml expects ./tmp-room, but that directory is absent and third-party/go-ssb-room is not initialized. Initialize the submodule or set SSB_ROOM_IMAGE."
  exit 1
}

build_smoke_client() {
  xcodebuild build \
    -project "$ROOT_DIR/SSBNetwork.xcodeproj" \
    -scheme SSBNetwork \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    >"$BUILD_LOG" 2>&1

  local build_products="$DERIVED_DATA/Build/Products/Debug"
  xcrun clang \
    -fobjc-arc \
    -F "$build_products" \
    -I "$ROOT_DIR/Sources" \
    -o "$CLIENT_BIN" \
    "$ROOT_DIR/tools/dev/RoomSmokeClient.m" \
    -framework Foundation \
    -framework SSBNetwork \
    -Wl,-rpath,"$build_products" \
    >>"$BUILD_LOG" 2>&1
}

prepare_compose_override

if ! command -v docker >/dev/null 2>&1 && [[ "$SKIP_COMPOSE" -eq 0 ]]; then
  write_failure_summary "missing_docker" "docker is required to run the room smoke harness"
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  write_failure_summary "missing_xcodebuild" "xcodebuild is required to build the smoke harness"
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  write_failure_summary "missing_xcrun" "xcrun is required to compile the smoke client"
  exit 1
fi

if [[ "$SKIP_COMPOSE" -eq 0 ]]; then
  typeset -a local_compose_cmd
  local_compose_cmd=(docker compose -f "$COMPOSE_FILE")
  if [[ -n "$OVERRIDE_COMPOSE_FILE" ]]; then
    local_compose_cmd+=(-f "$OVERRIDE_COMPOSE_FILE")
  fi
  "${local_compose_cmd[@]}" up -d --build >"$COMPOSE_UP_LOG" 2>&1 || {
    capture_docker_logs
    write_failure_summary "compose_up_failed" "docker compose up failed; see $COMPOSE_UP_LOG"
    exit 1
  }

  if ! wait_for_port; then
    capture_docker_logs
    write_failure_summary "room_port_unavailable" "Room did not start listening on ${HOST}:${PORT} within ${TIMEOUT_SECONDS}s"
    exit 1
  fi
fi

if [[ -z "$SERVER_PUBKEY" ]]; then
  if SERVER_PUBKEY="$(find_server_pubkey_in_repo_data 2>/dev/null)"; then
    :
  else
    capture_docker_logs
    write_failure_summary \
      "missing_server_pubkey" \
      "Could not infer the room public key from ssb-room-data. Pass --server-pubkey or set SSB_ROOM_SERVER_PUBKEY."
    exit 1
  fi
fi

SERVER_PUBKEY="$(normalize_server_pubkey "$SERVER_PUBKEY")"
mkdir -p "$RUNTIME_DIR"

if ! build_smoke_client; then
  capture_docker_logs
  write_failure_summary "build_failed" "Failed to build the room smoke client; see $BUILD_LOG"
  exit 1
fi

set +e
"$CLIENT_BIN" \
  --host "$HOST" \
  --port "$PORT" \
  --server-pubkey "$SERVER_PUBKEY" \
  --work-dir "$RUNTIME_DIR" \
  --trace-file "$TRACE_FILE" \
  --summary-file "$SUMMARY_FILE" \
  --timeout "$TIMEOUT_SECONDS" \
  >"$CLIENT_LOG" 2>&1
CLIENT_STATUS=$?
set -e

if [[ "$CLIENT_STATUS" -ne 0 ]]; then
  capture_docker_logs
  if [[ -f "$SUMMARY_FILE" ]]; then
    cat "$SUMMARY_FILE"
  else
    write_failure_summary "smoke_failed" "Smoke client exited with status $CLIENT_STATUS; see $CLIENT_LOG"
  fi
  exit "$CLIENT_STATUS"
fi

if [[ -f "$SUMMARY_FILE" ]]; then
  cat "$SUMMARY_FILE"
else
  write_failure_summary "missing_summary" "Smoke client exited successfully but did not write a summary"
  exit 1
fi

echo "Artifacts: $TRACE_DIR"
