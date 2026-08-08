#!/usr/bin/env python3
"""Black-box tests for rotate-credential.sh using fake `pass`/`bao` shims.

The shims record their invocations to log files so the tests can assert the
exact commands rotate-credential.sh issues for each credential backend.
No real password store, OpenBao server, or personal data is touched.
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "rotate-credential.sh"

FAKE_PASS = """#!/bin/bash
# Records argv to FAKE_PASS_LOG; consumes stdin on insert (like real pass).
set -euo pipefail
printf 'pass %s\\n' "$*" >> "${FAKE_PASS_LOG:?}"
if [[ "${1:-}" == "insert" ]]; then
  cat >/dev/null
fi
exit 0
"""

FAKE_BAO = """#!/bin/bash
# Records argv to FAKE_BAO_LOG.
set -euo pipefail
printf 'bao %s\\n' "$*" >> "${FAKE_BAO_LOG:?}"
exit 0
"""


class RotateTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name) / "home"
        self.home.mkdir()
        self.meta_dir = self.home / ".config" / "himalaya" / "openclaw-pgp"
        self.meta_dir.mkdir(parents=True)

        bindir = Path(self._tmp.name) / "bin"
        bindir.mkdir()
        for name, body in (("pass", FAKE_PASS), ("bao", FAKE_BAO)):
            p = bindir / name
            p.write_text(body)
            p.chmod(0o755)

        self.pass_log = Path(self._tmp.name) / "pass.log"
        self.bao_log = Path(self._tmp.name) / "bao.log"

        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["FAKE_PASS_LOG"] = str(self.pass_log)
        self.env["FAKE_BAO_LOG"] = str(self.bao_log)
        # Fake shims first, then the real PATH (needed for `python3` inside
        # rotate-credential.sh to read account metadata).
        self.env["PATH"] = f"{bindir}:{self.env['PATH']}"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_meta(self, cred_source: str, cred_path: str) -> None:
        (self.meta_dir / "default.json").write_text(
            json.dumps({
                "account": "default",
                "email": "me@example.com",
                "pgp_fingerprint": "ABCDEF1234567890ABCDEF1234567890ABCDEF12",
                "backend": "gpg",
                "credential_source": cred_source,
                "credential_path": cred_path,
            }),
            encoding="utf-8",
        )

    def run_rotate(self, args: list[str], stdin: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            input=stdin,
            capture_output=True,
            text=True,
            env=self.env,
            timeout=30,
        )

    def test_pass_imap_rotation(self):
        self.write_meta("pass", "openclaw-mail/default")
        proc = self.run_rotate(["default", "imap"], "newpass\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        log = self.pass_log.read_text()
        self.assertIn("pass insert -m -f openclaw-mail/default/imap", log)
        self.assertFalse(self.bao_log.exists())

    def test_openbao_imap_rotation(self):
        self.write_meta("openbao", "secret/mail/default")
        proc = self.run_rotate(["default", "imap"], "newpass\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        log = self.bao_log.read_text()
        self.assertIn("bao kv put secret/mail/default/imap password=newpass", log)
        self.assertFalse(self.pass_log.exists())

    def test_pass_both_rotation(self):
        self.write_meta("pass", "openclaw-mail/default")
        proc = self.run_rotate(["default", "both"], "p1\np2\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        log = self.pass_log.read_text()
        self.assertIn("pass insert -m -f openclaw-mail/default/imap", log)
        self.assertIn("pass insert -m -f openclaw-mail/default/smtp", log)

    def test_missing_metadata_fails(self):
        proc = self.run_rotate(["default", "imap"], "x\n")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("metadata not found", proc.stderr)

    def test_invalid_account_fails(self):
        proc = self.run_rotate(["../etc", "imap"], "x\n")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("invalid account name", proc.stderr)

    def test_invalid_target_fails(self):
        self.write_meta("pass", "openclaw-mail/default")
        proc = self.run_rotate(["default", "bogus"], "x\n")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("target must be imap, smtp, or both", proc.stderr)

    def test_unsupported_source_fails(self):
        self.write_meta("weird", "whatever/path")
        proc = self.run_rotate(["default", "imap"], "x\n")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unsupported credential_source", proc.stderr)


if __name__ == "__main__":
    unittest.main()
