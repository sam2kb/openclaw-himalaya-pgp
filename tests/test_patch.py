#!/usr/bin/env python3
"""Tests for patches/fix-1.2.0-await.py (fail-closed upstream bug patch)."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PATCH = REPO_ROOT / "patches" / "fix-1.2.0-await.py"

BUGGY = "TomlConfig::from_paths_or_default(config_paths).await?"
FIXED = "TomlConfig::from_paths_or_default(config_paths)?"


class AwaitPatchTestCase(unittest.TestCase):
    def run_patch(self, content: str):
        with tempfile.TemporaryDirectory() as tmp:
            cli = Path(tmp) / "cli.rs"
            cli.write_text(content, encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(PATCH), str(cli)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return proc, cli.read_text(encoding="utf-8")

    def test_patches_all_sites(self):
        content = "\n".join(f"let config = {BUGGY};" for _ in range(7)) + "\n"
        proc, out = self.run_patch(content)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(BUGGY, out)
        self.assertEqual(out.count(FIXED), 7)

    def test_idempotent_when_already_fixed(self):
        content = f"let config = {FIXED};\n"
        proc, out = self.run_patch(content)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("nothing to patch", proc.stdout)
        self.assertEqual(out, content)

    def test_skips_when_no_bug(self):
        content = "let x = 1;\n"
        proc, out = self.run_patch(content)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("nothing to patch", proc.stdout)
        self.assertEqual(out, content)


if __name__ == "__main__":
    unittest.main()
