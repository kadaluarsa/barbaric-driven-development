#!/usr/bin/env python3
"""Split the nightly full proof into parts by module (t69).

    nightly_plan.py <root> <envelope> --parts N --out <plan.tsv>

Reads every DECLARED law — the same list, in the same order, that tests/dsharp_strength.sh parses into its index
(`laws.py --declared --shards`), UNPROVEN laws included so the part that owns one scores it as a single run would.
Groups each law by its Gradle module (`affected.module_of(check, root)`; `-` for a law with no module), puts every
id in DSHARP_SERIAL into one group `serial` (those laws share state, so they stay together and in declared order),
and packs whole groups into at most N parts: largest group first (ties by name), each into the part with the fewest
laws (ties by lowest part). A part holds more than one group only when there are more groups than parts.

Writes `<declared index>\\t<id>\\t<part>` per law to <plan.tsv> and prints the matrix `{"part":[0,…]}`. There is
always at least one part, so zero laws give one empty part (GitHub refuses an empty matrix).

The plan only decides WHERE a law is scored. `dsharp_strength.sh --join` refuses any set of parts that does not
hold every declared law exactly once, in the part this plan gave it — docs/cascade/05b-t69-gradle-tuning.md §5.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from affected import module_of   # noqa: E402  (sibling: tests/lib ships as one directory)

HERE = os.path.dirname(os.path.abspath(__file__))


def declared(root: str, envelope: str) -> list[tuple[str, str]]:
    """(id, check) per declared law, indexed exactly as dsharp_strength.sh indexes them."""
    shards = os.path.join(root, "docs", "cascade", "laws")
    r = subprocess.run([sys.executable, "-B", os.path.join(HERE, "laws.py"), envelope, "--declared",
                        "--shards", shards], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"FATAL the laws cannot be read: {r.stderr.strip().splitlines()[-1:] or ['?']}")
    out = []
    for line in r.stdout.split("\n"):
        f = line.split("|")
        lid = f[0].strip() if f else ""
        if not lid:
            continue                                      # dsharp skips a record with no id the same way
        check = f[2].strip() if len(f) > 2 else ""
        out.append((lid, "" if check in ("TODO", "none") else check))
    return out


def plan(root: str, laws: list[tuple[str, str]], parts: int, serial: set[str]) -> list[int]:
    groups: dict[str, list[int]] = {}
    for i, (lid, check) in enumerate(laws):
        if lid in serial:
            g = "serial"
        else:
            m = module_of(check, root)[0] if check else None
            g = m or "-"
        groups.setdefault(g, []).append(i)
    n = max(1, min(parts, len(groups)))
    load = [0] * n
    where = [0] * len(laws)
    for name, members in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        k = min(range(n), key=lambda j: (load[j], j))
        load[k] += len(members)
        for i in members:
            where[i] = k
    return where


def main() -> int:
    a = sys.argv[1:]
    if len(a) != 6 or a[2] != "--parts" or not a[3].isdigit() or int(a[3]) < 1 or a[4] != "--out":
        print("usage: nightly_plan.py <root> <envelope> --parts N --out <plan.tsv>", file=sys.stderr)
        return 64
    root, envelope, parts, out = a[0], a[1], int(a[3]), a[5]
    laws = declared(root, envelope)
    serial = set((os.environ.get("DSHARP_SERIAL") or "").split())
    where = plan(root, laws, parts, serial)
    with open(out, "w", encoding="utf-8") as fh:
        for i, (lid, _) in enumerate(laws):
            fh.write(f"{i}\t{lid}\t{where[i]}\n")
    n = max(where) + 1 if where else 1
    print(json.dumps({"part": list(range(n))}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
