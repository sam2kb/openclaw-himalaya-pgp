#!/usr/bin/env python3
"""Fail-closed source patch for the himalaya 1.2.0 publish bug.

The crates.io 1.2.0 source contains
`TomlConfig::from_paths_or_default(config_paths).await?` (7 sites in
src/cli.rs), but pimalaya-tui 0.3.1 -- the version pinned in the crate's
own Cargo.lock -- provides that method synchronously, so the crate cannot
compile against its own lock. This removes the bogus `.await`, which is
exactly what rustc suggests.

Behavior:
- If the buggy pattern is absent, exit 0 and do nothing (upstream may have
  fixed it; a different break would still fail closed at compile time).
- If the pattern is present but cannot be fully removed, exit 1.

Usage: fix-1.2.0-await.py <path-to-cli.rs>
"""
from __future__ import annotations

import pathlib
import sys

BUGGY = "TomlConfig::from_paths_or_default(config_paths).await?"
FIXED = "TomlConfig::from_paths_or_default(config_paths)?"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix-1.2.0-await.py <cli.rs>", file=sys.stderr)
        return 2
    path = pathlib.Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")
    count = text.count(BUGGY)
    if count == 0:
        print("no himalaya .await bug found; nothing to patch")
        return 0
    fixed = text.replace(BUGGY, FIXED)
    if fixed.count(BUGGY) != 0:
        print("ERROR: failed to remove all .await occurrences", file=sys.stderr)
        return 1
    path.write_text(fixed, encoding="utf-8")
    print(
        f"patched {count} bogus .await site(s) in himalaya 1.2.0 cli.rs "
        "(upstream publish bug)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
