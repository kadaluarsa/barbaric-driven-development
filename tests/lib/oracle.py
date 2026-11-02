#!/usr/bin/env python3
"""The frozen oracle (t89): a slice's acceptance tests, written at GENERATE and pinned, judge every builder alike.

    oracle.py <root>                                    the GENERATE 05b gate — PASS/FAIL lines, `ORACLE k/n`
    oracle.py <root> --write --run CMD [--run …] PATH…  write docs/cascade/05b-<slug>.oracle (GENERATE 05b only)
    oracle.py <root> --loop                             EXECUTE 05b, for tests/loop.sh: exit 0 green, 3 refused
    oracle.py <root> --due                              exit 0 when this hop's pack ships tests/oracle.sh (loop.sh asks)
    oracle.py <root> --paths                            the frozen paths and the manifest, one per line (for hooks)

The manifest (sha256sum format plus `run:` lines):
    <64 hex>  <repo-relative path>
    run: <the exact goal VALIDATOR command that runs the oracle>

On EXECUTE the manifest is read as committed at the commit that opened the hop (affected.hop_base), never from the
working tree: a builder that rewrites a test and its manifest together is still refused (C4). A signed `- ORACLE: off`
inside <EDIT> in envelope.md, at HEAD and in the working tree, turns everything off on every hop (C9).
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laws import hopstate_field   # noqa: E402  (sibling: tests/lib ships as one directory)
from signed import BLOCK          # noqa: E402

HASH = re.compile(r"^([0-9a-f]{64})  (\S.*?)\s*$")
RUN = re.compile(r"^run:[ \t]+(.*?)\s*$")
SWITCH = re.compile(r"^\s*-\s*ORACLE:\s*(on|off)(?=\s|$)")
ENVELOPE = os.path.join("docs", "cascade", "envelope.md")


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def manifest_rel(slug: str) -> str:
    return f"docs/cascade/05b-{slug}.oracle"


def _switch(text: str) -> str | None:
    last = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = SWITCH.match(line)
            if m and "{{" not in line:
                last = m.group(1)
    return last


def off(root: str) -> bool:
    """`- ORACLE: off` is the human's only when it is the decision at HEAD and in the working tree alike."""
    try:
        now = open(os.path.join(root, ENVELOPE), encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    head = git(root, "show", f"HEAD:{ENVELOPE}")
    return _switch(now) == "off" and head.returncode == 0 and _switch(head.stdout) == "off"


def parse(text: str) -> tuple[list[tuple[str, str]], list[str]]:
    files, runs = [], []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = HASH.match(line)
        if m:
            files.append((m.group(1), m.group(2)))
            continue
        m = RUN.match(line)
        if m:
            runs.append(m.group(1))
    return files, runs


def sha(path: str) -> str | None:
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def hop(root: str) -> tuple[str, str, str]:
    """The hop — from CASCADE_HOPSTATE when autopilot hands over the pre-edge state (t81), else the hop-state file."""
    pre = os.environ.get("CASCADE_HOPSTATE") or os.environ.get("CASCADE_ENVELOPE")
    if pre:
        f = {}
        try:
            for line in open(pre, encoding="utf-8", errors="replace"):
                for k in ("CURRENT_HOP", "CURRENT_STAGE", "CURRENT_SLICE"):
                    if line.startswith(k + ":"):
                        f[k] = line.split(":", 1)[1].strip()
        except OSError:
            pass
        return f.get("CURRENT_HOP", "").upper(), f.get("CURRENT_STAGE", ""), f.get("CURRENT_SLICE", "")
    return (hopstate_field(root, "CURRENT_HOP").upper(), hopstate_field(root, "CURRENT_STAGE"),
            hopstate_field(root, "CURRENT_SLICE"))


def file_checks(root: str, files: list[tuple[str, str]]) -> list[tuple[bool, str]]:
    out = []
    for want, rel in files:
        p = os.path.join(root, rel)
        got = sha(p) if os.path.isfile(p) and not os.path.islink(p) else None
        if got is None and not os.path.lexists(p):
            out.append((False, f"missing: {rel}"))
        elif got != want:
            out.append((False, f"hash differs: {rel}"))
        else:
            out.append((True, f"pinned: {rel}"))
    return out


def report(results: list[tuple[bool, str]]) -> int:
    for ok, msg in results:
        print(f"{'PASS' if ok else 'FAIL'}  {msg}")
    k = sum(1 for ok, _ in results if ok)
    print(f"ORACLE {k}/{len(results)}")
    return 0 if k == len(results) else 1


def gate(root: str) -> int:
    h, stage, slug = hop(root)
    if off(root):
        print("ORACLE off (signed)"); return 0
    if h != "GENERATE" or stage != "05b" or not slug:
        print(f"ORACLE n/a — the oracle gates GENERATE 05b (this hop: {h or 'NONE'} {stage or '-'})"); return 0
    rel = manifest_rel(slug)
    try:
        text = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
    except OSError:
        return report([(False, f"no oracle manifest: {rel}")])
    files, runs = parse(text)
    results = [(True, f"manifest: {rel}"),
               (bool(files), "the manifest lists at least one file" if files else "the manifest lists no file"),
               (bool(runs), "the manifest has a run: line" if runs else "the manifest has no run: line")]
    if bugfix_tagged(root, slug):   # t91: a [bug-fix] slice's oracle must fail before the fix
        m = FAILS_BEFORE.search(text)
        results.append((bool(m) and m.group(1) == "yes",
                        "the bug-fix oracle fails on the unfixed tree" if m and m.group(1) == "yes" else
                        "a bug-fix oracle must fail on the unfixed tree: every run: line passed" if m else
                        "a bug-fix oracle must fail on the unfixed tree: not recorded — re-run --write"))
    return report(results + file_checks(root, files))


FAILS_BEFORE = re.compile(r"^# fails-before-fix:\s*(yes|no)\s*$", re.M)


def bugfix_tagged(root: str, slug: str) -> bool:
    """t91: the brief opts in with an explicit tag — `- <slug>: [bug-fix] …` — never by keywords (C1)."""
    try:
        text = open(os.path.join(root, "docs", "cascade", "05b-briefs.md"), encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    m = re.search(r"^- " + re.escape(slug) + r":\s*((?:\[[\w -]+\]\s*)*)", text, re.M)
    return bool(m and "[bug-fix]" in m.group(1))


def bugfix_oracle_fails(root: str, runs: list[str]) -> bool:
    """t91: on the unfixed tree a bug-fix oracle must fail — true when at least one run: command exits non-zero."""
    for cmd in runs:
        try:
            r = subprocess.run(["bash", "-c", cmd], cwd=root, capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired:
            continue
        if r.returncode != 0:
            return True
    return False


def write(root: str, runs: list[str], paths: list[str]) -> int:
    h, stage, slug = hop(root)
    if h != "GENERATE" or stage != "05b" or not slug:
        print("oracle: --write is for GENERATE (the oracle is frozen on EXECUTE)")
        return 2
    if not paths or not runs:
        print("usage: oracle.sh --write --run CMD [--run CMD…] PATH…", file=sys.stderr); return 64
    lines = [f"# {slug} frozen oracle (t89) — written at GENERATE; EXECUTE builds against it and does not edit it"]
    for rel in paths:
        got = sha(os.path.join(root, rel))
        if got is None:
            print(f"oracle: {rel} does not exist", file=sys.stderr); return 1
        lines.append(f"{got}  {rel}")
    lines += [f"run: {r}" for r in runs]
    if bugfix_tagged(root, slug):   # t91: run once, here, and record — gates read it and never run product tests
        lines.insert(1, f"# fails-before-fix: {'yes' if bugfix_oracle_fails(root, runs) else 'no'}")
    with open(os.path.join(root, manifest_rel(slug)), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"oracle: wrote {manifest_rel(slug)} ({len(paths)} file(s), {len(runs)} run line(s))")
    return 0


def base_manifest(root: str, slug: str) -> tuple[str | None, str]:
    """The manifest as committed at the commit that opened this hop — (text or None, why)."""
    try:
        from affected import hop_base   # noqa: PLC0415
        base, why = hop_base(root)
    except Exception as exc:  # noqa: BLE001
        return None, f"cannot find the commit that opened this hop ({exc})"
    if not base:
        return None, f"cannot find the commit that opened this hop ({why})"
    r = git(root, "show", f"{base}:{manifest_rel(slug)}")
    if r.returncode != 0:
        return None, f"no oracle manifest: {manifest_rel(slug)} (not in the commit that opened this hop, {base[:7]})"
    return r.stdout, ""


def goal_lines(root: str) -> set[str]:
    try:
        text = open(os.path.join(root, "docs", "cascade", "goal.md"), encoding="utf-8", errors="replace").read()
    except OSError:
        return set()
    return {" ".join(l[len("VALIDATOR:"):].split()) for l in text.splitlines() if l.startswith("VALIDATOR:")}


def loop(root: str) -> int:
    h, stage, slug = hop(root)
    if off(root) or h != "EXECUTE" or stage != "05b" or not slug:
        return 0
    text, why = base_manifest(root, slug)
    if text is None:
        print(f"FAIL  {why}"); return 3
    files, runs = parse(text)
    results = file_checks(root, files)
    have = goal_lines(root)
    results += [(" ".join(r.split()) in have, f"run line not in the goal: {r}") for r in runs]
    if not files or not runs:
        results.append((False, "the frozen manifest lists no file or no run: line"))
    bad = [m for ok, m in results if not ok]
    for m in bad:
        print(f"FAIL  {m}")
    return 3 if bad else 0


def due(root: str) -> int:
    """0 when the oracle applies: this tree ships tests/oracle.sh, or the commit that opened the hop did (so deleting
    the script mid-hop does not switch the oracle off). A repo on a pre-t89 pack has neither."""
    if os.path.isfile(os.path.join(root, "tests", "oracle.sh")):
        return 0
    try:
        from affected import hop_base   # noqa: PLC0415
        base, _ = hop_base(root)
    except Exception:  # noqa: BLE001
        base = None
    if base and git(root, "cat-file", "-e", f"{base}:tests/oracle.sh").returncode == 0:
        return 0
    return 1


def paths(root: str) -> int:
    """The frozen set for hooks: on EXECUTE 05b, the base manifest's files and the manifest itself."""
    h, stage, slug = hop(root)
    if off(root) or h != "EXECUTE" or stage != "05b" or not slug:
        return 0
    text, _ = base_manifest(root, slug)
    if text is None:
        return 0
    print(manifest_rel(slug))
    for _, rel in parse(text)[0]:
        print(rel)
    return 0


def main() -> int:
    a = sys.argv[1:]
    if not a:
        print(__doc__.split("\n\n")[1], file=sys.stderr); return 64
    root, rest = a[0], a[1:]
    if not rest:
        return gate(root)
    if rest[0] == "--loop":
        return loop(root)
    if rest[0] == "--due":
        return due(root)
    if rest[0] == "--paths":
        return paths(root)
    if rest[0] == "--write":
        runs, files, i = [], [], 1
        while i < len(rest):
            if rest[i] == "--run" and i + 1 < len(rest):
                runs.append(rest[i + 1]); i += 2
            else:
                files.append(rest[i]); i += 1
        return write(root, runs, files)
    print(f"oracle.py: unknown argument {rest[0]}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
