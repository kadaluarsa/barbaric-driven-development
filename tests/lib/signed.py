#!/usr/bin/env python3
"""Exit 0 if REGEX matches inside an <EDIT>...</EDIT> block of FILE — i.e. a human wrote it.

Hop hooks reject agent changes to <EDIT> content, so text inside a tag is a human signature.
usage: signed.py FILE REGEX
"""
import re
import sys

BLOCK = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)


def main() -> int:
    if len(sys.argv) != 3:
        return 64
    try:
        text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    except OSError:
        return 1
    pat = re.compile(sys.argv[2])
    return 0 if any(pat.search(b) for b in BLOCK.findall(text)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
