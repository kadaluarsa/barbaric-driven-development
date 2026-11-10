#!/usr/bin/env python3
"""Reuse a goal line's PASS while nothing its key holds has changed (t101).

    { printf 'V\\t<index>\\t<line>\\n' ...; } | goal_cache.py keys  <root> <envelope> <dir>
    { printf 'S\\t<line>\\t<key>\\n' ...; }   | goal_cache.py store <root> <dir> <fingerprint>

`keys` prints `F\\t<fingerprint>`, then `K\\t<index>\\t<key>\\t<hit|miss>` for each line it could key and
`N\\t<index>\\t<why>` for each it could not; or a single `OFF\\t<why>` when no line can be keyed this pass. `store`
writes each fresh PASS as <dir>/<id>.json, only when the worktree fingerprint still equals the one `keys` took;
otherwise it prints `NOSTORE\\t<why>` and writes nothing. docs/cascade/05b-t101-goal-verdict-cache.md is the contract.

Which lines have a key: a plain Gradle line on one module (`./gradlew :core:test …`, no shell metacharacter), and a
line a committed, signed `- LOOP_CACHE_PATHS: <path> … :: <line>` names exactly. Every other line always runs.
Only PASS is stored or reused; any doubt while computing a key is a miss, never a hit (I18). tests/loop.sh never
calls this for the autopilot gate (CASCADE_HOPSTATE / CASCADE_ENVELOPE set) or with BDD_LOOP_CACHE=off, and the
merge gate, the audit and the regression suite never call it.
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verdict_cache as vc   # noqa: E402
from affected import closure, in_force, is_build_logic, is_docs, module_map, module_of, shared_modules   # noqa: E402
from signed import BLOCK   # noqa: E402

SCHEMA = "bdd-goal-cache/1"
PATHS = re.compile(r"^\s*-\s*LOOP_CACHE_PATHS:\s*(.+?)\s+::\s+(.+?)\s*$")
META = set(";|&<>`$()")
ENTRY = ("./gradlew", "gradle")
EXTRA_ENV = ("ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_USER_HOME", "GRADLE_USER_HOME")
PACK_FILES = ("../loop.sh", "goal_cache.py") + vc.SCORERS


def line_id(line: str) -> str:
    return hashlib.sha256(line.encode()).hexdigest()[:16]


def sha_or_absent(path: str) -> str:
    return vc.sha_file(path) if os.path.isfile(path) else "absent"


def committed_text(root: str, envelope: str) -> str:
    """The envelope as committed at HEAD: a signature in the worktree only is no signature (item 2)."""
    rel = os.path.relpath(os.path.realpath(envelope), os.path.realpath(root))
    if rel.startswith(".."):
        return ""
    try:
        r = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=root, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout if r.returncode == 0 else ""


def signed_paths(text: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for block in BLOCK.findall(text):
        for raw in block.splitlines():
            m = PATHS.match(raw)
            if m and "{{" not in raw:
                out[m.group(2)] = [p[2:] if p.startswith("./") else p for p in m.group(1).split()]
    return out


def is_plain_gradle(line: str) -> bool:
    toks = line.split()
    return bool(toks) and toks[0] in ENTRY and not (set(line) & META)


def gradle_props(root: str, projects: dict) -> dict:
    """Item 6c: build inputs git may ignore, read directly."""
    dirs = {""} | {d for d, _ in projects.values() if d}
    out = {}
    for d in sorted(dirs):
        for name in ("local.properties", "gradle.properties"):
            rel = os.path.join(d, name) if d else name
            out[rel] = sha_or_absent(os.path.join(root, rel))
    home = os.path.join(os.path.expanduser("~"), ".gradle")
    out["~/.gradle/gradle.properties"] = sha_or_absent(os.path.join(home, "gradle.properties"))
    for p in sorted(glob.glob(os.path.join(home, "init.d", "*"))):
        out["~/.gradle/init.d/" + os.path.basename(p)] = sha_or_absent(p)
    return out


def law_keys(root: str, envelope: str, cdir: str, lines: list[str]) -> dict[str, str | None]:
    """Item 6b: for each goal line equal to an in-force D# check, that law's t65 key (None: t65 gives it none)."""
    try:
        laws = in_force(root, envelope)
    except Exception:   # noqa: BLE001 — unreadable laws: every law line misses
        return {ln: None for ln in lines}
    want = {}
    for i, law in enumerate(laws):
        check = (law.get("check") or "").strip()
        if check in lines and check not in want:
            want[check] = [ "L", str(i), str(law.get("id") or ""), check, (law.get("break") or "").strip(),
                            (law.get("path") or "").strip()]
    if not want:
        return {}
    try:
        rows = vc.keys(root, envelope, cdir, list(want.values()))
    except Exception:   # noqa: BLE001 — NoKey and any other doubt
        return {ln: None for ln in want}
    by_index = {}
    for r in rows:
        parts = r.split("\t")
        if parts[0] == "K" and len(parts) >= 3:
            by_index[parts[1]] = parts[2]
    return {check: by_index.get(row[1]) for check, row in want.items()}


