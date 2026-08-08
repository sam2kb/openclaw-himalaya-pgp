# OpenClaw + Himalaya + PGP bundle

A hardened Debian setup for the **official OpenClaw Himalaya workflow**, with PGP/MIME and non-plaintext mail credentials.

## What this is

This bundle turns an [OpenClaw](https://github.com/openclaw/openclaw) agent into a secure IMAP/SMTP mail client by overriding OpenClaw's bundled `himalaya` skill with a hardened version. It installs a pinned Himalaya CLI, connects it to your mailbox with encrypted credential storage, adds PGP/MIME signing and encryption, and ships a guarded PGP send helper plus an offline test suite.

It is an **override, not a fork**: the skill is installed at OpenClaw's highest-precedence location (`<workspace>/skills/himalaya`), shadowing the bundled skill without ever modifying it on disk. Remove the override and the stock skill comes back.

## Why it exists

OpenClaw's bundled Himalaya skill is intentionally minimal: it documents the v1 CLI surface but leaves credential handling to the user (its own example even shows a plaintext password inline) and has no PGP story. This bundle closes the gaps that matter in practice:

- **No plaintext credentials.** Mail passwords are stored GPG-encrypted in `pass` (default) or in an existing OpenBao server, referenced from config by `auth.cmd`, and never written into `config.toml`.
- **Real PGP/MIME.** Himalaya is built with GPGME bindings (`pgp-gpg`) so the agent can encrypt, sign, and verify mail through Himalaya — while private keys stay in the user's GnuPG keyring and never pass through the agent.
- **Safe PGP sending.** `pgp_send.py` turns structured JSON into MML and hands it to Himalaya with `shell=False`, rejecting header/MML injection and pre-checking recipient keys. No shell command is ever built from message content.
- **Version drift protection.** The official skill targets Himalaya v1 commands (`folder list`, `envelope list`, `message read`, `template send`), but Himalaya 2.x changed the CLI and moved composition to a separate `mml` tool. The bundle pins the known-compatible **1.2.0** line so the skill's commands and the installed binary always match.
- **Guardrails.** Incoming mail is untrusted data: the skill requires confirmation before sends and bulk mutations, and never lets message content drive shell commands, key-trust changes, or config edits.

## What it installs

- Himalaya **1.2.0**, pinned
- IMAP + SMTP support
- PGP through **GPGME bindings** (`pgp.type = "gpg"`), not shell PGP commands
- GnuPG
- `pass` (default) or OpenBao for IMAP/SMTP credentials
- a workspace `himalaya` skill override adding PGP and stricter safety rules
- a validated PGP send helper for OpenClaw
- a credential rotation tool (`rotate-credential.sh`)
- an offline test suite (`tests/`)

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

The default shell-command PGP backend is deliberately excluded. Dependencies are pinned by the crate's shipped `Cargo.lock`; the build runs `cargo update -p spin` first (that lock pins the yanked `spin 0.9.8`), applies a fail-closed source patch for the upstream 1.2.0 `.await` bug (`patches/fix-1.2.0-await.py`), and uses a rustup toolchain because the crate's pinned 1.82.0 cannot compile its own lock.

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

It finds an existing GPG secret key for the mailbox email address or lets you launch interactive GPG key creation. Mail credentials are written into a per-account `pass` subtree (default) or an OpenBao KV store (optional), never into Himalaya's TOML.

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

## OpenBao credential backend

At setup you can store mail credentials in an existing OpenBao server instead of `pass` (choice 2). This bundle never installs or runs an OpenBao server — `bao` is used purely as a client CLI, connecting to whatever `BAO_ADDR` points to.

Requirements:

- the `bao` client CLI installed and on PATH (the server is external; nothing is installed on the OpenClaw host)
- `BAO_ADDR` set to your server, for example `https://vault.example.com:8200`
- a usable token, for example after `bao login` (the CLI stores it in `~/.bao_token`, which is what lets Himalaya's non-interactive `auth.cmd` authenticate)

If your server uses a custom CA or mutual TLS, set the standard OpenBao variables (`BAO_CACERT`, `BAO_CLIENT_CERT`, `BAO_CLIENT_KEY`) — they are inherited by Himalaya and `rotate-credential.sh` because those tools run on the same host and user.

Setup writes each credential as `bao kv put <path>/<entry> password=...` and generates `auth.cmd = "bao kv get -field=password <path>/<entry>"`. The default path prefix is `secret/mail/<account>`, with `imap` and `smtp` entries.

### Rotation

`./rotate-credential.sh <account> [imap|smtp|both]` rotates credentials in whichever backend the account uses (default `both`). Himalaya fetches credentials per connection, so the new value is picked up on the next mail operation:

```bash
./rotate-credential.sh default
```

Note: OpenBao `kv put` passes the new value as a command-line argument (briefly visible via `ps`); `pass` reads it from stdin. Prefer `pass` if that exposure is unacceptable.

## Headless/GPG-agent note

If your private key has a passphrase, `pass`, signing, and decryption may need the GPG agent to be unlocked. This bundle does **not** weaken that by writing passwords or private-key passphrases to plaintext files.

## PGP attachments

The bundled safe PGP sender intentionally handles plain-text message bodies only. It does not silently send an attachment unencrypted. Add encrypted-attachment support only after testing the exact MML multipart behavior you want.

## Files

```text
install-system.sh              root: installs pinned Himalaya build + dependencies
patches/                       fail-closed upstream-bug patches (fix-1.2.0-await.py)
install-skill.sh               user: installs workspace skill override
setup-account.sh               user: credentials, IMAP/SMTP config, PGP identity
verify.sh                      user: connectivity/security checks, sends nothing
make-manifest.sh               dev: regenerates MANIFEST.sha256
uninstall.sh                   user: removes system binary, workspace skill, and account data
rotate-credential.sh           user: rotate mail credentials in pass or OpenBao
tests/                         essential test suite (run tests/run-tests.sh)
skill/himalaya/SKILL.md        OpenClaw skill
skill/himalaya/scripts/        guarded PGP send helper
skill/himalaya/references/     security + PGP notes
templates/                     reference config
SOURCES.md                     upstream/version rationale
```
