#!/usr/bin/env bash
set -euo pipefail
# Removes what this bundle installed on the current machine:
#   - /usr/local/bin/himalaya                        (install-system.sh)
#   - ~/.openclaw/workspace/skills/himalaya          (install-skill.sh)
#   - ~/.config/himalaya + pass subtree + downloads  (setup-account.sh)
# Your GnuPG keyring is never modified.

echo "This will remove:"
echo "  - /usr/local/bin/himalaya (system binary; needs sudo if not run as root)"
echo "  - \$HOME/.openclaw/workspace/skills/himalaya (workspace skill override)"
echo "  - \$HOME/.config/himalaya (mail accounts + PGP metadata)"
echo "  - \$HOME/.password-store/openclaw-mail (mail credentials in pass)"
echo "  - \$HOME/Downloads/himalaya (downloads directory)"
read -r -p "Continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# 1. System binary.
if [[ -f /usr/local/bin/himalaya ]]; then
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    rm -f /usr/local/bin/himalaya
    echo "Removed /usr/local/bin/himalaya"
  else
    echo "Run 'sudo rm /usr/local/bin/himalaya' to remove the system binary, or rerun this script as root."
  fi
fi

# 2. Workspace skill override.
rm -rf "$HOME/.openclaw/workspace/skills/himalaya"
echo "Removed workspace skill override"

# 3. Mail account data (config, pass subtree, downloads).
read -r -p "Remove mail accounts, pass subtree, and downloads too? [y/N]: " REMOVE_DATA
if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
  rm -rf "$HOME/.config/himalaya"
  if command -v pass >/dev/null 2>&1; then
    pass rm -rf openclaw-mail 2>/dev/null || true
  fi
  rm -rf "$HOME/Downloads/himalaya"
  echo "Removed mail account data"
  echo "Note: OpenBao KV secrets (if used) are not removed by this script; delete them manually, e.g. 'bao kv metadata delete secret/mail/<account>'."
else
  echo "Kept mail account data under \$HOME/.config/himalaya and pass"
fi

echo "Uninstall complete."
echo "Optional cleanup: sudo apt-get remove cargo rustc libgpgme-dev gnupg2 pass python3"
