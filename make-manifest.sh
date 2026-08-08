#!/usr/bin/env bash
set -euo pipefail
# Regenerates MANIFEST.sha256 for the bundle from the files on disk.
# Run from the bundle root after editing any tracked file:
#   ./make-manifest.sh
# The manifest includes this script's own hash, so run it again after any
# edit to this script. tests/run-tests.sh verifies the manifest is in sync.

cd "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

find . -type f \
  -not -path './.git/*' \
  -not -name 'MANIFEST.sha256' \
  -not -path '*/__pycache__/*' \
  -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256

echo "Wrote MANIFEST.sha256 ($(wc -l < MANIFEST.sha256) entries)."
