#!/usr/bin/env bash
set -euo pipefail

# Installs a pinned Himalaya build with the features required by this bundle.
# Run as root: sudo ./install-system.sh

HIMALAYA_VERSION="1.2.0"
INSTALL_ROOT="/opt/himalaya-${HIMALAYA_VERSION}"
CARGO_HOME_DIR="/var/cache/openclaw-himalaya/cargo"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: run this script as root: sudo ./install-system.sh" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: this installer targets Debian/Ubuntu systems using apt." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl build-essential pkg-config cargo rustc \
  libgpgme-dev gnupg2 pass python3

mkdir -p "$INSTALL_ROOT" "$CARGO_HOME_DIR"
export CARGO_HOME="$CARGO_HOME_DIR"

# Build from the crates.io release pinned by Cargo.lock. We intentionally use
# GPGME instead of Himalaya's shell-command PGP backend for message crypto.
cargo install himalaya \
  --version "$HIMALAYA_VERSION" \
  --locked \
  --root "$INSTALL_ROOT" \
  --force \
  --no-default-features \
  --features "imap,smtp,pgp-gpg"

install -m 0755 "$INSTALL_ROOT/bin/himalaya" /usr/local/bin/himalaya

version_out="$(/usr/local/bin/himalaya --version 2>&1 || true)"
if [[ "$version_out" != *"$HIMALAYA_VERSION"* ]]; then
  echo "ERROR: expected Himalaya $HIMALAYA_VERSION, got: $version_out" >&2
  exit 1
fi

echo "Installed: $version_out"
echo "GPGME library: $(gpgme-config --version 2>/dev/null || pkg-config --modversion gpgme 2>/dev/null || echo installed)"
echo "Optional: install the OpenBao client CLI separately if you plan to use an existing OpenBao server for the credential backend (see README)."
echo "Next: run ./install-skill.sh as the Unix user that runs OpenClaw."
