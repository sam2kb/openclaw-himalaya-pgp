#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "ERROR: run this as the same non-root Unix user that runs OpenClaw." >&2
  exit 1
fi

for bin in himalaya gpg pass python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing $bin" >&2; exit 1; }
done

if ! himalaya --version 2>&1 | grep -q '1\.2\.0'; then
  echo "ERROR: this bundle is pinned to Himalaya 1.2.0." >&2
  himalaya --version >&2 || true
  exit 1
fi

read -r -p "Account name [default]: " ACCOUNT
ACCOUNT="${ACCOUNT:-default}"
if [[ ! "$ACCOUNT" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "ERROR: account name may contain only letters, numbers, underscore, and hyphen." >&2
  exit 1
fi

read -r -p "Email address: " EMAIL
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]; then
  echo "ERROR: for safety this setup accepts conventional email addresses only." >&2
  exit 1
fi

read -r -p "Display name [${EMAIL%%@*}]: " DISPLAY_NAME
DISPLAY_NAME="${DISPLAY_NAME:-${EMAIL%%@*}}"
if [[ "$DISPLAY_NAME" =~ [^[:print:]] ]]; then
  echo "ERROR: display name may contain printable characters only." >&2
  exit 1
fi

cat <<'MENU'
Provider:
  1) Generic IMAP/SMTP
  2) Gmail (App Password)
  3) iCloud Mail (app-specific password)
  4) Proton Mail Bridge (local IMAP/SMTP)
MENU
read -r -p "Choice [1]: " PROVIDER
PROVIDER="${PROVIDER:-1}"

IMAP_HOST=""; IMAP_PORT=""; IMAP_ENC=""; SMTP_HOST=""; SMTP_PORT=""; SMTP_ENC=""; FOLDER_LINES=""
case "$PROVIDER" in
  1)
    read -r -p "IMAP host: " IMAP_HOST
    read -r -p "IMAP port [993]: " IMAP_PORT; IMAP_PORT="${IMAP_PORT:-993}"
    read -r -p "IMAP encryption [tls/start-tls/none] [tls]: " IMAP_ENC; IMAP_ENC="${IMAP_ENC:-tls}"
    read -r -p "SMTP host: " SMTP_HOST
    read -r -p "SMTP port [587]: " SMTP_PORT; SMTP_PORT="${SMTP_PORT:-587}"
    read -r -p "SMTP encryption [tls/start-tls/none] [start-tls]: " SMTP_ENC; SMTP_ENC="${SMTP_ENC:-start-tls}"
    ;;
  2)
    IMAP_HOST="imap.gmail.com"; IMAP_PORT="993"; IMAP_ENC="tls"
    SMTP_HOST="smtp.gmail.com"; SMTP_PORT="465"; SMTP_ENC="tls"
    FOLDER_LINES=$'folder.aliases.inbox = "INBOX"\nfolder.aliases.sent = "[Gmail]/Sent Mail"\nfolder.aliases.drafts = "[Gmail]/Drafts"\nfolder.aliases.trash = "[Gmail]/Trash"'
    ;;
  3)
    IMAP_HOST="imap.mail.me.com"; IMAP_PORT="993"; IMAP_ENC="tls"
    SMTP_HOST="smtp.mail.me.com"; SMTP_PORT="587"; SMTP_ENC="start-tls"
    ;;
  4)
    IMAP_HOST="127.0.0.1"; IMAP_PORT="1143"; IMAP_ENC="none"
    SMTP_HOST="127.0.0.1"; SMTP_PORT="1025"; SMTP_ENC="none"
    echo "Using the default Proton Bridge ports. Edit config.toml if your Bridge shows different ports."
    ;;
  *) echo "ERROR: invalid provider choice" >&2; exit 1 ;;
esac

# Hosts are written inside TOML strings, so whitespace/control characters
# would silently corrupt the config. Accept conservative hostname/IPv4/IPv6
# syntax only.
HOST_RE='^[A-Za-z0-9.:_-]+$'
for h in "$IMAP_HOST" "$SMTP_HOST"; do
  [[ "$h" =~ $HOST_RE ]] || { echo "ERROR: invalid host '$h'" >&2; exit 1; }
done

for p in "$IMAP_PORT" "$SMTP_PORT"; do
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )) || { echo "ERROR: invalid port $p" >&2; exit 1; }
done
for e in "$IMAP_ENC" "$SMTP_ENC"; do
  [[ "$e" == "tls" || "$e" == "start-tls" || "$e" == "none" ]] || { echo "ERROR: invalid encryption type $e" >&2; exit 1; }
done

