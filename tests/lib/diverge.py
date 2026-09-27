#!/usr/bin/env python3
"""Score a diverged slice's options for the open GENERATE 05b hop — t58-divergence.

    diverge.py <root> <hop> <stage> <slice>

A brief opts in with `- <slug>: [diverge]` or `[diverge N]` in docs/cascade/05b-briefs.md. Before the spec,
N fresh subagents each write one option (O1 is always the boring baseline); a fresh ranker orders them; the
human names one and signs it by filling the one empty `<EDIT>CHOSEN:</EDIT>` placeholder committed with them.

Nothing here judges which design is better. It checks that the options are complete, distinct in the ways a
script can see, committed verbatim before the choice, and that the choice is the human's: read from HEAD
(an uncommitted pick does not count), in the one placeholder that existed empty when the options landed
(filling existing <EDIT> content is what the pack's guards turn into a signature). The word-overlap check
catches copy-paste only — a paraphrase of the same idea passes it, and the docs say so.

Prints `DIVERGE k/n` (`… — waiting on your choice` before the pick) or `DIVERGE n/a`; exit 0 iff k == n.
"""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import adding_commit, at_head, section   # noqa: E402  (sibling: tests/lib ships as one directory)

FIELDS = ("constraint", "approach", "gives up", "regret when", "failure modes", "falsifier")
OPTION = re.compile(r"^###\s+(O\d+)\b[^\n]*$", re.M)
FIELD = re.compile(r"^(constraint|approach|gives up|regret when|failure modes|falsifier):[ \t]*(.*)$", re.M | re.I)
EDIT = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)
OVERLAP = 0.6


def tag(root: str, slice_: str) -> int | None:
    """N from `- <slug>: [diverge N]`, 3 for a bare `[diverge]`, None when the brief is untagged."""
    try:
        text = open(os.path.join(root, "docs", "cascade", "05b-briefs.md"), encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(rf"^- {re.escape(slice_)}:[ \t]*\[diverge(?:[ \t]+(\d+))?\]", text, re.M)
    if not m:
        return None
    return int(m.group(1)) if m.group(1) else 3


def options(text: str) -> dict[str, dict[str, str]]:
    """O# -> {field: value} for every `### O#` block, in file order."""
    out: dict[str, dict[str, str]] = {}
    marks = list(OPTION.finditer(text))
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = text[m.end():end]
        nxt = re.search(r"^##\s", body, re.M)   # a block ends at the next section too
        body = body[:nxt.start()] if nxt else body
        out[m.group(1)] = {k.lower(): v.strip() for k, v in FIELD.findall(body)}
    return out


def chosen_blocks(text: str) -> list[str]:
    return [b.strip() for b in EDIT.findall(text) if "CHOSEN" in b]


def words(s: str) -> set[str]:
    return set(re.findall(r"\w+", s.lower()))


def overlap(a: str, b: str) -> float:
    A, B = words(a), words(b)
    return len(A & B) / len(A | B) if A | B else 1.0


def main() -> int:
    root, hop, stage, slice_ = (sys.argv[1:5] + ["", "", "", ""])[:4]
    if hop.upper() != "GENERATE" or stage != "05b" or not slice_:
        print(f"DIVERGE n/a — divergence gates GENERATE 05b only (this hop: {hop or 'NONE'} {stage or '-'})")
        return 0
    n = tag(root, slice_)
    if n is None:
        print(f"DIVERGE n/a — the brief for {slice_} is not tagged [diverge]")
        return 0

    cand_rel = f"docs/cascade/05b-{slice_}-candidates.md"
    spec_rel = f"docs/cascade/05b-{slice_}.md"
    results: list[tuple[bool, str]] = []

    def check(ok: bool, msg: str) -> None:
        results.append((ok, msg))

    check(2 <= n <= 5, f"[diverge {n}] asks for 2–5 options")
    head = at_head(root, cand_rel)
    check(head is not None, f"options {cand_rel} are committed at HEAD — an uncommitted file proves nothing")
    if head is None:
        return report(results, waiting=False)

    opts = options(head)
    check(len(opts) >= n, f"at least {n} options (found {len(opts)})")
    blank = [f"{o}:{f}" for o, v in opts.items() for f in FIELDS if not v.get(f)]
    check(not blank, "every option fills " + ", ".join(FIELDS) + (f" — blank: {', '.join(blank[:4])}" if blank else ""))
    check(opts.get("O1", {}).get("constraint", "").lower().startswith("baseline"),
          "O1 is the boring baseline (constraint: baseline)")
    cons = [v.get("constraint", "").strip().lower() for v in opts.values()]
    check(len(set(cons)) == len(cons), "every option works under its own constraint")
    fals = [v.get("falsifier", "").strip().lower() for v in opts.values()]
    check(len(set(fals)) == len(fals), "every option has its own falsifier")
    nocmd = [o for o, v in opts.items() if "`" not in v.get("falsifier", "")]
    check(not nocmd, "every falsifier names a command or experiment in backticks"
          + (f" — not: {', '.join(nocmd)}" if nocmd else ""))
    ids = list(opts)
    close = [f"{a}~{b} ({overlap(opts[a].get('approach', ''), opts[b].get('approach', '')):.2f})"
             for i, a in enumerate(ids) for b in ids[i + 1:]
             if overlap(opts[a].get("approach", ""), opts[b].get("approach", "")) > OVERLAP]
    check(not close, f"no two approaches overlap above {OVERLAP} (a copy-paste catcher, not a novelty test)"
          + (f" — {', '.join(close)}" if close else ""))

    sha, first = adding_commit(root, cand_rel)
    if not sha or first is None:
        check(False, "the options have an adding commit in reachable history (a shallow clone cannot prove this)")
    else:
        check(options(first) == opts, f"options are verbatim since {sha[:7]}")
        fb = chosen_blocks(first)
        check(len(fb) == 1 and re.fullmatch(r"CHOSEN:", fb[0]) is not None,
              f"the options landed ({sha[:7]}) with exactly one empty <EDIT>CHOSEN:</EDIT> placeholder — "
              "filling existing <EDIT> content is what makes the pick a signature")

    hb = chosen_blocks(head)
    m = re.fullmatch(r"CHOSEN:\s*(O\d+)\b.*", hb[0], re.S) if len(hb) == 1 else None
    waiting = len(hb) == 1 and re.fullmatch(r"CHOSEN:", hb[0]) is not None
    check(m is not None and m.group(1) in opts,
          "HEAD holds exactly one CHOSEN block, naming an existing option"
          + (" — waiting on your choice" if waiting else f" (found {len(hb)} block(s))" if len(hb) != 1 else ""))
    pick = m.group(1) if m else ""
    try:
        spec = open(os.path.join(root, spec_rel), encoding="utf-8").read()
    except OSError:
        spec = None
    cd = section(spec, "Chosen design") if spec is not None else None
    check(bool(pick) and cd is not None and re.search(rf"\b{pick}\b", cd) is not None,
          f"spec {spec_rel} has `## Chosen design` naming the chosen option")
    return report(results, waiting=waiting)


def report(results: list[tuple[bool, str]], waiting: bool) -> int:
    for ok, msg in results:
        print(f"{'PASS' if ok else 'FAIL'}    {msg}")
    k = sum(1 for ok, _ in results if ok)
    print(f"DIVERGE {k}/{len(results)}" + (" — waiting on your choice" if waiting and k < len(results) else ""))
    return 0 if k == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
