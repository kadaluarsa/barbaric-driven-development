#!/usr/bin/env python3
"""A law may leave force inside an open hop only if it is GREEN (t68, I18).

    retirement_guard.py staged  <root>          the commit being made: HEAD vs the index
    retirement_guard.py history <root> <base>   every commit from <base> to HEAD (the merge gate's backstop)

A law leaves force when it is declared before and not declared after: a valid `retired:` line was added, or its D#
block was deleted. A hop is open when CURRENT_HOP is GENERATE or EXECUTE in the hop state before **or** after (read
from git, never from the working tree, so staging `CURRENT_HOP: NONE` in the same commit is not a closed hop).
Then the law's check: and break: are run on the tree before the change (a `git archive` in a temp directory, GIT_*
variables unset): GREEN = the check passes and the break fails. Anything else — RED, THEATER, UNPROVEN — is refused,
whoever signs it. A law that another law names in `superseded by` may not be retired until that pointer moves.

Prints one refusal line per law and exits 1, or exits 0. docs/cascade/05b-t68-law-retirement.md is the contract.
"""
from __future__ import annotations

import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from laws import RETIRED, laws as parse_laws, retirement   # noqa: E402

ENVELOPE = "docs/cascade/envelope.md"
HOPSTATE = "docs/cascade/hop-state.md"
SHARDS = "docs/cascade/laws/"
GIT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR")
TIMEOUT = 1800


def git(root: str, *args: str, binary: bool = False):
    env = {k: v for k, v in os.environ.items() if k not in GIT_VARS or k == "GIT_INDEX_FILE"}
    r = subprocess.run(["git", *args], cwd=root, capture_output=True, env=env)
    return r if binary else subprocess.CompletedProcess(r.args, r.returncode, r.stdout.decode("utf-8", "replace"),
                                                       r.stderr.decode("utf-8", "replace"))


def blob(root: str, spec: str) -> str | None:
    """`git show <spec>` — `REV:path` for a commit, `:path` for the index. None when it does not exist."""
    r = git(root, "show", spec)
    return r.stdout if r.returncode == 0 else None


def law_files(root: str, rev: str | None) -> list[str]:
    """The shard paths in a commit (rev) or in the index (None)."""
    r = git(root, "ls-tree", "--name-only", rev, SHARDS) if rev else git(root, "ls-files", "--", SHARDS)
    return [p for p in r.stdout.splitlines() if p.endswith(".md") and not p.endswith("/README.md")]


_LAWS: dict = {}


def laws_at(root: str, rev: str | None) -> list[dict]:
    """Every law (retired included) as committed at rev, or as staged (rev None), in laws.py's order. Tolerant of a
    duplicate id — the first one counts — so a duplicate can never be the reason this check is skipped (a dup added
    to one commit and removed in the next must not hide a failing law leaving force). Memoised per commit."""
    if rev and rev in _LAWS:
        return _LAWS[rev]
    prefix = f"{rev}:" if rev else ":"
    out: list[dict] = []
    for p in [ENVELOPE] + sorted(law_files(root, rev)):
        text = blob(root, prefix + p)
        for d in parse_laws(text or ""):
            d["source"] = p
            out.append(d)
    first: dict = {}
    for d in out:
        first.setdefault(d["id"], d)
    for d in out:
        d["retired_ok"], d["retired_date"], d["retired_why"] = (
            retirement(d, first) if (d.get("retired") or "").strip() else (False, "", ""))
    if rev:
        _LAWS[rev] = out
    return out


def hop_open(root: str, rev: str | None) -> bool:
    prefix = f"{rev}:" if rev else ":"
    text = blob(root, prefix + HOPSTATE)
    if text is None:
        text = blob(root, prefix + ENVELOPE) or ""   # a repo from before the hop-state split
    m = re.search(r"^CURRENT_HOP:\s*(\S+)", text, re.M)
    return bool(m) and m.group(1).upper() in ("GENERATE", "EXECUTE")


_ARCHIVES: dict = {}


