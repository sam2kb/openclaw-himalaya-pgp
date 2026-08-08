#!/usr/bin/env bash
set -euo pipefail
# Essential test suite for the OpenClaw Himalaya PGP bundle.
# Run from anywhere; tests operate on the bundle tree only and never touch a
# real mail account, keyring, password store, or network.

cd "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/.."

fail=0

SCRIPTS=(install-system.sh install-skill.sh install-bao.sh setup-account.sh verify.sh make-manifest.sh uninstall.sh rotate-credential.sh tests/run-tests.sh)

echo "== bash syntax =="
for s in "${SCRIPTS[@]}"; do
  if bash -n "$s" 2>/dev/null; then
    echo "ok: $s"
  else
    echo "FAIL: $s (bash -n)"; fail=1
  fi
done

echo "== python compile =="
if python3 -m py_compile skill/himalaya/scripts/pgp_send.py patches/fix-1.2.0-await.py tests/test_pgp_send.py tests/test_rotate.py tests/test_patch.py; then
  echo "ok: py_compile"
else
  echo "FAIL: py_compile"; fail=1
fi

echo "== pgp_send.py behavior =="
if python3 -m unittest discover -s tests -p 'test_*.py' -v; then
  echo "ok: unittest"
else
  echo "FAIL: unittest"; fail=1
fi

# unittest/py_compile leave bytecode behind; keep the tree clean.
rm -rf tests/__pycache__ skill/himalaya/scripts/__pycache__ patches/__pycache__

echo "== stray bytecode =="
STRAY="$(find . -path ./.git -prune -o -type d -name '__pycache__' -print -o -type f -name '*.pyc' -print)"
if [[ -n "$STRAY" ]]; then
  echo "FAIL: stray Python bytecode: $STRAY"; fail=1
else
  echo "ok: no stray bytecode"
fi

echo "== manifest =="
if sha256sum -c MANIFEST.sha256 >/dev/null 2>&1; then
  echo "ok: MANIFEST.sha256 in sync"
else
  echo "FAIL: MANIFEST.sha256 out of sync; run ./make-manifest.sh"; fail=1
fi

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  if shellcheck --severity=warning "${SCRIPTS[@]}"; then
    echo "ok: shellcheck"
  else
    echo "FAIL: shellcheck"; fail=1
  fi
else
  echo "skip: shellcheck not installed"
fi

if [[ "$fail" -eq 0 ]]; then
  echo
  echo "ALL TESTS PASSED"
else
  echo
  echo "SOME TESTS FAILED"
  exit 1
fi
