#!/usr/bin/env bash
set -euo pipefail
# Rotates mail credentials for one account in whichever credential backend was
# chosen during setup (pass or OpenBao). Operator tool; not part of the skill.
#
# Usage:
#   ./rotate-credential.sh <account> [imap|smtp|both]   (default: both)
#
# New values are read hidden. For pass the value is fed over stdin; for
# OpenBao it is passed as a `kv put` argument (briefly visible in argv).

ACCOUNT="${1:-}"
if [[ -z "$ACCOUNT" ]]; then
  echo "usage: $0 <account> [imap|smtp|both]" >&2
  exit 1
fi
if [[ ! "$ACCOUNT" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "ERROR: invalid account name" >&2
  exit 1
fi

TARGET="${2:-both}"
case "$TARGET" in
  imap|smtp|both) ;;
  *) echo "ERROR: target must be imap, smtp, or both" >&2; exit 1 ;;
esac

META="$HOME/.config/himalaya/openclaw-pgp/$ACCOUNT.json"
if [[ ! -f "$META" ]]; then
  echo "ERROR: metadata not found: $META (run setup-account.sh first)" >&2
  exit 1
fi
if [[ -L "$META" ]]; then
  echo "ERROR: account metadata must not be a symlink" >&2
  exit 1
fi

readarray -t INFO < <(python3 - "$META" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print(x.get('credential_source','pass'))
print(x.get('credential_path',''))
PY
)
CRED_SOURCE="${INFO[0]}"
CRED_PATH="${INFO[1]}"
if [[ -z "$CRED_PATH" ]]; then
  CRED_PATH="openclaw-mail/$ACCOUNT"
fi
if [[ "$CRED_SOURCE" != "pass" && "$CRED_SOURCE" != "openbao" ]]; then
  echo "ERROR: unsupported credential_source '$CRED_SOURCE'" >&2
  exit 1
fi
if [[ "$CRED_SOURCE" == "openbao" && ! "$CRED_PATH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "ERROR: invalid OpenBao credential_path '$CRED_PATH'" >&2
  exit 1
fi
if [[ "$CRED_SOURCE" == "openbao" ]] && ! command -v bao >/dev/null 2>&1; then
  echo "ERROR: 'bao' CLI not found on PATH" >&2
  exit 1
fi

store() { # $1 = entry name (imap|smtp)
  local name="$1"
  read -r -s -p "New $name password (hidden): " NEW_PW; echo
  if [[ -z "$NEW_PW" ]]; then
    echo "ERROR: empty password" >&2
    exit 1
  fi
  case "$CRED_SOURCE" in
    pass)
      # pass reads the value from stdin, so it never appears in argv/ps.
      printf '%s\n' "$NEW_PW" | pass insert -m -f "$CRED_PATH/$name" >/dev/null
      ;;
    openbao)
      bao kv put "$CRED_PATH/$name" "password=$NEW_PW" >/dev/null
      ;;
  esac
  unset NEW_PW
}

case "$TARGET" in
  imap) store imap ;;
  smtp) store smtp ;;
  both) store imap; store smtp ;;
esac

echo "Rotated $TARGET credential(s) for account '$ACCOUNT' via $CRED_SOURCE."
