# Upstream references

- Official OpenClaw Himalaya skill:
  https://github.com/openclaw/openclaw/blob/main/skills/himalaya/SKILL.md
- OpenClaw skill creation/loading docs:
  https://github.com/openclaw/openclaw/blob/main/docs/tools/skills.md
  https://github.com/openclaw/openclaw/blob/main/docs/tools/creating-skills.md
- Himalaya v1.2.0:
  https://github.com/pimalaya/himalaya/releases/tag/v1.2.0
- Himalaya v1.2.0 source/config:
  https://github.com/pimalaya/himalaya/tree/v1.2.0

Key design facts used by this bundle:

1. Himalaya v1.2.0 exposes IMAP, SMTP and PGP cargo features.
2. `pgp-gpg` uses GPG bindings/GPGME and requires the GPG library on the system.
3. `pgp-commands` is a separate feature and is not enabled by this bundle.
4. Himalaya v2 changed the CLI and removed the v1 top-level PGP configuration.
5. OpenClaw workspace skills override bundled skills with the same skill name.
