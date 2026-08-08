#!/usr/bin/env python3
"""Safe PGP/MIME sender for the OpenClaw Himalaya skill.

Input is JSON on stdin. The script validates all header-controlled fields,
constructs MML in memory, and invokes Himalaya without a shell.

Example:
  printf '%s' '{"account":"default","to":["alice@example.com"],"subject":"Hi","body":"Secret"}' \
    | pgp_send.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ACCOUNT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
# Intentionally conservative. This excludes unusual-but-valid RFC mailbox forms
# so an address can never contain shell/MML/header metacharacters.
EMAIL_RE = re.compile(r"^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$")
MODES = {
    "encrypt-sign": "encrypt=gpg sign=gpg",
    "encrypt-only": "encrypt=gpg",
    "sign-only": "sign=gpg",
}


def die(msg: str, code: int = 2) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def clean_address(value: object) -> str:
    if not isinstance(value, str) or not EMAIL_RE.fullmatch(value):
        die(f"unsafe or unsupported email address: {value!r}")
    return value


def clean_address_list(value: object, field: str, required: bool = False) -> list[str]:
    if value is None:
        value = []
    if not isinstance(value, list) or len(value) > 25:
        die(f"{field} must be a JSON list of at most 25 addresses")
    out = [clean_address(v) for v in value]
    if required and not out:
        die(f"{field} requires at least one recipient")
    return out


def load_metadata(account: str) -> dict:
    path = Path.home() / ".config" / "himalaya" / "openclaw-pgp" / f"{account}.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"account metadata not found: {path}; run setup-account.sh first")
    except json.JSONDecodeError as exc:
        die(f"invalid account metadata: {exc}")
    if data.get("account") != account:
        die("account metadata mismatch")
    if data.get("backend") != "gpg":
        die("account is not configured for the GPG backend")
    clean_address(data.get("email"))
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="print MML instead of sending")
    args = parser.parse_args()

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        die(f"stdin is not valid JSON: {exc}")
    if not isinstance(payload, dict):
        die("JSON input must be an object")

    account = payload.get("account", "default")
    if not isinstance(account, str) or not ACCOUNT_RE.fullmatch(account):
        die("invalid account name")
    meta = load_metadata(account)
    sender = clean_address(meta["email"])

    to = clean_address_list(payload.get("to"), "to", required=True)
    cc = clean_address_list(payload.get("cc"), "cc")

    subject = payload.get("subject")
    if not isinstance(subject, str) or not subject or len(subject) > 300:
        die("subject must be a non-empty string up to 300 characters")
    if "\r" in subject or "\n" in subject:
        die("subject may not contain CR/LF")

    body = payload.get("body")
    if not isinstance(body, str) or len(body.encode("utf-8")) > 1024 * 1024:
        die("body must be a UTF-8 string no larger than 1 MiB")
    # MML uses <#...> directives. Reject user body text that could create one.
    if "<#" in body:
        die("body contains reserved MML sequence '<#'; send it as a file or rewrite it")

    mode = payload.get("mode", "encrypt-sign")
    if mode not in MODES:
        die(f"mode must be one of: {', '.join(MODES)}")

    headers = [
        f"From: {sender}",
        f"To: {', '.join(to)}",
    ]
    if cc:
        headers.append(f"Cc: {', '.join(cc)}")
    headers.append(f"Subject: {subject}")

    attrs = MODES[mode]
    mml = "\n".join(headers) + f"\n\n<#part type=text/plain {attrs}>\n{body}\n<#/part>\n"

    if args.dry_run:
        sys.stdout.write(mml)
        return 0

    env = os.environ.copy()
    env.setdefault("RUST_LOG", "warn")
    proc = subprocess.run(
        ["himalaya", "--account", account, "template", "send"],
        input=mml,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        shell=False,
        timeout=120,
    )
    if proc.stdout:
        sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
