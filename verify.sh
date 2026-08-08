#!/usr/bin/env bash
set -euo pipefail
ACCOUNT="${1:-default}"

printf '%-24s' "Himalaya version"
himalaya --version
if ! himalaya --version 2>&1 | grep -q '1\.2\.0'; then
  echo "ERROR: expected Himalaya 1.2.0" >&2; exit 1
fi

META="$HOME/.config/himalaya/openclaw-pgp/$ACCOUNT.json"
if [[ ! -f "$META" ]]; then echo "ERROR: missing metadata $META" >&2; exit 1; fi

readarray -t INFO < <(python3 - "$META" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x['email']); print(x['pgp_fingerprint'])
PY
)
EMAIL="${INFO[0]}"; FP="${INFO[1]}"

echo "Account: $ACCOUNT ($EMAIL)"
gpg --batch --list-secret-keys "$FP" >/dev/null
pass show "openclaw-mail/$ACCOUNT/imap" >/dev/null

echo "GPG secret key: OK ($FP)"
echo "Credential retrieval: OK"

echo "IMAP folder listing:"
himalaya --account "$ACCOUNT" folder list

echo "Recent envelope query:"
himalaya --account "$ACCOUNT" envelope list --page 1 || {
  echo "WARNING: envelope query failed; folder connectivity succeeded earlier." >&2
}

SCRIPT="$HOME/.openclaw/workspace/skills/himalaya/scripts/pgp_send.py"
if [[ -f "$SCRIPT" ]]; then
  python3 -m py_compile "$SCRIPT"
  echo "PGP send helper syntax: OK"
else
  echo "WARNING: workspace PGP helper not found at $SCRIPT" >&2
fi

if command -v openclaw >/dev/null 2>&1; then
  openclaw skills list 2>/dev/null | grep -i himalaya || true
fi

echo "Verification complete. No email was sent."