# Select the PGP identity used for signing/decryption.
PGP_FP="$(gpg --batch --with-colons --list-secret-keys "$EMAIL" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
if [[ -z "$PGP_FP" ]]; then
  echo "No secret GPG key found for $EMAIL."
  read -r -p "Launch interactive 'gpg --full-generate-key' now? [y/N]: " MAKE_KEY
  if [[ "$MAKE_KEY" =~ ^[Yy]$ ]]; then
    gpg --full-generate-key
    PGP_FP="$(gpg --batch --with-colons --list-secret-keys "$EMAIL" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
  fi
fi
if [[ -z "$PGP_FP" ]]; then
  read -r -p "Enter an existing secret-key fingerprint to use: " PGP_FP
fi
PGP_FP="${PGP_FP// /}"
if [[ ! "$PGP_FP" =~ ^[A-Fa-f0-9]{40,64}$ ]]; then
  echo "ERROR: invalid GPG fingerprint." >&2
  exit 1
fi
if ! gpg --batch --list-secret-keys "$PGP_FP" >/dev/null 2>&1; then
  echo "ERROR: secret key $PGP_FP is not available to this Unix user." >&2
  exit 1
fi

echo "PGP identity: $PGP_FP"

echo
echo "Mail credential storage:"
echo "  1) pass (default; GPG-encrypted, offline, host-local)"
echo "  2) OpenBao (external KV store; centralized rotation)"
read -r -p "Choice [1]: " CRED_STORE
CRED_STORE="${CRED_STORE:-1}"
case "$CRED_STORE" in
  1)
    CRED_SOURCE="pass"
    CRED_PATH="openclaw-mail/$ACCOUNT"
    ;;
  2)
    CRED_SOURCE="openbao"
    if ! command -v bao >/dev/null 2>&1; then
      echo "ERROR: 'bao' CLI not found. Install OpenBao first (see README)." >&2
      exit 1
    fi
    if ! bao token lookup >/dev/null 2>&1; then
      echo "ERROR: cannot reach/authenticate OpenBao at BAO_ADDR. Set BAO_ADDR (e.g. https://vault.example.com:8200) and log in ('bao login') first." >&2
      exit 1
    fi
    read -r -p "OpenBao KV path prefix [secret/mail/$ACCOUNT]: " CRED_PATH
    CRED_PATH="${CRED_PATH:-secret/mail/$ACCOUNT}"
    if [[ ! "$CRED_PATH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
      echo "ERROR: OpenBao path may contain letters, numbers, dots, hyphens, slashes, and underscores only." >&2
      exit 1
    fi
    ;;
  *) echo "ERROR: invalid credential storage choice" >&2; exit 1 ;;
esac
echo "Credential storage: $CRED_SOURCE ($CRED_PATH)"

# pass: use a per-account subtree so adding another account does not re-key
# unrelated entries, and ensure the subtree is decryptable by the chosen key.
if [[ "$CRED_SOURCE" == "pass" ]]; then
  PASS_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}/$CRED_PATH"
  if [[ ! -f "$PASS_DIR/.gpg-id" ]]; then
    pass init -p "$CRED_PATH" "$PGP_FP"
  elif ! grep -Fq "$PGP_FP" "$PASS_DIR/.gpg-id"; then
    echo "Existing pass subtree $CRED_PATH is not initialized for key $PGP_FP." >&2
    read -r -p "Add this key and re-encrypt the subtree now? [y/N]: " REINIT
    if [[ "$REINIT" =~ ^[Yy]$ ]]; then
      pass init -p "$CRED_PATH" "$PGP_FP"
    else
      echo "ERROR: refusing to continue: the new PGP key could not read stored credentials." >&2
      exit 1
    fi
  fi
fi

store_credential() { # $1 = entry name (imap|smtp)
  local name="$1"
  read -r -s -p "Password for $name (hidden): " NEW_PW; echo
  if [[ -z "$NEW_PW" ]]; then echo "ERROR: empty password" >&2; exit 1; fi
  case "$CRED_SOURCE" in
    pass)
      # pass reads the value from stdin, so it never appears in argv/ps.
      printf '%s\n' "$NEW_PW" | pass insert -m -f "$CRED_PATH/$name" >/dev/null
      ;;
    openbao)
      # Standard OpenBao interface; the value is briefly visible in argv.
      bao kv put "$CRED_PATH/$name" "password=$NEW_PW" >/dev/null
      ;;
  esac
  unset NEW_PW
}

store_credential imap

read -r -p "Use the same credential for SMTP? [Y/n]: " SAME_SMTP
SAME_SMTP="${SAME_SMTP:-Y}"
if [[ "$SAME_SMTP" =~ ^[Nn]$ ]]; then
  store_credential smtp
  SMTP_CRED_ENTRY="smtp"
else
  SMTP_CRED_ENTRY="imap"
