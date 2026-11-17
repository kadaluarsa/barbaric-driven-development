#!/usr/bin/env python3
"""Doc parts (t102): which line ranges of the pipeline doc and CONTROL-LINE.md a hop reads.

The manifest is a table between `<!-- doc-parts:begin -->` and `<!-- doc-parts:end -->` in
docs/cascade/product-e2e-gre-pipeline.md. Each row is `| <hop class> | <part>; <part>; … |`. A part is
`<file>#<heading>` (a Markdown heading, to the next heading of the same or a higher level; fenced lines are never
headings) or `<file>@<label>` (a line in the conductor's code block that starts with the label, to the next label
line or the closing fence). `<file>` is `gre` or `cl`.

usage: doc_parts.py <root> [--hop H --stage S | --check | --measure]
"""
from __future__ import annotations

import os
import re
import sys

FILES = {"gre": os.path.join("docs", "cascade", "product-e2e-gre-pipeline.md"), "cl": "CONTROL-LINE.md"}
LABELS = ["You are running", "INVARIANTS", "PRESERVE protocol", "ADD protocol", "COMMAND BINDING:", "Hard rules:",
          "Spec critic", "Switch review", "Divergence", "Current hop:"]
CLASSES = ["ALL", "GENERATE 05b", "GENERATE", "EXECUTE-BUILD", "EXECUTE-DESIGN", "EXECUTE-AUDIT", "EXECUTE-PRR"]
DESIGN, AUDIT, PRR = {"01", "02", "03", "04"}, {"10"}, {"11"}
BEGIN, END = "<!-- doc-parts:begin -->", "<!-- doc-parts:end -->"
BASELINE = ["docs/cascade/hop-state.md", "docs/cascade/envelope.md", FILES["gre"], "docs/cascade/product-e2e-cascade.md",
            "CONTROL-LINE.md"]
FIXED = [BASELINE[0], BASELINE[1], BASELINE[3]]


class Red(Exception):
    pass


def hop_class(hop: str, stage: str) -> str | None:
    """seam.py's hop_class, with GENERATE split by stage."""
    hop, st = hop.upper(), (stage.split()[0] if stage else "")
    if hop == "GENERATE":
        return "GENERATE 05b" if st == "05b" else "GENERATE"
    if hop == "EXECUTE":
        if st in DESIGN:
            return "EXECUTE-DESIGN"
        if st in AUDIT:
            return "EXECUTE-AUDIT"
        if st in PRR:
            return "EXECUTE-PRR"
        return "EXECUTE-BUILD"
    return None


def _lines(root: str, key: str) -> list[str]:
    with open(os.path.join(root, FILES[key]), encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def manifest(root: str) -> dict[str, list[str]] | None:
    """{hop class: [part, …]} from the manifest block, or None when the block is missing."""
    try:
        text = "\n".join(_lines(root, "gre"))
    except OSError:
        return None
    m = re.search(re.escape(BEGIN) + r"(.*?)" + re.escape(END), text, re.S)
    if not m:
        return None
    rows: dict[str, list[str]] = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip("|"))]
        if len(cells) < 2 or set(cells[0]) <= set("-: ") or cells[0].lower() == "hop class":
            continue
        cls = cells[0].strip("`")
        rows[cls] = [p.strip().strip("`").replace("\\|", "|") for p in cells[1].split(";") if p.strip()]
    return rows


def _code_block(lines: list[str]) -> tuple[int, int]:
    """(first, last) 0-based indexes inside the fence that holds the `INVARIANTS` label."""
    fence = None
    for i, line in enumerate(lines):
        if line.startswith("```"):
            if fence is None:
                fence = i
            else:
                if any(lines[j].startswith("INVARIANTS") for j in range(fence + 1, i)):
                    return fence + 1, i - 1
                fence = None
    raise Red("no conductor code block holding the INVARIANTS label")


def resolve(root: str, part: str) -> tuple[str, int, int]:
    """(path, start, end), 1-based and inclusive, or Red with the reason."""
    m = re.match(r"^(gre|cl)([#@])(.+)$", part)
    if not m:
        raise Red("not <gre|cl>#<heading> or <gre|cl>@<label>")
    key, kind, name = m.groups()
    try:
        lines = _lines(root, key)
    except OSError as exc:
        raise Red(f"cannot read {FILES[key]} ({exc.__class__.__name__})")
    if kind == "@":
        if name not in LABELS:
            raise Red(f"unknown label (labels: {', '.join(LABELS)})")
        lo, hi = _code_block(lines)
        hits = [i for i in range(lo, hi + 1) if lines[i].startswith(name)]
        if len(hits) != 1:
            raise Red(f"label matches {len(hits)} lines in the conductor block (need 1)")
        s = hits[0]
        e = hi
        for j in range(s + 1, hi + 1):
            if any(lines[j].startswith(lab) for lab in LABELS if lab != name):
                e = j - 1
                break
    else:
        heads, fence = [], False
        for i, line in enumerate(lines):
            if line.startswith("```"):
                fence = not fence
                continue
            hm = re.match(r"^(#+)\s+(.*?)\s*$", line)
            if hm and not fence:
                heads.append((i, len(hm.group(1)), hm.group(2)))
        hits = [h for h in heads if h[2] == name]
        if len(hits) != 1:
            raise Red(f"heading matches {len(hits)} lines (need 1)")
        s, lvl, _ = hits[0]
        e = len(lines) - 1
        for i, l2, _ in heads:
            if i > s and l2 <= lvl:
                e = i - 1
                break
    while e > s and not lines[e].strip():   # trailing blank lines are not part of the text
        e -= 1
    if e < s or not any(lines[k].strip() for k in range(s, e + 1)):
        raise Red("empty range")
    return FILES[key], s + 1, e + 1


