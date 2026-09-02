#!/usr/bin/env python3
"""Exit 1 if the <EDIT>...</EDIT> block contents differ between two versions.

<EDIT> tags are human-authored (I15). An agent may add new tags but may not
change or delete the contents of tags that already exist.
"""
from __future__ import annotations

import re
import sys

BLOCK = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)


def blocks(path: str) -> list[str]:
    if path == "-":
        return BLOCK.findall(sys.stdin.read())
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return BLOCK.findall(fh.read())
    except FileNotFoundError:
        return []


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: edit_tags.py <before> <after>", file=sys.stderr)
        return 64
    before, after = blocks(sys.argv[1]), blocks(sys.argv[2])
    kept = [b for b in before if b in after]
    if len(kept) != len(before):
        missing = [b for b in before if b not in after]
        print("EDIT tag content was changed or deleted:", file=sys.stderr)
        for m in missing[:5]:
            print(f"  - <EDIT>{m.strip()[:70]}</EDIT>", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
