# PGP notes

## Backend

The bundle builds Himalaya 1.2.0 with `pgp-gpg`, and account setup writes:

```toml
pgp.type = "gpg"
```

This uses GPGME bindings instead of Himalaya's shell-command PGP backend.

Himalaya v1.2 MML marks protected parts with the selected PGP backend. The bundled sender uses:

```text
<#part type=text/plain encrypt=gpg sign=gpg>
...
<#/part>
```

For sign-only or encrypt-only, the unused attribute is omitted.

## Key handling

List the configured user's secret keys:

```bash
gpg --list-secret-keys --keyid-format long
```

Look for a recipient key locally or via WKD:

```bash
gpg --auto-key-locate local,wkd --locate-keys recipient@example.com
```

Display the fingerprint before relying on a newly discovered key:

```bash
gpg --fingerprint recipient@example.com
```

Do not mark a key ultimately trusted merely to suppress an encryption error. Trust is a security decision.

## Agent unlock

A passphrase-protected secret key may require pinentry/GPG-agent unlock for both `pass` credential retrieval and PGP signing/decryption. Do not work around that by placing secrets in plaintext config files.
