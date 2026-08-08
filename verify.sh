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
print(x.get('credential_source','pass')); print(x.get('credential_path',''))
PY
)
EMAIL="${INFO[0]}"; FP="${INFO[1]}"
CRED_SOURCE="${INFO[2]}"; CRED_PATH="${INFO[3]}"
if [[ -z "$CRED_PATH" ]]; then CRED_PATH="openclaw-mail/$ACCOUNT"; fi

echo "Account: $ACCOUNT ($EMAIL)"
gpg --batch --list-secret-keys "$FP" >/dev/null
case "$CRED_SOURCE" in
  pass)    pass show "$CRED_PATH/imap" >/dev/null ;;
  openbao) bao kv get -field=password "$CRED_PATH/imap" >/dev/null ;;
  *) echo "ERROR: unsupported credential_source '$CRED_SOURCE'" >&2; exit 1 ;;
esac

echo "GPG secret key: OK ($FP)"
echo "Credential retrieval: OK ($CRED_SOURCE)"

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
  echo "PGP send helper dry-run:"
  if printf '%s' "{\"account\":\"$ACCOUNT\",\"to\":[\"$EMAIL\"],\"subject\":\"verify-dry-run\",\"body\":\"configuration and validation check\"}" \
      | "$SCRIPT" --dry-run >/dev/null; then
    echo "OK"
  else
    echo "WARNING: pgp_send.py dry-run failed; the error above explains why (missing key or locked GPG agent are common)." >&2
  fi
else
  echo "WARNING: workspace PGP helper not found at $SCRIPT" >&2
fi

if command -v openclaw >/dev/null 2>&1; then
  openclaw skills list 2>/dev/null | grep -i himalaya || true
fi

echo "Verification complete. No email was sent."
