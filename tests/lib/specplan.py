#!/usr/bin/env python3
"""The spec and plan check (t94): a new spec and plan meet the signed language rules; a 05b one also holds the contract.

    specplan.py <root>            read the working tree
    specplan.py <root> --index    read every file from staged text, for .githooks/pre-commit

Prints WARN/PASS/FAIL lines and `SPECPLAN k/n`; exit 0 iff k == n. `SPECPLAN n/a` exits 0 when no hop is running, the
slice has no spec on a stage other than 05b, the repo never held the rules, a signed off is in force, or the spec
predates the rules. A rules file that left the repo after it landed fails: a missing file cannot turn this off.

This checks what a script can detect. It does not claim ASD-STE100 conformance, and the pack ships no dictionary.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

RULES = "docs/cascade/specplan-rules.md"
HOPSTATE = "docs/cascade/hop-state.md"
ENVELOPE = "docs/cascade/envelope.md"
LIMIT_PROCEDURE = "SPECPLAN_MAX_WORDS_PROCEDURE"
LIMIT_DESCRIPTIVE = "SPECPLAN_MAX_WORDS_DESCRIPTIVE"
BANNED = "SPECPLAN_BANNED"
FIELDS = ("allowed", "prohibited", "procedure", "acceptance")
PRIORITIES = ("MUST", "SHOULD", "MAY")
NO_ID = ("", "—", "-")

EDIT = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)
FENCE = re.compile(r"^(```|~~~)[^\n]*\n.*?^\1[^\n]*$", re.M | re.S)
COMMENT = re.compile(r"<!--.*?-->", re.S)
OFF = re.compile(r"^\s*-\s*SPECPLAN:\s*off\b", re.M)
ITEM = re.compile(r"^\s*(\d+\.|[-*])\s+(\S.*)$")
LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
CODE = re.compile(r"`[^`]*`")
SENTENCE_END = re.compile(r"(?<=[.!?])\s+")
CELL = re.compile(r"(?<!\\)\|")
SEPARATOR = re.compile(r"^\s*\|[\s:|-]*\|\s*$")
# A regex cannot detect passive voice with enough precision to block a commit, so this only warns.
PASSIVE = re.compile(r"\b(?:is|are|was|were|be|been|being)\s+\w+ed\b", re.I)


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def parse_rules(text: str) -> tuple[dict, list[str]]:
    """Limits only from <EDIT>. A missing, invalid or duplicate limit is a failure, never a default."""
    body = "\n".join(EDIT.findall(text))
    rules: dict = {}
    bad: list[str] = []
    for key in (LIMIT_PROCEDURE, LIMIT_DESCRIPTIVE):
        found = re.findall(rf"^{key}:[ \t]*(.*?)[ \t]*$", body, re.M)
        if len(found) != 1 or not found[0].isdigit() or int(found[0]) < 1:
            bad.append(f"{key} must appear once inside <EDIT>, as a positive number (found {found or 'none'})")
        else:
            rules[key] = int(found[0])
    terms = re.findall(rf"^{BANNED}:[ \t]*(.*)$", body, re.M)
    if len(terms) > 1:
        bad.append(f"{BANNED} appears more than once inside <EDIT>")
    rules[BANNED] = [t.strip() for t in terms[0].split("|") if t.strip()] if terms else []
    return rules, bad


def section(text: str, head: str, level: int) -> str | None:
    pattern = rf"^{'#' * level} {re.escape(head)}[ \t]*$(.*?)(?=^#{{1,{level}}} |\Z)"
    m = re.search(pattern, text, re.M | re.S)
    return m.group(1) if m else None


def table_rows(body: str | None) -> list[list[str]]:
    rows = []
    for line in (body or "").splitlines():
        if not line.strip().startswith("|") or SEPARATOR.match(line):
            continue
        cells = [c.strip() for c in CELL.split(line.strip().strip("|"))]
        if cells and cells[0] != "ID":
            rows.append(cells)
    return rows


def check_contract(text: str) -> list[str]:
    body = section(FENCE.sub("", text), "Execution contract", 2)
    if body is None:
        return ["spec has no `## Execution contract` section"]
    fails, items = [], {}
    for name in FIELDS:
        items[name] = [ITEM.match(l) for l in (section(body, name, 3) or "").splitlines() if ITEM.match(l)]
        if not items[name]:
            fails.append(f"contract field {name} is missing or empty")
    if not all(m.group(1)[0].isdigit() for m in items["procedure"]):
        fails.append("contract field procedure must be a numbered list")
    for m in items["acceptance"]:
        if "`" not in m.group(2) and not m.group(2).startswith("manual:"):
            fails.append(f"contract field acceptance has a row with no command or manual: check: {m.group(2)[:50]}")
    return fails


def blocks(text: str) -> list[tuple[str, bool]]:
    """(text, is_procedure) per paragraph or list item; a wrapped line belongs to the block it continues."""
    text = COMMENT.sub("", FENCE.sub("", text))
    out: list[list] = []
    current = None
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith(("#", "|", ">")):
            current = None
            continue
        m = ITEM.match(line)
        if m:
            current = [m.group(2), m.group(1)[0].isdigit()]
            out.append(current)
        elif current is not None:
            current[0] += " " + s
        else:
            current = [s, False]
            out.append(current)
    for row in table_rows(section(text, "Requirements", 2)):
        if len(row) >= 3:
            out.append([row[2], False])
    for row in table_rows(section(text, "Tasks", 2)):
        if len(row) >= 4:
            out.append([row[3], True])
    return [(b[0], b[1]) for b in out]


def sentences(text: str) -> list[tuple[str, bool]]:
    res = []
    for block, procedure in blocks(text):
        plain = CODE.sub("CODE", LINK.sub(r"\1", block))
        res += [(s.strip(), procedure) for s in SENTENCE_END.split(plain) if s.strip()]
    return res


def check_language(text: str, rules: dict, name: str) -> list[str]:
    fails = []
    for sent, procedure in sentences(text):
        limit = rules[LIMIT_PROCEDURE if procedure else LIMIT_DESCRIPTIVE]
        count = len(sent.split())
        if count > limit:
            fails.append(f"{name}: sentence has {count} words (limit {limit}): {sent[:50]}")
        for term in rules[BANNED]:
            if re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", sent, re.I):
                fails.append(f"{name}: banned term {term}: {sent[:50]}")
    return fails


def passive_warnings(text: str, name: str) -> list[str]:
    return [f"{name}: possible passive voice: {s[:50]}" for s, _ in sentences(text) if PASSIVE.search(s)]


def check_trace(spec: str, plan: str | None) -> list[str]:
    spec, plan = FENCE.sub("", spec), FENCE.sub("", plan) if plan is not None else None
    req_body = section(spec, "Requirements", 2)
    if req_body is None:
        return ["spec has no `## Requirements` section"]
    task_body = section(plan, "Tasks", 2) if plan is not None else None   # a plan's tasks replace the spec's
    if task_body is None:
        task_body = section(spec, "Tasks", 2)
    if task_body is None:
        return ["neither the plan nor the spec has a `## Tasks` section"]
    fails: list[str] = []
    reqs: dict[str, str] = {}
    for row in table_rows(req_body):
        if len(row) != 4:
            fails.append(f"requirement {row[0]} needs 4 cells, not {len(row)}")
            continue
        rid, priority, _, check = row
        if rid in reqs:
            fails.append(f"duplicate requirement id {rid}")
        reqs[rid] = priority
        if priority not in PRIORITIES:
            fails.append(f"requirement {rid} has unknown priority {priority}")
        if priority == "MUST" and "`" not in check and not check.startswith("manual:"):
            fails.append(f"MUST requirement {rid} has no command or manual: check")
    if not reqs:
        fails.append("`## Requirements` has no rows")
    tasks: dict[str, tuple[list[str], list[str]]] = {}
    for row in table_rows(task_body):
        if len(row) != 4:
            fails.append(f"task {row[0]} needs 4 cells, not {len(row)}")
            continue
        tid, deps, verifies, _ = row
        if tid in tasks:
            fails.append(f"duplicate task id {tid}")
        split = lambda cell: [x.strip() for x in cell.split(",") if x.strip() not in NO_ID]   # noqa: E731
        tasks[tid] = (split(deps), split(verifies))
    if not tasks:
        fails.append("`## Tasks` has no rows")
    covered = set()
    for tid, (deps, verifies) in tasks.items():
        if not verifies:
            fails.append(f"task {tid} verifies no requirement")
        for rid in verifies:
            covered.add(rid)
            if rid not in reqs:
                fails.append(f"task {tid} names unknown requirement {rid}")
        fails += [f"task {tid} depends on unknown task {d}" for d in deps if d not in tasks]
    fails += [f"MUST requirement {r} has no verifying task" for r, p in reqs.items() if p == "MUST" and r not in covered]
    state: dict[str, int] = {}

    def cyclic(tid: str) -> bool:
        if state.get(tid):
            return state[tid] == 1
        state[tid] = 1
        found = any(cyclic(d) for d in tasks[tid][0] if d in tasks)
        state[tid] = 2
        return found

    if any([cyclic(t) for t in tasks]):
        fails.append("the task dependencies hold a cycle")
    return fails


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 64
    root, index = args[0], "--index" in args[1:]

    def read(rel: str) -> str | None:
        if index:
            r = git(root, "show", f":{rel}")
            return r.stdout if r.returncode == 0 else None
        try:
            return open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
        except OSError:
            return None

    hop_text = read(HOPSTATE)
    if hop_text is None:   # a repo from before the hop-state split keeps these lines in the envelope
        hop_text = read(ENVELOPE) or ""

    def line(name: str) -> str:
        m = re.search(rf"^{name}:[ \t]*(\S*)", hop_text, re.M)
        return m.group(1) if m else ""

    hop, stage, slug = line("CURRENT_HOP").upper(), line("CURRENT_STAGE"), line("CURRENT_SLICE")
    if hop not in ("GENERATE", "EXECUTE") or not stage or not slug:
        print(f"SPECPLAN n/a — this check covers an open hop on a named slice (this hop: {hop or 'NONE'} {stage or '-'})")
        return 0
    spec_rel, plan_rel = f"docs/cascade/{stage}-{slug}.md", f"docs/cascade/plans/{stage}-{slug}.md"
    spec, plan = read(spec_rel), read(plan_rel)
    if stage != "05b" and spec is None and plan is None:
        print(f"SPECPLAN n/a — stage {stage} has no spec for this slice")
        return 0
    rules_text = read(RULES)
    rules_added = git(root, "log", "--diff-filter=A", "--format=%H", "-1", "--", RULES).stdout.strip()
    if rules_text is None and not rules_added:
        print(f"SPECPLAN n/a — this repo never held {RULES}")
        return 0
    if any(OFF.search(block) for block in EDIT.findall(read(ENVELOPE) or "")):
        print("SPECPLAN n/a — signed off in the envelope")
        return 0
    if git(root, "cat-file", "-e", f"HEAD:{spec_rel}").returncode == 0:   # a spec that is not at HEAD is new
        added = git(root, "log", "--diff-filter=A", "--format=%H", "-1", "--", spec_rel).stdout.strip()
        if added and rules_added and added != rules_added \
                and git(root, "merge-base", "--is-ancestor", added, rules_added).returncode == 0:
            print(f"SPECPLAN n/a — {spec_rel} predates the rules")
            return 0

    results: list[tuple[bool, str]] = []
    if rules_text is None:
        rules, bad = {}, [f"{RULES} left the repo after it landed"]
    else:
        rules, bad = parse_rules(rules_text)
    results.append((not bad, "the rules are signed and valid" if not bad else "; ".join(bad)))
    if stage == "05b":
        results.append((spec is not None, f"spec {spec_rel} exists"))
        if spec is not None:
            f = check_contract(spec)
            results.append((not f, "the contract has four valid fields" if not f else "; ".join(f)))
            f = check_trace(spec, plan)
            results.append((not f, "each requirement traces to a task" if not f else "; ".join(f[:8])))
    docs = [(rel, text) for rel, text in ((spec_rel, spec), (plan_rel, plan)) if text is not None]
    if not bad:
        f = [x for rel, text in docs for x in check_language(text, rules, rel)]
        results.append((not f, "the language rules hold" if not f else "; ".join(f[:8])))
    for rel, text in docs:
        for warning in passive_warnings(text, rel):
            print(f"WARN    {warning}")
    for ok, msg in results:
        print(f"{'PASS' if ok else 'FAIL'}    {msg}")
    k = sum(1 for ok, _ in results if ok)
    print(f"SPECPLAN {k}/{len(results)}")
    return 0 if k == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
