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

# Debian's apt rustc is frequently too old for freshly resolved dependencies
# (e.g. ar_archive_writer requires recent `let`-chain syntax), which breaks
# `cargo install` for the pinned himalaya line. Install a modern stable
# toolchain via rustup, self-contained under the bundle's own directories.
export RUSTUP_HOME="$INSTALL_ROOT/rustup"
export CARGO_HOME="$CARGO_HOME_DIR"
if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
  echo "Installing rustup (minimal, stable toolchain)..."
  RUSTUP_INIT="$(mktemp)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$RUSTUP_INIT"
  sh "$RUSTUP_INIT" -y --profile minimal --default-toolchain stable
  rm -f "$RUSTUP_INIT"
fi
export PATH="$CARGO_HOME/bin:$PATH"
cargo --version
rustc --version

# Build the exact crates.io release with GPGME instead of Himalaya's
# shell-command PGP backend for message crypto. The `--locked` flag is
# intentionally omitted: the crate's shipped Cargo.lock pins `spin 0.9.8`,
# which is yanked on crates.io, so locked resolution fails. The himalaya
# version itself stays pinned via --version, and the rustup toolchain above
# guarantees a compiler new enough for whatever resolution lands.
cargo install himalaya \
  --version "$HIMALAYA_VERSION" \
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
