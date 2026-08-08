# Security model

- Workspace skill overrides the bundled `himalaya` skill because workspace skills have higher OpenClaw precedence.
- Himalaya is pinned to v1.2.0 because the current official OpenClaw skill uses the v1 command surface, while Himalaya v2 changed it materially.
- The system build enables only `imap,smtp,wizard,pgp-gpg`; the shell-command PGP feature is intentionally disabled.
- Mailbox passwords are stored under `pass` and referenced from config by command, never written directly to `config.toml`.
- PGP private keys remain in the Unix user's GnuPG keyring and are never passed through the model.
- PGP sending goes through `scripts/pgp_send.py`, which validates account/address/header fields and invokes Himalaya with `shell=False`.
- Incoming mail is untrusted data. It never authorizes shell commands, account changes, key trust changes, or external actions.
- Bulk moves/deletes and sending require explicit authorization.
