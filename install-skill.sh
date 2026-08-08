#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "ERROR: do not run this as root. Run it as the Unix user that runs OpenClaw." >&2
  exit 1
fi

for bin in himalaya gpg pass python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing $bin" >&2; exit 1; }
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
TARGET="$WORKSPACE/skills/himalaya"
SOURCE="$SCRIPT_DIR/skill/himalaya"

mkdir -p "$WORKSPACE/skills"
if [[ -d "$TARGET" ]]; then
  backup="${TARGET}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$TARGET" "$backup"
  echo "Backed up existing workspace Himalaya override to: $backup"
fi

cp -a "$SOURCE" "$TARGET"
chmod 700 "$TARGET/scripts"
chmod 700 "$TARGET/scripts/pgp_send.py"

if command -v openclaw >/dev/null 2>&1; then
  echo "OpenClaw skill status:"
  openclaw skills list 2>/dev/null | grep -i himalaya || true
  echo "Restart the gateway or start a new session after account setup."
else
  echo "WARNING: openclaw CLI is not on PATH for this user. Skill files were still installed at $TARGET"
fi

echo "Installed workspace override: $TARGET"
