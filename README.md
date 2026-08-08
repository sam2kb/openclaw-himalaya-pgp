# OpenClaw + Himalaya + PGP bundle

A hardened Debian setup for the **official OpenClaw Himalaya workflow**, with PGP/MIME and non-plaintext mail credentials.

## What it installs

- Himalaya **1.2.0**, pinned
- IMAP + SMTP support
- PGP through **GPGME bindings** (`pgp.type = "gpg"`), not shell PGP commands
- GnuPG
- `pass` for IMAP/SMTP credentials
- a workspace `himalaya` skill override adding PGP and stricter safety rules
- a validated PGP send helper for OpenClaw

The workspace override does **not** modify OpenClaw's bundled skill on disk. OpenClaw gives workspace skills higher precedence.

## Why Himalaya 1.2.0

The current official OpenClaw Himalaya skill uses Himalaya v1 commands such as `folder list`, `envelope list`, `message read`, `message reply`, and `template send`. Himalaya 2.0 changed the command surface and moved composition/PGP responsibilities around. This bundle stays on the known-compatible v1.2.0 line.

## Install

Unzip the bundle and enter it:

```bash
unzip openclaw-himalaya-pgp.zip
cd openclaw-himalaya-pgp
```

### 1. Install system components

```bash
sudo ./install-system.sh
```

This compiles the exact crates.io release `himalaya 1.2.0` with only:

```text
imap,smtp,pgp-gpg
```

The default shell-command PGP backend is deliberately excluded.

### 2. Install the OpenClaw workspace skill

Run this **as the Unix user that runs OpenClaw**, not root:

```bash
./install-skill.sh
```

Default target:

```text
~/.openclaw/workspace/skills/himalaya/
```

Set `OPENCLAW_WORKSPACE` first if your agent uses another workspace.

### 3. Configure the mail account + PGP key

Again as the OpenClaw Unix user:

```bash
./setup-account.sh
```

The setup supports:

- generic IMAP/SMTP
- Gmail App Password
- iCloud app-specific password
- Proton Mail Bridge

It finds an existing GPG secret key for the mailbox email address or lets you launch interactive GPG key creation. Mail credentials are written into a per-account `pass` subtree, not into Himalaya's TOML.

### 4. Verify without sending mail

```bash
./verify.sh default
```

Replace `default` with the account name chosen during setup.

### 5. Reload OpenClaw

```bash
openclaw gateway restart
```

Or start a fresh session so the updated skill snapshot is loaded.

### 6. Test the bundle (sends nothing)

```bash
./tests/run-tests.sh
```

Runs bash syntax checks, the `pgp_send.py` validation battery (with fake keys), and confirms `MANIFEST.sha256` is in sync. After editing any tracked file, regenerate the manifest:

```bash
./make-manifest.sh
```

### 7. Uninstall

```bash
./uninstall.sh
```

Removes the system binary, the workspace skill override, and (with confirmation) the mail accounts, `pass` subtree, and downloads directory. Your GPG keyring is never touched.

## PGP send helper

OpenClaw is instructed to use:

```text
~/.openclaw/workspace/skills/himalaya/scripts/pgp_send.py
```

Example dry run:

```bash
printf '%s' '{
  "account":"default",
  "to":["alice@example.com"],
  "subject":"PGP test",
  "body":"This is protected.",
  "mode":"encrypt-sign"
}' | python3 ~/.openclaw/workspace/skills/himalaya/scripts/pgp_send.py --dry-run
```

`--dry-run` validates the full pipeline, including key availability, without sending anything. The helper fails fast with an actionable message if your signing key is unavailable or (for encrypt modes) a recipient has no public key.

Supported modes:

- `encrypt-sign`
- `encrypt-only`
- `sign-only`

The helper intentionally accepts only conservative normal email-address syntax, rejects header newlines and MML directives in message bodies, and invokes Himalaya with `shell=False`.

## Recipient keys

Prefer an already-verified local key. WKD can locate a domain-published key:

```bash
gpg --auto-key-locate local,wkd --locate-keys alice@example.com
gpg --fingerprint alice@example.com
```

Verify a new fingerprint through an appropriate independent channel before treating it as trusted.

## Headless/GPG-agent note

If your private key has a passphrase, `pass`, signing, and decryption may need the GPG agent to be unlocked. This bundle does **not** weaken that by writing passwords or private-key passphrases to plaintext files.

## PGP attachments

The bundled safe PGP sender intentionally handles plain-text message bodies only. It does not silently send an attachment unencrypted. Add encrypted-attachment support only after testing the exact MML multipart behavior you want.

## Files

```text
install-system.sh              root: installs pinned Himalaya build + dependencies
install-skill.sh               user: installs workspace skill override
setup-account.sh               user: credentials, IMAP/SMTP config, PGP identity
verify.sh                      user: connectivity/security checks, sends nothing
make-manifest.sh               dev: regenerates MANIFEST.sha256
uninstall.sh                   user: removes system binary, workspace skill, and account data
tests/                         essential test suite (run tests/run-tests.sh)
skill/himalaya/SKILL.md        OpenClaw skill
skill/himalaya/scripts/        guarded PGP send helper
skill/himalaya/references/     security + PGP notes
templates/                     reference config
SOURCES.md                     upstream/version rationale
```