def parts(root: str, hop: str, stage: str) -> list[tuple[str, int, int, str]]:
    """The parts a hop reads: ALL first, then the class row, each in manifest order. [] when there is none."""
    cls = hop_class(hop, stage)
    rows = manifest(root)
    if cls is None or rows is None:
        return []
    out, seen = [], set()
    for part in rows.get("ALL", []) + rows.get(cls, []):
        if part in seen:
            continue
        seen.add(part)
        try:
            p, a, b = resolve(root, part)
        except Red:
            continue
        out.append((p, a, b, part))
    return out


def size(root: str, rows: list[tuple[str, int, int, str]]) -> int:
    """Bytes of the distinct lines the parts cover."""
    seen, total, cache = set(), 0, {}
    for p, a, b, _ in rows:
        if p not in cache:
            with open(os.path.join(root, p), "rb") as fh:
                cache[p] = fh.read().split(b"\n")
        for i in range(a, b + 1):
            if (p, i) not in seen:
                seen.add((p, i))
                total += len(cache[p][i - 1]) + 1
    return total


def check(root: str) -> int:
    rows = manifest(root)
    if rows is None:
        print(f"DOC PARTS red: no {BEGIN.replace('begin', 'begin/end')} block")
        return 1
    bad, n = 0, 0
    for cls, ps in rows.items():
        if cls not in CLASSES:
            print(f"DOC PARTS red: row '{cls}' — unknown hop class (classes: {', '.join(CLASSES)})")
            bad = 1
        for part in ps:
            n += 1
            try:
                resolve(root, part)
            except Red as exc:
                print(f"DOC PARTS red: {part} — {exc}")
                bad = 1
    try:
        p, a, b = resolve(root, "gre@INVARIANTS")
        lines = _lines(root, "gre")[a - 1:b]
        for i in range(1, 19):
            if not any(x.startswith(f"I{i} ") for x in lines):
                print(f"DOC PARTS red: gre@INVARIANTS — I{i} does not start a line in {p}:{a}-{b}")
                bad = 1
    except Red as exc:
        print(f"DOC PARTS red: gre@INVARIANTS — {exc}")
        bad = 1
    if not bad:
        print(f"DOC PARTS ok: {len(rows)} rows, {n} parts")
    return bad


def measure(root: str) -> int:
    if manifest(root) is None:
        print(f"DOC PARTS red: no {BEGIN.replace('begin', 'begin/end')} block")
        return 1
    fsize = lambda p: os.path.getsize(os.path.join(root, p)) if os.path.exists(os.path.join(root, p)) else 0
    base = sum(fsize(p) for p in BASELINE)
    fixed = sum(fsize(p) for p in FIXED)
    probe = {"GENERATE 05b": ("GENERATE", "05b"), "GENERATE": ("GENERATE", "03"), "EXECUTE-BUILD": ("EXECUTE", "05b"),
             "EXECUTE-DESIGN": ("EXECUTE", "03"), "EXECUTE-AUDIT": ("EXECUTE", "10"), "EXECUTE-PRR": ("EXECUTE", "11")}
    bad = 0
    for cls, (h, s) in probe.items():
        after = fixed + size(root, parts(root, h, s))
        r = after / base if base else 1.0
        flag = "ok " if r <= 0.5 else "RED"
        bad |= r > 0.5
        print(f"{flag} {cls:<15} {after:>7} / {base} bytes = {r:.0%}")
    return int(bad)


def current(root: str) -> tuple[str, str]:
    path = os.path.join(root, "docs", "cascade", "hop-state.md")
    if not os.path.exists(path):
        path = os.path.join(root, "docs", "cascade", "envelope.md")
    hop = stage = ""
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            if line.startswith("CURRENT_HOP:"):
                hop = line.split(":", 1)[1].strip()
            elif line.startswith("CURRENT_STAGE:"):
                stage = line.split(":", 1)[1].strip()
    except OSError:
        pass
    return hop, stage


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 64
    root, args = argv[0], argv[1:]
    if args[:1] == ["--check"]:
        return check(root)
    if args[:1] == ["--measure"]:
        return measure(root)
    if args[:1] == ["--hop"]:
        if len(args) != 4 or args[2] != "--stage":
            print("usage: doc_parts.sh --hop <GENERATE|EXECUTE> --stage <stage>", file=sys.stderr)
            return 64
        hop, stage = args[1], args[3]
    elif not args:
        hop, stage = current(root)
        if hop_class(hop, stage) is None:
            print("no hop running")
            return 0
    else:
        print("usage: doc_parts.sh [--hop H --stage S | --check | --measure]", file=sys.stderr)
        return 64
    rows = parts(root, hop, stage)
    for p, a, b, name in rows:
        print(f"{p}:{a}-{b}  {size(root, [(p, a, b, name)])}  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
