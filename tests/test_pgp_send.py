#!/usr/bin/env python3
"""Black-box tests for skill/himalaya/scripts/pgp_send.py.

Runs the real script through its stdin/JSON interface using a fake HOME and a
fake `gpg` shim on PATH, so no real keys, credentials, or personal data are
ever touched. All addresses use example.com domains.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "skill" / "himalaya" / "scripts" / "pgp_send.py"

VALID_FP = "ABCDEF1234567890ABCDEF1234567890ABCDEF12"

FAKE_GPG = """#!/bin/bash
# Minimal gpg shim for tests. No real keyring is ever touched.
# Absolute shebang: the test PATH contains only the fake bin dir.
set -euo pipefail
if [[ "${1:-}" == "--batch" ]]; then
  shift
fi
case "${1:-}" in
  --list-secret-keys)
    case "${2:-}" in
      ABCDEF1234567890ABCDEF1234567890ABCDEF12) exit 0 ;;
      *) exit 2 ;;
    esac
    ;;
  --list-keys)
    case "${2:-}" in
      alice@example.com|bob@example.com|me@example.com) exit 0 ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 0 ;;
esac
"""


class PgpSendTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name) / "home"
        self.home.mkdir()
        self.meta_dir = self.home / ".config" / "himalaya" / "openclaw-pgp"
        self.meta_dir.mkdir(parents=True)
        self.write_meta("default", "me@example.com", VALID_FP)

        bindir = Path(self._tmp.name) / "bin"
        bindir.mkdir()
        gpg = bindir / "gpg"
        gpg.write_text(FAKE_GPG)
        gpg.chmod(0o755)

        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        # Only the fake bin dir on PATH: deterministic lookup for `gpg`, and
        # `himalaya` is deliberately absent so send-path tests fail cleanly.
        self.env["PATH"] = str(bindir)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_meta(self, account: str, email: str, fp: str, backend: str = "gpg") -> None:
        (self.meta_dir / f"{account}.json").write_text(
            json.dumps(
                {"account": account, "email": email, "pgp_fingerprint": fp, "backend": backend}
            ),
            encoding="utf-8",
        )

    def run_script(self, payload: dict, dry_run: bool = True) -> subprocess.CompletedProcess:
        args = [sys.executable, str(SCRIPT)]
        if dry_run:
            args.append("--dry-run")
        return subprocess.run(
            args,
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=self.env,
            timeout=60,
        )

    def assert_ok(self, proc: subprocess.CompletedProcess, mml: str = "") -> None:
        self.assertEqual(proc.returncode, 0, proc.stderr)
        if mml:
            self.assertIn(mml, proc.stdout)

    def assert_rejected(self, proc: subprocess.CompletedProcess, needle: str) -> None:
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertIn(needle, proc.stderr)

    # --- happy paths ---

    def test_valid_encrypt_sign_dry_run(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "PGP test", "body": "This is protected.",
        })
        self.assert_ok(proc, "<#part type=text/plain encrypt=gpg sign=gpg>")
        self.assertIn("From: me@example.com", proc.stdout)
        self.assertIn("To: alice@example.com", proc.stdout)
        self.assertIn("Subject: PGP test", proc.stdout)

    def test_sign_only_mml(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "b", "mode": "sign-only",
        })
        self.assert_ok(proc, "sign=gpg")
        self.assertNotIn("encrypt=gpg", proc.stdout)

    def test_encrypt_only_mml(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "b", "mode": "encrypt-only",
        })
        self.assert_ok(proc, "encrypt=gpg")
        self.assertNotIn("sign=gpg", proc.stdout)

    def test_cc_included(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"], "cc": ["bob@example.com"],
            "subject": "s", "body": "b",
        })
        self.assert_ok(proc)
        self.assertIn("Cc: bob@example.com", proc.stdout)

    def test_sign_only_skips_recipient_key_check(self):
        proc = self.run_script({
            "account": "default", "to": ["unknown@example.com"],
            "subject": "s", "body": "b", "mode": "sign-only",
        })
        self.assert_ok(proc)

    # --- input validation rejections ---

    def test_mml_injection_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "hi <#part type=text/plain> evil",
        })
        self.assert_rejected(proc, "reserved MML")

    def test_part_terminator_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "bye <#/part>",
        })
        self.assert_rejected(proc, "reserved MML")

    def test_subject_newline_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "a\nb", "body": "x",
        })
        self.assert_rejected(proc, "control characters")

    def test_subject_escape_char_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "a\x1bb", "body": "x",
        })
        self.assert_rejected(proc, "control characters")

    def test_subject_too_long_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "x" * 301, "body": "x",
        })
        self.assert_rejected(proc, "up to 300")

    def test_body_too_large_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x" * (1024 * 1024 + 1),
        })
        self.assert_rejected(proc, "1 MiB")

    def test_shell_metachar_email_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["$(id)@evil.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "unsafe or unsupported email address")

    def test_cc_header_injection_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "cc": ["c@d.com\nBcc: x@y.com"], "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "unsafe or unsupported email address")

    def test_empty_to_rejected(self):
        proc = self.run_script({
            "account": "default", "to": [], "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "at least one recipient")

    def test_bad_mode_rejected(self):
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x", "mode": "shell",
        })
        self.assert_rejected(proc, "mode must be one of")

    def test_path_traversal_account_rejected(self):
        proc = self.run_script({
            "account": "../etc", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "invalid account name")

    # --- key pre-flight checks ---

    def test_missing_recipient_key_fails(self):
        proc = self.run_script({
            "account": "default", "to": ["unknown@example.com"],
            "subject": "s", "body": "x", "mode": "encrypt-only",
        })
        self.assert_rejected(proc, "no public key found")

    def test_missing_signing_key_fails(self):
        self.write_meta("default", "me@example.com", "DEADBEEF" * 5)
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "signing secret key")

    # --- account metadata handling ---

    def test_metadata_symlink_rejected(self):
        real = self.meta_dir / "real.json"
        real.write_text(
            json.dumps({
                "account": "default", "email": "me@example.com",
                "pgp_fingerprint": VALID_FP, "backend": "gpg",
            }),
            encoding="utf-8",
        )
        (self.meta_dir / "default.json").unlink()
        os.symlink(real, self.meta_dir / "default.json")
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "must not be a symlink")

    def test_metadata_account_mismatch_rejected(self):
        (self.meta_dir / "default.json").write_text(
            json.dumps({
                "account": "other", "email": "me@example.com",
                "pgp_fingerprint": VALID_FP, "backend": "gpg",
            }),
            encoding="utf-8",
        )
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "account metadata mismatch")

    def test_non_gpg_backend_rejected(self):
        self.write_meta("default", "me@example.com", VALID_FP, backend="shell")
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "not configured for the GPG backend")

    def test_metadata_with_credential_fields_ok(self):
        (self.meta_dir / "default.json").write_text(
            json.dumps({
                "account": "default", "email": "me@example.com",
                "pgp_fingerprint": VALID_FP, "backend": "gpg",
                "credential_source": "openbao", "credential_path": "secret/mail/default",
            }),
            encoding="utf-8",
        )
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_ok(proc)

    def test_unsupported_credential_source_rejected(self):
        (self.meta_dir / "default.json").write_text(
            json.dumps({
                "account": "default", "email": "me@example.com",
                "pgp_fingerprint": VALID_FP, "backend": "gpg",
                "credential_source": "weird", "credential_path": "x",
            }),
            encoding="utf-8",
        )
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "unsupported credential_source")

    def test_missing_metadata_rejected(self):
        (self.meta_dir / "default.json").unlink()
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        })
        self.assert_rejected(proc, "account metadata not found")

    # --- send path ---

    def test_missing_himalaya_fails_cleanly(self):
        # No `himalaya` on the fake PATH: the send path must fail with a clean
        # message, not a traceback.
        proc = self.run_script({
            "account": "default", "to": ["alice@example.com"],
            "subject": "s", "body": "x",
        }, dry_run=False)
        self.assert_rejected(proc, "himalaya binary not found")


if __name__ == "__main__":
    unittest.main()
