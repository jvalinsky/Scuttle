#!/usr/bin/env bash
# Generate an ed25519 keypair for the go-ssb-room dev container.
# Writes to ssb-room-data/ which is volume-mounted into the container at /data.
#
# go-ssb-room secret format requirements:
#   - File permissions: exactly 0600 (enforced by LoadKeyPair)
#   - "private": base64(seed || pubkey) + ".ed25519"  (64 bytes total, NaCl format)
#   - "public":  base64(pubkey) + ".ed25519"            (32 bytes)
#   - "id":      "@" + base64(pubkey) + ".ed25519"
#
# Outputs:
#   ssb-room-data/secret             - go-ssb identity file (0600)
#   ssb-room-data/server-pubkey.bin  - raw 32-byte public key (for Scuttle tests)
#   ssb-room-data/server-id.txt      - @<base64>.ed25519 string (for Scuttle tests)
#
# Usage: ./tools/generate-room-keypair.sh
# Safe to re-run: will NOT overwrite an existing secret (room identity is stable).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../ssb-room-data"
SECRET_FILE="$DATA_DIR/secret"

mkdir -p "$DATA_DIR"

if [ -f "$SECRET_FILE" ]; then
  echo "Room identity already exists at $SECRET_FILE — skipping generation."
  echo "Delete $SECRET_FILE to generate a new identity."
else
  echo "Generating ed25519 keypair for go-ssb-room..."

  TMPDIR_KEYS=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_KEYS"' EXIT

  # Generate ed25519 private key in PEM format
  openssl genpkey -algorithm ed25519 -out "$TMPDIR_KEYS/private.pem" 2>/dev/null

  # Extract raw 32-byte public key (last 32 bytes of SubjectPublicKeyInfo DER)
  openssl pkey -in "$TMPDIR_KEYS/private.pem" -pubout -outform DER 2>/dev/null \
    | tail -c 32 > "$DATA_DIR/server-pubkey.bin"

  # Extract raw 32-byte seed (last 32 bytes of PrivateKeyInfo DER)
  openssl pkey -in "$TMPDIR_KEYS/private.pem" -outform DER 2>/dev/null \
    | tail -c 32 > "$TMPDIR_KEYS/seed.bin"

  # NaCl ed25519 "private key" = seed (32 bytes) || public key (32 bytes) = 64 bytes
  cat "$TMPDIR_KEYS/seed.bin" "$DATA_DIR/server-pubkey.bin" > "$TMPDIR_KEYS/nacl-private.bin"

  PUB_B64=$(base64 < "$DATA_DIR/server-pubkey.bin" | tr -d '\n')
  PRIV_B64=$(base64 < "$TMPDIR_KEYS/nacl-private.bin" | tr -d '\n')
  FEED_ID="@${PUB_B64}.ed25519"

  # Write go-ssb secret format with required 0600 permissions
  (umask 177; cat > "$SECRET_FILE" << EOF
{
  "curve": "ed25519",
  "public": "${PUB_B64}.ed25519",
  "private": "${PRIV_B64}.ed25519",
  "id": "${FEED_ID}"
}
EOF
)

  # Write plain text server ID for test code to read
  echo -n "$FEED_ID" > "$DATA_DIR/server-id.txt"

  echo "Done."
  echo "  Room ID: $FEED_ID"
  echo "  Secret:  $SECRET_FILE (permissions: $(stat -f '%Mp%Lp' "$SECRET_FILE" 2>/dev/null || stat -c '%a' "$SECRET_FILE" 2>/dev/null))"
fi

# Always print the room ID
ROOM_ID=$(python3 -c "import json; d=json.load(open('$SECRET_FILE')); print(d['id'])" 2>/dev/null \
  || cat "$DATA_DIR/server-id.txt" 2>/dev/null \
  || echo "(parse error)")
echo "Room ID: $ROOM_ID"
