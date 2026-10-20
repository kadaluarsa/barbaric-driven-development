#!/usr/bin/env python3
"""Affected-law selection for one hop (t66).

    affected.py <root> <envelope> [--base REV] [--tsv | --list | --why]

The base is the commit that opened the current hop: the newest commit touching
`docs/cascade/hop-state.md` (or the envelope in a repo installed before the split), whose hop fields
equal the working tree's. `merge-base` would include every earlier hop on the same branch, and an
environment variable would let one line hide a law, so neither is used. `--base` exists for reports and
fixtures only; `tests/loop.sh` never passes it.

A law is affected when a changed file matches its `path:` (with the documented `:symbol` suffix stripped,
exactly as tests/dsharp_strength.sh does) or a file named in its check/break command, or when the changed
file's Gradle module is its module or a module that module depends on. Anything the script cannot prove
narrows the set: no base, a hop-state mismatch, build logic, a signed shared module, an unreadable module
map, an unknown module, an unmapped file, or a law with no map at all.

Output (--tsv):  M<TAB>full|narrow<TAB><base|-><TAB><reason>
                 L<TAB><id><TAB>affected|not<TAB><reason>
Exit 0 for every verdict, including full: full is today's behavior, not a failure. docs/cascade/
05b-t66-affected-laws.md is the contract.
"""
from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gradle_runner import parse                       # noqa: E402  (sibling: tests/lib ships as one directory)
from laws import laws as read_laws                    # noqa: E402
from signed import BLOCK                              # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INIT = os.path.join(HERE, "affected.init.gradle")
HOPSTATE = os.path.join("docs", "cascade", "hop-state.md")
ENVELOPE = os.path.join("docs", "cascade", "envelope.md")
BUILD_FILES = {"build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
               "gradle.properties", "libs.versions.toml"}
BUILD_DIRS = ("gradle/", "buildSrc/", "build-logic/")
SUFFIXES = (".py", ".sh", ".js", ".ts", ".java", ".kt", ".kts", ".rb", ".go", ".rs", ".cs", ".php",
            ".scala", ".groovy")
