#!/usr/bin/env python3
"""Fail-closed source patch for the himalaya 1.2.0 publish bug.

The crates.io 1.2.0 source awaits `TomlConfig::from_*` config-loading calls
(9 sites across src/cli.rs and src/main.rs), but pimalaya-tui 0.3.1 -- the
version pinned in the crate's own Cargo.lock -- provides those methods
synchronously, so the crate cannot compile against its own lock. This
removes the bogus `.await`, which is exactly what rustc suggests.

Behavior:
- If none of the buggy patterns are present, exit 0 and do nothing (upstream
  may have fixed it; a different break would still fail closed at compile).
- If a pattern is present but remains after patching, exit 1.

Usage: fix-1.2.0-await.py <crate-src-dir>
"""
from __future__ import annotations

import pathlib
import sys

# (buggy, fixed) pairs. Keep this list in sync with the actual upstream sites.
PATCHES = [
    (
        "TomlConfig::from_paths_or_default(config_paths).await?",
        "TomlConfig::from_paths_or_default(config_paths)?",
    ),
    (
        "TomlConfig::from_default_paths().await?",
        "TomlConfig::from_default_paths()?",
    ),
    (
        "TomlConfig::from_paths_or_default(cli.config_paths.as_ref()).await?",
        "TomlConfig::from_paths_or_default(cli.config_paths.as_ref())?",
    ),
]

FILES = ("cli.rs", "main.rs")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix-1.2.0-await.py <crate-src-dir>", file=sys.stderr)
        return 2
    src_dir = pathlib.Path(sys.argv[1])
    total = 0
    for name in FILES:
        path = src_dir / name
        if not path.is_file():
            print(f"ERROR: expected source file missing: {path}", file=sys.stderr)
            return 1
        text = path.read_text(encoding="utf-8")
        for buggy, fixed in PATCHES:
            count = text.count(buggy)
            if count == 0:
                continue
            text = text.replace(buggy, fixed)
            total += count
        path.write_text(text, encoding="utf-8")
    if total == 0:
        print("no himalaya .await bugs found; nothing to patch")
        return 0
    # Fail-closed: confirm no buggy pattern remains in any file.
    for name in FILES:
        text = (src_dir / name).read_text(encoding="utf-8")
        for buggy, _ in PATCHES:
            if buggy in text:
                print(f"ERROR: buggy pattern still present in {name}", file=sys.stderr)
                return 1
    print(
        f"patched {total} bogus .await site(s) in himalaya 1.2.0 "
        "(upstream publish bug)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
