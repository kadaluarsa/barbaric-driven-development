#!/usr/bin/env python3
"""Score the spec critic's output for the open GENERATE 05b hop — t57-spec-critic.

    critique.py <root> <hop> <stage> <slice>

The critic only advises. Nothing here judges whether a finding is *right*: it checks that the critique
exists, keeps its shape, was not rewritten after it was committed, and that every finding was *answered*.
A script that graded the critic's opinions would be a new "trust me" (I17).

Prints one PASS/FAIL line per check and `CRITIQUE k/n`; exit 0 iff k == n. Any hop other than
GENERATE 05b prints `CRITIQUE n/a` and exits 0 — the critique gates the spec edge, not the build.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

CAP = 10
SEVERITY = {"high", "medium", "low"}
FINDING = re.compile(r"^\|\s*C\d+\s*\|")
DISPO = re.compile(r"^(fixed|rejected|human)\s+\S")
UNESCAPED_PIPE = re.compile(r"(?<!\\)\|")
# Evidence a human can check without trusting the critic: a `command` or `path:line` in backticks, a bare
# path:line, or the honest UNEVIDENCED. "I think it's wrong" is none of those.
EVIDENCE = re.compile(r"`[^`]+`|[\w./-]+\.\w+:\d+|^UNEVIDENCED$")


def cells(line: str) -> list[str]:
    """Split a table row on unescaped pipes only: `\\|` inside a cell (a shell pipe in evidence) stays put."""
    parts = UNESCAPED_PIPE.split(line.strip())
    if parts and parts[0].strip() == "":
        parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
    return [p.strip() for p in parts]


def section(text: str, heading: str) -> str | None:
    """Body of `## heading` up to the next `## `, or None when the heading is absent."""
    m = re.search(rf"^##\s+{re.escape(heading)}\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
    return m.group(1) if m else None


def findings(text: str) -> tuple[dict[str, list[str]], list[str]]:
    """The critic's rows from `## Brief` and `## Spec` — id -> 4 cells — plus shape problems."""
    rows: dict[str, list[str]] = {}
    bad: list[str] = []
    for head in ("Brief", "Spec"):
        body = section(text, head) or ""
        for line in body.splitlines():
            if not FINDING.match(line):
                continue
            c = cells(line)
            cid = c[0] if c else "?"
            if len(c) != 4:
                bad.append(f"{cid} has {len(c)} cells, not 4 — a literal pipe inside a cell must be written \\|")
                continue
            if cid in rows:
                bad.append(f"{cid} appears twice")
            rows[cid] = c
    return rows, bad


def git(root: str, *args: str) -> tuple[int, str]:
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def main() -> int:
    root, hop, stage, slice_ = (sys.argv[1:5] + ["", "", "", ""])[:4]
    if hop.upper() != "GENERATE" or stage != "05b" or not slice_:
        print(f"CRITIQUE n/a — the critique gates GENERATE 05b only (this hop: {hop or 'NONE'} {stage or '-'})")
        return 0

    spec_rel = f"docs/cascade/05b-{slice_}.md"
    crit_rel = f"docs/cascade/05b-{slice_}-critique.md"
    results: list[tuple[bool, str]] = []

    def check(ok: bool, msg: str) -> None:
        results.append((ok, msg))

    try:
        spec = open(os.path.join(root, spec_rel), encoding="utf-8").read()
    except OSError:
        spec = None
    check(spec is not None, f"spec {spec_rel} exists")
    if spec is not None:
        ba = section(spec, "Before vs after")
        check(ba is not None and ba.count("```mermaid") >= 2,
              "spec has `## Before vs after` with a before and an after mermaid diagram")
        bt = section(spec, "Benefits and trade-offs")
        check(bt is not None and any(l.strip().startswith("|") for l in bt.splitlines()),
              "spec has `## Benefits and trade-offs` with a table")

    try:
        crit = open(os.path.join(root, crit_rel), encoding="utf-8").read()
    except OSError:
        crit = None
    check(crit is not None, f"critique {crit_rel} exists — dispatch the critic and commit its rows")
    if crit is None:
        return report(results)

    check(section(crit, "Brief") is not None and section(crit, "Spec") is not None,
          "critique has `## Brief` (is this the right problem?) and `## Spec`")

    rows, bad = findings(crit)
    none = re.search(r"^NO FINDINGS\b", crit, re.M) is not None
    check(not bad, "every finding row has 4 cells and a unique id" + ("" if not bad else ": " + "; ".join(bad[:3])))
    check((1 <= len(rows) <= CAP) or (not rows and none),
          f"1–{CAP} findings, or an explicit NO FINDINGS line (found {len(rows)})")
    sev = [cid for cid, c in rows.items() if c[1].lower() not in SEVERITY]
    check(not sev, "every severity is high|medium|low" + (f" — not: {', '.join(sev)}" if sev else ""))
    noev = [cid for cid, c in rows.items() if not EVIDENCE.search(c[3])]
    check(not noev, "every finding has evidence (a command, a path:line, or UNEVIDENCED)"
          + (f" — empty: {', '.join(noev)}" if noev else ""))

    answers: dict[str, str] = {}
    for line in (section(crit, "Dispositions") or "").splitlines():
        if FINDING.match(line):
            c = cells(line)
            if len(c) >= 2:
                answers[c[0]] = c[1]
    missing = [cid for cid in rows if not DISPO.match(answers.get(cid, ""))]
    check(not missing, "every finding is answered: fixed <where> | rejected <reason> | human <question>"
          + (f" — unanswered: {', '.join(missing)}" if missing else ""))
    stray = [cid for cid in answers if cid not in rows]
    check(not stray, "no disposition for a finding the critic did not write"
          + (f" — {', '.join(stray)}" if stray else ""))

    # Provenance: the critic's rows as first committed must be the rows now. Edited *or* deleted fails.
    rc_head, _ = git(root, "cat-file", "-e", f"HEAD:{crit_rel}")
    check(rc_head == 0, "the critique is committed at HEAD (a file git does not track proves nothing)")
    rc, sha = git(root, "log", "--diff-filter=A", "--format=%H", "-1", "--", crit_rel)
    sha = sha.strip()
    if rc != 0 or not sha:
        check(False, "the critique's rows are committed before they are answered (no adding commit in "
                     "reachable history — commit the critic's rows first; a shallow clone cannot prove this)")
    else:
        _, first = git(root, "show", f"{sha}:{crit_rel}")
        # The first commit must hold the critic's words alone: rows and answers landing together prove
        # nothing about what the critic said before the author saw it.
        check(section(first, "Dispositions") is None,
              f"the critic's rows were committed ({sha[:7]}) before any answer was added")
        orig, _ = findings(first)
        same = orig == rows
        diff = sorted(set(orig) ^ set(rows)) + sorted(k for k in set(orig) & set(rows) if orig[k] != rows[k])
        check(same, f"critic rows are verbatim since {sha[:7]}"
              + ("" if same else f" — changed or removed: {', '.join(diff)}"))

    human = [cid for cid in rows if answers.get(cid, "").startswith("human")]
    if human:
        print(f"HUMAN   questions for the edge: {', '.join(human)}")
    return report(results)


def report(results: list[tuple[bool, str]]) -> int:
    for ok, msg in results:
        print(f"{'PASS' if ok else 'FAIL'}    {msg}")
    k = sum(1 for ok, _ in results if ok)
    print(f"CRITIQUE {k}/{len(results)}")
    return 0 if k == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
