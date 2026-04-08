#!/bin/bash
# generate-userdata.sh
# Injicerar SSH-pubkey i user-data-template innan packer build.
#
# Användning:
#   ./generate-userdata.sh [sökväg-till-pubkey]
#   Default: ~/.ssh/id_ed25519.pub

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_PATH="${1:-$HOME/.ssh/id_ed25519.pub}"

if [ ! -f "$KEY_PATH" ]; then
  echo "FEL: Hittade ingen pubkey på $KEY_PATH"
  echo "Ange sökväg som argument: ./generate-userdata.sh /path/to/key.pub"
  exit 1
fi

SSH_KEY="$(cat "$KEY_PATH")"

sed "s|SSH_PUBLIC_KEY_PLACEHOLDER|${SSH_KEY}|g" \
  "$SCRIPT_DIR/files/user-data.tpl" > "$SCRIPT_DIR/files/user-data"

echo "Klar: files/user-data skapad med nyckel från $KEY_PATH"
