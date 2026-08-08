# OpenBao credential backend — runtime setup

This bundle can store mail credentials in an existing OpenBao server (chosen
at setup, option 2). The server is external; only the `bao` client CLI is
installed on the OpenClaw host (`sudo ./install-bao.sh`).

## How the mail path authenticates

Himalaya reads the mail password itself, outside OpenClaw's SecretRef
machinery: `config.toml` sets
`backend.auth.cmd = "bao kv get -field=password <path>/imap"`, and Himalaya
spawns that command on the host in the OpenClaw user's session. OpenClaw
never resolves or passes the mail password.

For that command to work, the `bao` client needs, in the OpenClaw user's
runtime environment:

- `BAO_ADDR` — the server address (e.g. `https://bao.example.com:8200`)
- `BAO_CACERT` — path to the server's CA certificate **if it uses a private
  CA** (TLS will fail without it)
- auth material scoped to `secret/mail/<account>/*`:
  - a token (in `BAO_TOKEN` or `~/.bao_token` after `bao login`), or
  - AppRole: `bao login -method=approle role_id=... secret_id=...`

## Claw's own OpenBao access is separate

OpenClaw may already talk to OpenBao through its own SecretRef exec provider
— for example a dedicated resolver service using AppRole with a
TPM-encrypted credential, running as its own OS user with its own
`OPENBAO_ADDR` / `OPENBAO_CACERT` environment. That setup does **not** carry
over to the mail path:

- the resolver's credential is bound to its service/user, not the OpenClaw
  user;
- the mail path runs `bao` as the OpenClaw user and must authenticate on its
  own;
- the env vars the resolver uses (e.g. `OPENBAO_ADDR`) are not what the
  `bao` CLI reads (`BAO_ADDR`).

Mirror the pieces (address, CA) and give the OpenClaw user its own
least-privilege auth.

## Least-privilege policy

Give the OpenClaw user's token/role only:

- `read` on `secret/mail/*` (Himalaya fetching credentials)
- `create`/`update` on `secret/mail/*` (setup-account.sh and
  rotate-credential.sh writing credentials)

Deliberately narrower than the resolver's access; mail passwords stay
separate from whatever else the resolver handles.

## Environment propagation

The agent process that spawns Himalaya must inherit `BAO_ADDR` (and
`BAO_CACERT` if used):

- shell-based agent: export in `~/.bashrc` / `~/.profile`
- systemd service: set `Environment=` / `EnvironmentFile=` in the unit (it
  does not read shell rc files), and make sure `HOME` points at the OpenClaw
  user so `bao` finds `~/.bao_token`

## Token lifecycle

`bao login` writes the token to `~/.bao_token` (0600). When the server-side
token expires, mail auth fails until login is repeated. `verify.sh`'s
"Credential retrieval" line flags this. Prefer a long-lived token for the
mail path, or re-run `bao login` after rotation.
