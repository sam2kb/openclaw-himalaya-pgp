#!/usr/bin/env bash
set -euo pipefail
# Installs the OpenBao client CLI (client only; the server stays external)
# from official GitHub releases into /usr/local/bin.
#
# Usage: sudo ./install-bao.sh
# Optional: BAO_VERSION=2.6.1 to pin a specific release (default: latest).
# Requires: curl, tar. No server is installed and nothing runs as a service.
#
# The download is served over HTTPS. Releases also publish `.tar.gz.gpgsig`
# and `.sigstore.json` artifacts if you want signature verification on top.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: run this script as root: sudo ./install-bao.sh" >&2
  exit 1
fi

for bin in curl tar; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing $bin" >&2; exit 1; }
done

[[ "$(uname -s)" == "Linux" ]] || { echo "ERROR: this installer targets Linux." >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)  BINARCH="amd64" ;;
  aarch64|arm64) BINARCH="arm64" ;;
  armv6l)        BINARCH="armv6" ;;
  armv7l)        BINARCH="armv6" ;;  # openbao ships armv6; it runs on armv7
  *) echo "ERROR: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ -n "${BAO_VERSION:-}" ]]; then
  VERSION="${BAO_VERSION#v}"
else
  VERSION="$(curl -fsSL https://api.github.com/repos/openbao/openbao/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')"
  VERSION="${VERSION#v}"
fi
[[ -n "$VERSION" ]] || { echo "ERROR: could not determine the latest release tag." >&2; exit 1; }

ASSET="openbao_${VERSION}_linux_${BINARCH}.tar.gz"
URL="https://github.com/openbao/openbao/releases/download/v${VERSION}/${ASSET}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading ${ASSET} (v${VERSION})..."
curl -fsSL "$URL" -o "$TMPDIR/$ASSET"

echo "Installing /usr/local/bin/bao ..."
tar -xzf "$TMPDIR/$ASSET" -C "$TMPDIR"
install -m 0755 "$TMPDIR/bao" /usr/local/bin/bao

bao version
echo
echo "OpenBao client CLI installed."
echo "Next: export BAO_ADDR=... , run 'bao login', then ./setup-account.sh (choose OpenBao)."