def keys(root: str, envelope: str, cdir: str, rows: list[tuple[str, str]]) -> list[str]:
    try:
        text = open(envelope, encoding="utf-8", errors="replace").read()
    except OSError:
        text = ""
    signed = signed_paths(committed_text(root, envelope))
    candidates = []
    for idx, line in rows:
        if is_plain_gradle(line):
            mod, _ = module_of(line, root)
            candidates.append((idx, line, "gradle", mod) if mod else (idx, line, None, "a Gradle line with no single :module:task"))
        elif line in signed:
            candidates.append((idx, line, "paths", None))
        else:
            candidates.append((idx, line, None, "no key: not a plain Gradle line, and no signed LOOP_CACHE_PATHS line names it"))
    if not any(c[2] for c in candidates):
        return ["OFF\tno goal line has a key"]

    f1, blobs = vc.fingerprint(root)
    tree = vc.Tree(root, blobs)
    entries = {line.split()[0] for _, line, *_ in candidates if line.split()[:1] and line.split()[0] in ENTRY}
    projects: dict = {}
    if entries:
        projects, why = module_map(root, entries)
        if projects is None:
            return [f"OFF\t{why}"]
    u = platform.uname()
    toolchain = {"uname": f"{u.system} {u.release} {u.machine}",
                 "bash": vc.first_line(["bash", "--version"]), "python": sys.version.split()[0]}
    for entry in sorted(entries):
        try:
            r = subprocess.run([entry, "--version"], cwd=root, capture_output=True, text=True, timeout=vc.TIMEOUT,
                               stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as exc:
            return [f"OFF\t{entry} --version could not run ({exc.__class__.__name__})"]
        if r.returncode != 0:
            return [f"OFF\t{entry} --version failed (exit {r.returncode})"]
        toolchain[entry] = r.stdout
    pack = {"version": vc.pack_version(root), "files": {s: sha_or_absent(os.path.join(HERE, s)) for s in PACK_FILES}}
    props = gradle_props(root, projects)
    shared, _ = shared_modules(text)
    for m in shared:
        if m not in projects:
            return [f"OFF\tshared module {m} is not in the module map"]
    tree_scope = (vc.signed_values(text, vc.SCOPE) or "").strip() == "tree"

    owned: set[str] = set()
    for d, _ in projects.values():
        if d:
            owned.update(tree.under(d))
    nondoc = [p for p in tree.paths if not is_docs(p)]
    unowned = {p for p in nondoc if p not in owned}
    glob_paths = {p for p in nondoc if is_build_logic(p)} | unowned
    for m in shared:
        glob_paths.update(tree.under(projects[m][0]))
    unowned_digest = vc.digest(tree.rows(unowned))
    glob_digest = vc.digest(tree.rows(glob_paths))
    whole = vc.digest(tree.rows(tree.paths)) if tree_scope else None
    laws = law_keys(root, envelope, cdir, [c[1] for c in candidates if c[2]])

    out = [f"F\t{f1}"]
    for idx, line, kind, extra in candidates:
        if not kind:
            out.append(f"N\t{idx}\t{extra}")
            continue
        named = tree.guarded(vc.named_files(root, {"check": line, "break": ""}))
        if kind == "gradle":
            mods, why = closure(extra, projects)
            if mods is None:
                out.append(f"N\t{idx}\t{why}")
                continue
            own: set[str] = set()
            for m in sorted(mods):
                d = projects[m][0]
                if d:
                    own.update(tree.under(d))
            part = {"own": vc.digest(tree.rows(own)), "global": glob_digest, "shared": shared, "whole": whole}
        else:
            own = set()
            for p in signed[line]:
                p = p.rstrip("/") if p not in ("", "/") else p
                if p in tree.blobs:
                    own.add(p)
                own.update(tree.under(p))
            part = {"paths": signed[line], "own": vc.digest(tree.rows(own)), "unowned": unowned_digest}
        if line in laws:
            if laws[line] is None:
                out.append(f"N\t{idx}\tthe D# check line has no t65 key")
                continue
            part["law"] = laws[line]
        env = vc.env_part(line, "")
        env.update({k: os.environ.get(k) for k in EXTRA_ENV})
        obj = {"schema": SCHEMA, "line": line, "kind": kind, "part": part, "named": vc.digest(tree.rows(named)),
               "toolchain": toolchain, "pack": pack, "props": props, "env": env}
        key = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        out.append(f"K\t{idx}\t{key}\t{'hit' if lookup(cdir, line, key) else 'miss'}")
    return out


def lookup(cdir: str, line: str, key: str) -> bool:
    p = os.path.join(cdir, f"{line_id(line)}.json")
    if os.path.islink(p) or not os.path.isfile(p):
        return False
    try:
        entry = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(entry, dict) or entry.get("schema") != SCHEMA:
        return False
    return entry.get("line") == line and entry.get("key") == key and entry.get("verdict") == "PASS"


def store(root: str, cdir: str, f1: str, rows: list[list[str]]) -> list[str]:
    todo = [(r[1], r[2]) for r in rows if len(r) >= 3 and r[0] == "S" and re.fullmatch(r"[0-9a-f]{64}", r[2])]
    if not todo:
        return []
    f2, _ = vc.fingerprint(root)
    if f2 != f1:
        return ["NOSTORE\tthe worktree changed during the pass"]
    if os.path.islink(cdir):
        return ["NOSTORE\tthe cache directory is a symlink"]
    os.makedirs(cdir, exist_ok=True)
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for line, key in todo:
        lid = line_id(line)
        fd, tmp = tempfile.mkstemp(prefix=f".{lid}-", dir=cdir)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"schema": SCHEMA, "line": line, "key": key, "verdict": "PASS", "at": at}, fh)
        os.replace(tmp, os.path.join(cdir, f"{lid}.json"))
    return []


def main() -> int:
    if len(sys.argv) >= 5 and sys.argv[1] == "keys":
        rows = []
        for raw in sys.stdin.read().splitlines():
            parts = raw.split("\t", 2)
            if len(parts) == 3 and parts[0] == "V" and parts[2].strip():
                rows.append((parts[1], parts[2]))
        try:
            out = keys(sys.argv[2], sys.argv[3], sys.argv[4], rows)
        except Exception as exc:   # noqa: BLE001 — any doubt: every line runs
            out = [f"OFF\t{exc.__class__.__name__}: {str(exc)[:160]}"]
        print("\n".join(out))
        return 0
    if len(sys.argv) >= 5 and sys.argv[1] == "store":
        rows = []
        for raw in sys.stdin.read().splitlines():
            parts = raw.split("\t")
            if len(parts) >= 3 and parts[0] == "S":
                rows.append(["S", "\t".join(parts[1:-1]), parts[-1]])
        try:
            out = store(sys.argv[2], sys.argv[3], sys.argv[4], rows)
        except Exception as exc:   # noqa: BLE001
            out = [f"NOSTORE\t{exc.__class__.__name__}"]
        if out:
            print("\n".join(out))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
