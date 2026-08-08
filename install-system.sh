#!/usr/bin/env bash
set -euo pipefail

# Installs a pinned Himalaya build with the features required by this bundle.
# Run as root: sudo ./install-system.sh

HIMALAYA_VERSION="1.2.0"
INSTALL_ROOT="/opt/himalaya-${HIMALAYA_VERSION}"
CARGO_HOME_DIR="/var/cache/openclaw-himalaya/cargo"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

# Build from the pinned crates.io source with its shipped Cargo.lock. That
# lock pins `spin 0.9.8`, which is yanked on crates.io, so a locked build
# fails as-is while an unlocked build drifts onto API-incompatible versions.
# The standard fix is cargo's own `cargo update -p spin`: it re-resolves just
# that one package to a non-yanked release and rewrites the checksum itself,
# leaving every other pinned version untouched.
SRC_DIR="$CARGO_HOME_DIR/src/himalaya-${HIMALAYA_VERSION}"
CRATE_ARCHIVE="$CARGO_HOME_DIR/himalaya-${HIMALAYA_VERSION}.crate"
if [[ ! -f "$CRATE_ARCHIVE" ]]; then
  curl --proto '=https' --tlsv1.2 -sSfL \
    "https://static.crates.io/crates/himalaya/himalaya-${HIMALAYA_VERSION}.crate" \
    -o "$CRATE_ARCHIVE"
fi
rm -rf "$SRC_DIR"
mkdir -p "$CARGO_HOME_DIR/src"
tar -xzf "$CRATE_ARCHIVE" -C "$CARGO_HOME_DIR/src"

# The published 1.2.0 source has leftover `.await`s that do not compile
# against its own lock (upstream bug). Apply our fail-closed patch.
python3 "$SCRIPT_DIR/patches/fix-1.2.0-await.py" "$SRC_DIR/src"

# Force the modern stable toolchain for every cargo step: the crate's
# rust-toolchain.toml pins an older channel (1.82.0) that cannot compile the
# lock's newer dependencies.
export RUSTUP_TOOLCHAIN=stable
(cd "$SRC_DIR" && cargo update -p spin)
cargo install \
  --path "$SRC_DIR" \
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
echo "Optional: run ./install-bao.sh (as root) if you plan to use an existing OpenBao server for the credential backend."
echo "Next: run ./install-skill.sh as the Unix user that runs OpenClaw."