TIMEOUT = 600


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def hop_fields(text: str) -> dict:
    out = {}
    for line in text.replace("\r\n", "\n").split("\n"):
        m = re.match(r"^(CURRENT_HOP|CURRENT_STAGE|CURRENT_SLICE):[ \t]*(.*?)[ \t]*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def hop_base(root: str) -> tuple[str | None, str]:
    """The commit that opened this hop, or (None, why) — never a guess."""
    rel = HOPSTATE if os.path.isfile(os.path.join(root, HOPSTATE)) else ENVELOPE
    r = git(root, "log", "-1", "--format=%H", "--", rel)
    sha = r.stdout.strip()
    if r.returncode or not sha:
        return None, f"no commit opens this hop ({rel} is not committed)"
    if git(root, "merge-base", "--is-ancestor", sha, "HEAD").returncode:
        return None, f"the hop-open commit {sha[:7]} is not an ancestor of HEAD"
    old = git(root, "show", f"{sha}:{rel}")
    try:
        now = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
    except OSError:
        return None, f"{rel} cannot be read"
    if old.returncode or hop_fields(old.stdout) != hop_fields(now):
        return None, f"the last {os.path.basename(rel)} commit {sha[:7]} opened a different hop"
    return sha, ""


def ancestor(root: str, rev: str) -> tuple[bool, str]:
    if not rev:
        return False, "no base"
    if git(root, "rev-parse", "--verify", f"{rev}^{{commit}}").returncode:
        return False, f"base {rev} is not a commit"
    if git(root, "merge-base", "--is-ancestor", rev, "HEAD").returncode:
        return False, f"base {rev[:12]} is not an ancestor of HEAD"
    return True, ""


def changed(root: str, base: str) -> tuple[list[tuple[str, str]] | None, str]:
    """[(path, status)] since base: working tree + untracked; renames/copies at both paths, deletions old."""
    r = git(root, "diff", "--name-status", "-M", base)
    if r.returncode:
        return None, f"git diff failed: {r.stderr.strip()[:200]}"
    out: list[tuple[str, str]] = []
    for line in r.stdout.splitlines():
        p = line.split("\t")
        if len(p) < 2:
            continue
        st = p[0]
        if st.startswith(("R", "C")) and len(p) >= 3:
            out += [(p[1], st), (p[2], st)]
        else:
            out.append((p[1], st))
    u = git(root, "ls-files", "--others", "--exclude-standard")
    if u.returncode:
        return None, f"git ls-files failed: {u.stderr.strip()[:200]}"
    out += [(p, "??") for p in u.stdout.splitlines() if p.strip()]
    return out, ""


def is_build_logic(path: str) -> bool:
    name = os.path.basename(path)
    if name in BUILD_FILES:
        return True
    if path.startswith(BUILD_DIRS):
        return True
    return path.endswith((".gradle", ".gradle.kts"))


def is_docs(path: str) -> bool:
    return path.startswith("docs/") or path.lower().endswith(".md")


def in_force(text: str) -> list[dict]:
    out = []
    for d in read_laws(text):
        check = (d.get("check") or "").strip()
        brk = (d.get("break") or "").strip()
        if not check or check.lower() in ("todo", "none", "-"):
            continue
        if not brk or brk.lower() in ("todo", "none", "-"):
            continue
        out.append(d)
    return out


def file_parts(root: str, law: dict) -> list[tuple[str, bool]]:
    """(path, is_dir) the law guards. `:symbol` is stripped as dsharp_strength.sh does."""
    out: list[tuple[str, bool]] = []
    p = (law.get("path") or "").strip()
    if p:
        p = p.split(":", 1)[0].strip()
        p = p[2:] if p.startswith("./") else p.lstrip("/")
        if p:
            out.append((p, os.path.isdir(os.path.join(root, p))))
    for cmd in ((law.get("check") or ""), (law.get("break") or "")):
        try:
            toks = shlex.split(cmd)
        except ValueError:
            continue
        for tok in toks:
            tok = tok.strip("'\"")
            if not tok or tok.startswith(("-", "/")) or ".." in tok.split("/") or "$" in tok or "=" in tok:
                continue
            if not tok.endswith(SUFFIXES):
                continue
            tok = tok[2:] if tok.startswith("./") else tok
            if os.path.isfile(os.path.join(root, tok)):
                out.append((tok, False))
    seen, uniq = set(), []
    for x in out:
        if x not in seen:
            seen.add(x)
            uniq.append(x)
    return uniq


def matches(path: str, guarded: list[tuple[str, bool]]) -> bool:
    for g, is_dir in guarded:
        if path == g or (is_dir and path.startswith(g.rstrip("/") + "/")):
            return True
    return False


def module_of(check: str, root: str) -> tuple[str | None, str]:
    """(:module, "") for a Gradle check with exactly one `:module:task`; (None, "") for non-Gradle;
    (None, why) when a Gradle check cannot name one module — that law runs everywhere."""
    toks = check.split()
    if not toks or toks[0] not in ("./gradlew", "gradle"):
        return None, ""
    p = parse(check, root)
    if p is None or len(p["sels"]) != 1:
        return None, "a Gradle check that does not name exactly one task"
    sel = p["sels"][0][0]
    if not sel.startswith(":") or sel.count(":") < 2:
        return None, "a Gradle check without a project path (`:module:test`)"
    return sel[: sel.rfind(":")], ""


def shared_modules(text: str) -> tuple[list[str], str]:
    """The last signed AFFECTED_SHARED_MODULES line inside <EDIT>, or none."""
    val = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = re.match(r"^\s*-\s*AFFECTED_SHARED_MODULES:\s*(.*?)\s*$", line)
            if m and "{{" not in line:
                val = m.group(1)
    return [x for x in re.split(r"[\s,]+", val or "") if x], ""


def module_map(root: str, entries: set[str]) -> tuple[dict | None, str]:
    """{project path: (dir, [deps])} from one Gradle configure per entry. None, why on any doubt."""
    merged: dict = {}
    for entry in sorted(entries):
        fd, tmp = tempfile.mkstemp(prefix="affected-", suffix=".tsv")
        os.close(fd)
        try:
            env = dict(os.environ, BDD_AFFECTED_OUT=tmp)
            try:
                r = subprocess.run([entry, "-q", "--no-configuration-cache", "-I", INIT,
                                    "bddAffectedProjects"], cwd=root, env=env,
                                   capture_output=True, text=True, timeout=TIMEOUT)
            except (OSError, subprocess.SubprocessError) as exc:
                return None, f"the module map build could not start ({entry}: {exc.__class__.__name__})"
            if r.returncode != 0:
                tail = (r.stderr or r.stdout).strip().splitlines()
                return None, f"the module map build failed ({entry}, exit {r.returncode}: {tail[-1][:160] if tail else 'no output'})"
            try:
                rows = [ln.split("\t") for ln in open(tmp, encoding="utf-8", errors="replace").read().splitlines() if ln.strip()]
            except OSError:
                return None, "the module map file could not be read"
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        if not rows:
            return None, f"the module map is empty ({entry})"
        for row in rows:
            if row[0].startswith("!ERROR"):
                return None, f"the module map build reported an error ({row[-1][:160]})"
            if len(row) < 3:
                return None, "a module map row is malformed"
            path, d = row[0].strip(), row[1].strip().strip("/").lstrip("./")
            deps = [x for x in row[2].split(",") if x]
            if path in merged and merged[path][0] != d:
                return None, f"{path} has two project directories"
            old = merged.get(path)
            merged[path] = (d, sorted(set((old[1] if old else []) + deps)))
            if any(not os.path.isdir(os.path.join(root, d)) for pp, (d, _) in merged.items()):
                return None, "a project directory in the map does not exist"
    return merged, ""


def owner(path: str, projects: dict) -> str | None:
    best = None
    for pp, (d, _) in projects.items():
        if not d:
            continue
        if path == d or path.startswith(d + "/"):
            if best is None or len(d) > len(projects[best][0]):
                best = pp
    return best


def closure(module: str, projects: dict) -> tuple[set[str] | None, str]:
    seen: set[str] = set()
    stack = [module]
    while stack:
        m = stack.pop()
        if m in seen:
            continue
        if m not in projects:
            return None, f"module {m} is not in the map"
        seen.add(m)
        stack += [d for d in projects[m][1] if d not in seen]
    return seen, ""


def decide(root: str, envelope: str, base_override: str | None = None) -> tuple[dict, str, str, list[tuple[str, bool, str]]]:
    """(header, base, reason, rows) where rows are (id, affected, why)."""
    try:
        text = open(envelope, encoding="utf-8", errors="replace").read()
    except OSError:
        text = ""
    rows = in_force(text)
    by_id = {d["id"]: d for d in rows}

    def full(reason: str):
        return ({"mode": "full", "base": base_override or "", "reason": reason}, base_override or "",
                reason, [(d["id"], True, reason) for d in rows])

    if not rows:
        return {"mode": "narrow", "base": "", "reason": "no in-force law"}, "", "no in-force law", []

    if base_override:
        ok, why = ancestor(root, base_override)
        if not ok:
            return full(why)
        base = base_override
    else:
        base, why = hop_base(root)
        if not base:
            return full(why)

    files, why = changed(root, base)
    if files is None:
        return full(why)

    guarded = {d["id"]: file_parts(root, d) for d in rows}
    modules: dict[str, str | None] = {}
    for d in rows:
        m, why = module_of((d.get("check") or "").strip(), root)
        if why:
            return full(f"{d['id']}: {why}")
        modules[d["id"]] = m

    entries = {"./gradlew" if (d.get("check") or "").startswith("./gradlew") else "gradle"
               for d in rows if modules[d["id"]]}
    projects: dict = {}
    if entries:
        projects, why = module_map(root, entries)
        if projects is None:
            return full(why)

    shared, _ = shared_modules(text)
    if shared:
        if not projects:
            return full("AFFECTED_SHARED_MODULES is signed but no Gradle module map exists")
        for m in shared:
            if m not in projects:
                return full(f"shared module {m} is not in the map")

    affected: dict[str, bool] = {d["id"]: False for d in rows}
    why_for: dict[str, str] = {d["id"]: "" for d in rows}

    for path, _st in files:
        if is_build_logic(path):
            return full(f"build logic changed: {path}")
        for d in rows:
            if matches(path, guarded[d["id"]]):
                affected[d["id"]] = True
                why_for[d["id"]] = why_for[d["id"]] or f"file {path}"
        own = owner(path, projects) if projects else None
        if own:
            if own in shared:
                return full(f"shared module {own} changed: {path}")
            for d in rows:
                m = modules[d["id"]]
                if not m:
                    continue
                cl, why = closure(m, projects)
                if cl is None:
                    return full(why)
                if own in cl:
                    affected[d["id"]] = True
                    why_for[d["id"]] = why_for[d["id"]] or (
                        f"module {own}" if own == m else f"module {own} is in {m}'s closure")
            continue
        if is_docs(path) or matches_any(path, guarded):
            continue
        return full(f"no law maps {path}")

    for d in rows:
        if not guarded[d["id"]] and not modules[d["id"]]:
            return full(f"{d['id']} has neither a path: nor a Gradle module")
        m = modules[d["id"]]
        if m and m not in projects:
            return full(f"{d['id']} names module {m}, which is not in the map")

    out = [(d["id"], affected[d["id"]], why_for[d["id"]]) for d in rows]
    return {"mode": "narrow", "base": base, "reason": ""}, base, "", out


def matches_any(path: str, guarded: dict) -> bool:
    return any(matches(path, g) for g in guarded.values())


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: affected.py <root> <envelope> [--base REV] [--tsv|--list|--why]", file=sys.stderr)
        return 64
    root, envelope = sys.argv[1], sys.argv[2]
    if not os.path.isabs(envelope):
        envelope = os.path.join(root, envelope)
    mode = "human"
    base = None
    i = 3
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--base" and i + 1 < len(sys.argv):
            base = sys.argv[i + 1]; i += 2
        elif a in ("--tsv", "--list", "--why"):
            mode = a[2:]; i += 1
        else:
            print(f"affected.py: unknown argument {a}", file=sys.stderr)
            return 64
    try:
        header, used, reason, rows = decide(root, envelope, base)
    except Exception as exc:  # noqa: BLE001 — a crash must be the full set, never an empty one
        header = {"mode": "full", "base": base or "", "reason": f"selector failed ({exc.__class__.__name__}: {exc})"}
        used, reason, rows = base or "", header["reason"], []
        try:
            rows = [(d["id"], True, reason) for d in in_force(open(envelope, encoding="utf-8", errors="replace").read())]
        except OSError:
            rows = []
    if mode == "tsv":
        print("\t".join(["M", header["mode"], used or "-", reason.replace("\t", " ")]))
        for lid, aff, why in rows:
            print("\t".join(["L", lid, "affected" if aff else "not", why.replace("\t", " ")]))
    elif mode == "list":
        for lid, aff, _ in rows:
            if aff:
                print(lid)
    elif mode == "why":
        print(f"mode: {header['mode']}")
        print(f"base: {used or '-'}")
        print(f"reason: {reason or '-'}")
        for lid, aff, why in rows:
            print(f"{lid}: {'affected' if aff else 'not affected'}{(' — ' + why) if why else ''}")
    else:
        try:
            names = {d["id"]: d.get("law", "") for d in in_force(open(envelope, encoding="utf-8", errors="replace").read())}
        except OSError:
            names = {}
        aff = sum(1 for _, a, _ in rows if a)
        if header["mode"] == "full":
            print(f"AFFECTED full — {reason}")
        else:
            print(f"AFFECTED {aff}/{len(rows)} affected (base {used[:12]})")
        for lid, a, why in rows:
            label = names.get(lid, "")
            state = "affected" if a else "not affected"
            print(f"{state}  {lid}  {label}{('  — ' + why) if why else ''}".rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