fi

CONFIG_DIR="$HOME/.config/himalaya"
CONFIG="$CONFIG_DIR/config.toml"
META_DIR="$CONFIG_DIR/openclaw-pgp"
mkdir -p "$CONFIG_DIR" "$META_DIR"
chmod 700 "$CONFIG_DIR" "$META_DIR"

if [[ -f "$CONFIG" ]] && grep -Eq "^\[accounts\.${ACCOUNT}\][[:space:]]*$" "$CONFIG"; then
  echo "ERROR: account '$ACCOUNT' already exists in $CONFIG. Remove/update it manually, then rerun." >&2
  exit 1
fi

if [[ -f "$CONFIG" ]]; then
  cp -a "$CONFIG" "$CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
fi

if [[ -f "$CONFIG" ]] && grep -q '^\[accounts\.' "$CONFIG"; then
  DEFAULT="false"
else
  DEFAULT="true"
fi

# Escape only the TOML strings we permit user control over.
toml_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
E_EMAIL="$(toml_escape "$EMAIL")"
E_DISPLAY="$(toml_escape "$DISPLAY_NAME")"
E_IMAP_HOST="$(toml_escape "$IMAP_HOST")"
E_SMTP_HOST="$(toml_escape "$SMTP_HOST")"

{
  [[ -s "$CONFIG" ]] && printf '\n'
  printf '[accounts.%s]\n' "$ACCOUNT"
  printf 'email = "%s"\n' "$E_EMAIL"
  printf 'display-name = "%s"\n' "$E_DISPLAY"
  printf 'default = %s\n' "$DEFAULT"
  printf 'downloads-dir = "~/Downloads/himalaya"\n\n'
  [[ -n "$FOLDER_LINES" ]] && printf '%s\n\n' "$FOLDER_LINES"
  printf 'backend.type = "imap"\n'
  printf 'backend.host = "%s"\n' "$E_IMAP_HOST"
  printf 'backend.port = %s\n' "$IMAP_PORT"
  printf 'backend.encryption.type = "%s"\n' "$IMAP_ENC"
  printf 'backend.login = "%s"\n' "$E_EMAIL"
  printf 'backend.auth.type = "password"\n'
  if [[ "$CRED_SOURCE" == "pass" ]]; then
    printf 'backend.auth.cmd = "pass show %s/imap"\n\n' "$CRED_PATH"
  else
    printf 'backend.auth.cmd = "bao kv get -field=password %s/imap"\n\n' "$CRED_PATH"
  fi
  printf 'message.send.backend.type = "smtp"\n'
  printf 'message.send.backend.host = "%s"\n' "$E_SMTP_HOST"
  printf 'message.send.backend.port = %s\n' "$SMTP_PORT"
  printf 'message.send.backend.encryption.type = "%s"\n' "$SMTP_ENC"
  printf 'message.send.backend.login = "%s"\n' "$E_EMAIL"
  printf 'message.send.backend.auth.type = "password"\n'
  if [[ "$CRED_SOURCE" == "pass" ]]; then
    printf 'message.send.backend.auth.cmd = "pass show %s/%s"\n' "$CRED_PATH" "$SMTP_CRED_ENTRY"
  else
    printf 'message.send.backend.auth.cmd = "bao kv get -field=password %s/%s"\n' "$CRED_PATH" "$SMTP_CRED_ENTRY"
  fi
  printf 'message.send.save-copy = true\n\n'
  printf '# PGP/MIME via GPGME. No shell command receives message-controlled recipients.\n'
  printf 'pgp.type = "gpg"\n'
} >> "$CONFIG"
chmod 600 "$CONFIG"

python3 - "$META_DIR/$ACCOUNT.json" "$ACCOUNT" "$EMAIL" "$PGP_FP" "$CRED_SOURCE" "$CRED_PATH" <<'PY'
import json, os, sys
path, account, email, fp, cred_source, cred_path = sys.argv[1:]
data = {
    "account": account,
    "email": email,
    "pgp_fingerprint": fp,
    "backend": "gpg",
    "credential_source": cred_source,
    "credential_path": cred_path,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
os.chmod(path, 0o600)
PY

mkdir -p "$HOME/Downloads/himalaya"
chmod 700 "$HOME/Downloads/himalaya"

echo
echo "Checking account configuration..."
himalaya account list

echo
echo "Testing IMAP connection (folder list)..."
himalaya --account "$ACCOUNT" folder list

echo
echo "Account '$ACCOUNT' configured."
echo "Config: $CONFIG"
echo "Credential storage: $CRED_SOURCE ($CRED_PATH)"
echo "PGP key: $PGP_FP"
echo "Next: ./verify.sh $ACCOUNT"