def verdict(root: str, rev: str, law: dict, tmp: str) -> str:
    """GREEN / RED / THEATER / UNPROVEN of a law on the tree at rev (a commit or a tree id), or UNBUILDABLE.
    Each law gets a fresh copy, so one law's break cannot leave a mutant behind for the next. The copy is a clean
    export: no .git, no untracked or ignored files — a law that needs them cannot be proven here and is retired with
    no hop running instead."""
    blank = lambda c: not c or c.strip().lower() in ("todo", "none", "-")   # noqa: E731
    if blank(law.get("check")) or blank(law.get("break")):
        return "UNPROVEN"
    if rev not in _ARCHIVES:
        r = git(root, "archive", "--format=tar", rev, binary=True)
        _ARCHIVES[rev] = r.stdout if r.returncode == 0 else None
    if _ARCHIVES[rev] is None:
        return "UNBUILDABLE"   # no evidence it was GREEN
    tree = tempfile.mkdtemp(prefix=f"tree-{law['id']}-", dir=tmp)
    try:
        with tarfile.open(fileobj=io.BytesIO(_ARCHIVES[rev])) as tf:
            try:
                tf.extractall(tree, filter="data")   # no absolute paths, links out of the tree, or device files
            except TypeError:                        # Python before 3.12's extraction filters
                tf.extractall(tree)
    except (tarfile.TarError, OSError):
        return "UNBUILDABLE"
    env = {k: v for k, v in os.environ.items() if k not in GIT_VARS}

    def ok(cmd: str) -> bool:
        try:
            return subprocess.run(["bash", "-c", cmd], cwd=tree, env=env, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=TIMEOUT).returncode == 0
        except subprocess.TimeoutExpired:
            return False
    if not ok(law["check"]):
        return "RED"
    if ok(law["break"]):
        return "THEATER"
    return "GREEN"


def judge(root: str, before: list[dict], after: list[dict], open_: bool, revs: tuple[str, str], tmp: str,
          where: str) -> list[str]:
    """revs = (the tree before, the tree after). A leaving law must be GREEN on both: before, so a failing law is not
    dropped; after, so one commit cannot break the product and drop the law that would catch it."""
    out = []
    first_before: dict = {}
    for d in before:
        first_before.setdefault(d["id"], d)
    in_force_before = {i: d for i, d in first_before.items() if not d["retired_ok"]}
    in_force_after = {d["id"] for d in after if not d["retired_ok"]}
    leaving = [d for i, d in in_force_before.items() if i not in in_force_after]
    # A law others point at with `superseded by` may not leave force — retired or deleted — while they still do:
    # otherwise their retirement turns invalid and they silently come back into force.
    leaving_ids = {d["id"] for d in leaving}
    for d in after:
        m = RETIRED.match((d.get("retired") or "").strip())
        if m and m.group(2) and m.group(2).upper() in leaving_ids:
            out.append(f"RETIREMENT REFUSED  {m.group(2).upper()}  {d['id']} says it is superseded by "
                       f"{m.group(2).upper()}{where}; re-point {d['id']} first")
    if not open_:
        return out
    for d in leaving:
        for label, rev in (("before", revs[0]), ("after", revs[1])):
            v = verdict(root, rev, d, tmp)
            if v != "GREEN":
                out.append(f"RETIREMENT REFUSED  {d['id']}  {d['law']} is {v} on the tree {label} this change "
                           f"({rev[:12]}){where}; taking it out of force inside an open hop would drop a failing law to "
                           "pass a gate (I18). Fix it, or close the hop and retire it with no hop running.")
                break
    return out


def staged(root: str) -> int:
    touched = git(root, "diff", "--cached", "--no-renames", "--name-only", "--", ENVELOPE, SHARDS).stdout.split()
    if not touched or git(root, "rev-parse", "-q", "--verify", "HEAD").returncode != 0:
        return 0
    tmp = tempfile.mkdtemp(prefix="bdd-retire-")
    try:
        before, after = laws_at(root, "HEAD"), laws_at(root, None)
        head = git(root, "rev-parse", "HEAD").stdout.strip()
        staged_tree = git(root, "write-tree").stdout.strip()   # the tree this commit will have
        if not staged_tree:
            print("BLOCKED: the staged tree cannot be read, so a law leaving force cannot be checked (t68)", file=sys.stderr)
            return 1
        out = judge(root, before, after, hop_open(root, "HEAD") or hop_open(root, None), (head, staged_tree), tmp, "")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if out:
        print("BLOCKED: a law may leave force inside an open hop only if it is GREEN (t68, I18) — no signature lifts this:",
              file=sys.stderr)
    for line in out:
        print("  " + line, file=sys.stderr)
    return 1 if out else 0


def history(root: str, base: str) -> int:
    revs = git(root, "rev-list", "--reverse", f"{base}..HEAD" if base else "HEAD", "--", ENVELOPE, SHARDS).stdout.split()
    tmp = tempfile.mkdtemp(prefix="bdd-retire-")
    out = []
    try:
        for c in revs:
            parent = git(root, "rev-parse", "-q", "--verify", f"{c}^").stdout.strip()
            if not parent:
                continue
            before, after = laws_at(root, parent), laws_at(root, c)
            out += judge(root, before, after, hop_open(root, parent) or hop_open(root, c), (parent, c), tmp,
                         f" (in {c[:12]})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for line in out:
        print(line)
    print(f"RETIREMENTS {'REFUSED' if out else 'clean'}: {len(revs)} commit(s) touching the laws checked")
    return 1 if out else 0


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == "staged":
        return staged(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "history":
        return history(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    print(__doc__.strip().splitlines()[2], file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
