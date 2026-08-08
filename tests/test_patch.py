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

CLI_BUGGY = "TomlConfig::from_paths_or_default(config_paths).await?"
CLI_FIXED = "TomlConfig::from_paths_or_default(config_paths)?"
MAIN_BUGGIES = [
    "TomlConfig::from_default_paths().await?",
    "TomlConfig::from_paths_or_default(cli.config_paths.as_ref()).await?",
]
MAIN_FIXED = [
    "TomlConfig::from_default_paths()?",
    "TomlConfig::from_paths_or_default(cli.config_paths.as_ref())?",
]


class AwaitPatchTestCase(unittest.TestCase):
    def run_patch(self, files: dict[str, str]):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            for name, content in files.items():
                (src / name).write_text(content, encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(PATCH), str(src)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return proc, {name: (src / name).read_text(encoding="utf-8") for name in files}

    def test_patches_cli_and_main(self):
        cli = "\n".join(f"let config = {CLI_BUGGY};" for _ in range(7)) + "\n"
        main = "\n".join(f"let config = {b};" for b in MAIN_BUGGIES) + "\n"
        proc, out = self.run_patch({"cli.rs": cli, "main.rs": main})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(CLI_BUGGY, out["cli.rs"])
        self.assertEqual(out["cli.rs"].count(CLI_FIXED), 7)
        for buggy in MAIN_BUGGIES:
            self.assertNotIn(buggy, out["main.rs"])
        for fixed in MAIN_FIXED:
            self.assertIn(fixed, out["main.rs"])

    def test_idempotent_when_already_fixed(self):
        files = {
            "cli.rs": f"let config = {CLI_FIXED};\n",
            "main.rs": "\n".join(f"let config = {f};" for f in MAIN_FIXED) + "\n",
        }
        proc, out = self.run_patch(files)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("nothing to patch", proc.stdout)
        self.assertEqual(out["cli.rs"], files["cli.rs"])
        self.assertEqual(out["main.rs"], files["main.rs"])

    def test_skips_when_no_bug(self):
        files = {"cli.rs": "let x = 1;\n", "main.rs": "fn main() {}\n"}
        proc, out = self.run_patch(files)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("nothing to patch", proc.stdout)
        self.assertEqual(out["cli.rs"], files["cli.rs"])
        self.assertEqual(out["main.rs"], files["main.rs"])


if __name__ == "__main__":
    unittest.main()
