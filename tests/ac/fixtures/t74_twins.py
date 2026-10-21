#!/usr/bin/env python3
"""Red twins and a fault injection for T74 (tests/enforcement.sh), applied to a fixture copy of .githooks/pre-commit.

    t74_twins.py inject          <hook>   add a failing command right after the ERR trap (the hook must name it)
    t74_twins.py old-extraction  <hook>   restore the pre-t74 id extraction (a new law's twin exits 1 again)
    t74_twins.py skip-no-id      <hook>   skip a file with no D# id instead of listing it (conftest.py lands)

Each exits non-zero when the code it targets has moved, so a twin can never silently patch nothing.
"""
import re
import sys

NEW_EXTRACTION = """  id="$(basename "$f" | grep -oE '(^|[^A-Za-z0-9])D[0-9]+' | head -1 | sed 's/^[^D]*//' || true)\""""
OLD_EXTRACTION = """  id="$(basename "$f" | grep -oE '^test_D[0-9]+' | sed 's/^test_//')\""""


def main() -> int:
    mode, path = sys.argv[1], sys.argv[2]
    s = open(path).read()
    if mode == "inject":
        i = s.find("trap 'echo \"cascade: pre-commit stopped at line")
        if i < 0:
            sys.exit("t74 twin: the ERR trap is not found — update the twin with the code")
        j = s.index("\n", i) + 1
        s = s[:j] + "cat /bdd-no-such-file\n" + s[j:]
    elif mode == "old-extraction":
        if NEW_EXTRACTION not in s:
            sys.exit("t74 twin: the id extraction is not found — update the twin with the code")
        s = s.replace(NEW_EXTRACTION, OLD_EXTRACTION, 1)
    elif mode == "skip-no-id":
        m = re.search(r'  if \[\[ -z "\$id" \]\]; then\n    inv_touched=.*?\n    continue\n  fi\n', s, re.S)
        if not m:
            sys.exit("t74 twin: the no-id branch is not found — update the twin with the code")
        s = s[:m.start()] + '  [[ -n "$id" ]] || continue\n' + s[m.end():]
    else:
        sys.exit(f"t74 twin: unknown mode {mode}")
    open(path, "w").write(s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
