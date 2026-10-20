#!/usr/bin/env python3
"""Reuse a law's GREEN when nothing it declares has changed (t65).

    { printf 'L\\t<index>\\t<id>\\t<check>\\t<break>\\t<path>\\n' ...; } | verdict_cache.py keys <root> <envelope> <dir>
    { printf 'S\\t<id>\\t<key>\\n' ...; }                               | verdict_cache.py store <root> <dir> <fingerprint>

`keys` prints `F\\t<fingerprint>`, then `K\\t<index>\\t<key>\\t<hit|miss>` for each law it could key and
`N\\t<index>\\t<why>` for each it could not; or a single `OFF\\t<why>` when no law can be keyed this run. `store`
writes each fresh GREEN as <dir>/<id>.json, only when the worktree fingerprint still equals the one `keys` took;
otherwise it prints `NOSTORE\\t<why>` and writes nothing. docs/cascade/05b-t65-verdict-cache.md is the contract.

Only GREEN is ever stored or reused. A hit needs the entry's schema, id and key to equal the computed ones and its
verdict to be exactly GREEN; anything else is a miss. Any doubt while computing a key is a miss, never a hit (I18).
The merge gate and the nightly never call this (DSHARP_CACHE=off).
"""
from __future__ import annotations

import bisect
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from affected import closure, file_parts, is_build_logic, is_docs, module_map, module_of, owner   # noqa: E402
from signed import BLOCK   # noqa: E402

SCHEMA = "bdd-verdict-cache/1"
ID = re.compile(r"^D\d+$")
SCOPE = re.compile(r"^\s*-\s*DSHARP_CACHE_SCOPE:\s*(\S+)")
SHARED = re.compile(r"^\s*-\s*AFFECTED_SHARED_MODULES:\s*(.*?)\s*$")
ENV_NAMES = ("GRADLE_OPTS", "JAVA_HOME", "JAVA_OPTS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")
ENV_PREFIXES = ("INV_", "DSHARP_", "ORG_GRADLE_PROJECT_")
ENV_SPEED = {"DSHARP_JOBS", "DSHARP_SERIAL", "DSHARP_CACHE", "DSHARP_HARNESS"}   # cannot change a verdict (I18)
REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
SCORERS = ("../dsharp_strength.sh", "laws.py", "law_harness.py", "verdict_cache.py", "affected.py", "gradle_runner.py",
           "law_harness.init.gradle", "affected.init.gradle")
TIMEOUT = 300


class NoKey(Exception):
    """A key cannot be computed: every law misses, nothing is stored."""


def fingerprint(root: str) -> tuple[str, dict]:
    """("t2:<tree>", {path: blob}) of the worktree, ignored files and .cascade excluded — the same scheme and the
    same hardening as cascade_worktree_sha (tests/lib/cascade.sh), so the two cannot drift (AC8)."""
    def run(args, env=None, inp=None):
        return subprocess.run(args, cwd=root, env=env, input=inp, capture_output=True, timeout=TIMEOUT)
    r = run(["git", "rev-parse", "--is-inside-work-tree"])
    if r.returncode != 0:
        raise NoKey("not a git worktree")
    gi = run(["git", "rev-parse", "--git-path", "index"]).stdout.decode().strip()
    objs = run(["git", "rev-parse", "--git-path", "objects"]).stdout.decode().strip()
    if not objs:
        raise NoKey("git has no object directory")
    gi = gi if os.path.isabs(gi) else os.path.join(root, gi)
    objs = os.path.realpath(objs if os.path.isabs(objs) else os.path.join(root, objs))
    tmp = tempfile.mkdtemp(prefix="bdd-verdicts-")
    try:
        os.mkdir(os.path.join(tmp, "objects"))
        if os.path.isfile(gi):
            shutil.copy2(gi, os.path.join(tmp, "index"))   # keeps the index mtime: git's racy-entry check needs it
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"),
                   GIT_OBJECT_DIRECTORY=os.path.join(tmp, "objects"), GIT_ALTERNATE_OBJECT_DIRECTORIES=objs)
        g = ["git", "-c", "core.trustctime=true", "-c", "core.checkStat=default", "-c", "core.fsmonitor=false",
             "-c", "core.ignoreStat=false", "-c", "core.untrackedCache=false"]
        flags = run(g + ["ls-files", "-z", "-v"], env).stdout.decode("utf-8", "surrogateescape").split("\0")
        lower = "\n".join(x[2:] for x in flags if len(x) > 2 and x[0].islower() and x[1] == " ")
        skip = "\n".join(x[2:] for x in flags if x.startswith("S "))
        if lower:
            run(g + ["update-index", "--no-assume-unchanged", "--stdin"], env, (lower + "\n").encode("utf-8", "surrogateescape"))
        if skip:
            run(g + ["update-index", "--no-skip-worktree", "--stdin"], env, (skip + "\n").encode("utf-8", "surrogateescape"))
        run(g + ["add", "-A", "--ignore-errors", "--", ".", ":(exclude).cascade"], env)
        w = run(g + ["write-tree"], env)
        tree = w.stdout.decode().strip()
        if w.returncode != 0 or not tree:
            raise NoKey("git could not fingerprint the worktree")
        ls = run(g + ["ls-files", "-s", "-z"], env)
        if ls.returncode != 0:
            raise NoKey("git could not list the worktree")
    except (OSError, subprocess.SubprocessError) as exc:
        raise NoKey(f"git failed ({exc.__class__.__name__})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    blobs: dict = {}
    for rec in ls.stdout.decode("utf-8", "surrogateescape").split("\0"):
        if "\t" not in rec:
            continue
        meta, path = rec.split("\t", 1)
        parts = meta.split()
        if len(parts) >= 2:
            blobs[path] = parts[1]
    return "t2:" + tree, blobs


def signed_values(text: str, pat: re.Pattern) -> str | None:
    """The last line matching pat inside <EDIT>; a {{template}} line is no decision."""
    val = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = pat.match(line)
            if m and "{{" not in line:
                val = m.group(1)
    return val


def digest(rows) -> str:
    h = hashlib.sha256()
    for path, blob in rows:
        h.update(path.encode("utf-8", "surrogateescape") + b"\0" + blob.encode() + b"\n")
    return h.hexdigest()


def sha_file(path: str) -> str:
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return "absent"


def first_line(args: list[str]) -> str:
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=60)
        return ((out.stdout or out.stderr).strip().splitlines() or [""])[0]
    except (OSError, subprocess.SubprocessError):
        return "absent"


def pack_version(root: str) -> str:
    for rel in (".claude-plugin/plugin.json",):
        try:
            return str(json.load(open(os.path.join(root, rel), encoding="utf-8")).get("version", ""))
        except (OSError, ValueError, AttributeError):
            pass
    try:
        for line in open(os.path.join(root, ".cascade", "manifest"), encoding="utf-8"):
            if line.startswith("version "):
                return line.split(None, 1)[1].strip()
    except OSError:
        pass
    return ""


def env_part(check: str, brk: str) -> dict:
    names = {k for k in os.environ if k.startswith(ENV_PREFIXES) and k not in ENV_SPEED} | set(ENV_NAMES)
    names |= set(REF.findall(check)) | set(REF.findall(brk))
    return {k: os.environ.get(k) for k in sorted(names)}


class Tree:
    """The fingerprinted worktree, sorted, for prefix lookups."""

    def __init__(self, root: str, blobs: dict):
        self.root = root
        self.blobs = blobs
        self.paths = sorted(blobs)

    def under(self, d: str) -> list[str]:
        pre = d.rstrip("/") + "/"
        i = bisect.bisect_left(self.paths, pre)
        out = []
        while i < len(self.paths) and self.paths[i].startswith(pre):
            out.append(self.paths[i])
            i += 1
        return out

    def guarded(self, guards: list[tuple[str, bool]]) -> set[str]:
        out: set[str] = set()
        for g, is_dir in guards:
            if g in self.blobs or os.path.isfile(os.path.join(self.root, g)):
                out.add(g)   # an ignored file a law names is hashed directly (U2)
            if is_dir or g not in self.blobs:
                out.update(self.under(g))
        return out

    def rows(self, paths) -> list[tuple[str, str]]:
        return [(p, self.blobs.get(p) or "f:" + sha_file(os.path.join(self.root, p))) for p in sorted(paths)]


def keys(root: str, envelope: str, cdir: str, rows: list[list[str]]) -> list[str]:
    try:
        text = open(envelope, encoding="utf-8", errors="replace").read()
    except OSError:
        text = ""
    laws = []
    for r in rows:
        if len(r) < 5 or r[0] != "L":
            continue
        laws.append({"index": r[1], "id": r[2], "check": r[3], "break": r[4], "path": r[5] if len(r) > 5 else ""})
    if not laws:
        return ["OFF\tno law has both a check and a break"]
    f1, blobs = fingerprint(root)
    tree = Tree(root, blobs)
    scope = "tree" if (signed_values(text, SCOPE) or "").strip() == "tree" else "declared"

    # The module map and the toolchain: fresh every run (§6). Doubt here is doubt about every key.
    entries: set[str] = set()
    for law in laws:
        toks = law["check"].split()
        if toks and toks[0] in ("./gradlew", "gradle"):
            entries.add(toks[0])
    projects: dict = {}
    if entries:
        projects, why = module_map(root, entries)
        if projects is None:
            raise NoKey(why)
    u = platform.uname()
    toolchain = {"uname": f"{u.system} {u.release} {u.machine}",
                 "bash": first_line(["bash", "--version"]), "python": sys.version.split()[0]}
    for entry in sorted(entries):
        try:
            r = subprocess.run([entry, "--version"], cwd=root, capture_output=True, text=True, timeout=TIMEOUT,
                               stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as exc:
            raise NoKey(f"{entry} --version could not run ({exc.__class__.__name__})")
        if r.returncode != 0:
            raise NoKey(f"{entry} --version failed (exit {r.returncode})")
        toolchain[entry] = r.stdout
    pack = {"version": pack_version(root), "scorers": {s: sha_file(os.path.join(HERE, s)) for s in SCORERS}}

    shared = [x for x in re.split(r"[\s,]+", signed_values(text, SHARED) or "") if x]
    for m in shared:
        if m not in projects:
            raise NoKey(f"shared module {m} is not in the module map")

    # Per law: what it declares.
    guards: dict = {}
    for law in laws:
        files = file_parts(root, law)
        mod, why = module_of(law["check"], root)
        gradle = law["check"].split()[:1] in (["./gradlew"], ["gradle"])
        mods = None
        if mod is not None:
            mods, why = closure(mod, projects)
            if mods is None:
                law["nokey"] = why
                continue
        law["files"], law["mods"] = files, mods
        law["unmapped"] = (not files and not mods) or (gradle and mod is None)

    nondoc = [p for p in tree.paths if not is_docs(p)]
    declared: set[str] = set()
    for law in laws:
        if "files" in law:
            declared |= tree.guarded(law["files"])
    glob_paths = {p for p in nondoc if is_build_logic(p)}
    for m in shared:
        glob_paths.update(tree.under(projects[m][0]))
    glob_paths.update(p for p in nondoc if p not in declared and owner(p, projects) is None)
    glob = {"files": digest(tree.rows(glob_paths)), "shared": shared, "scope": scope}

    out = [f"F\t{f1}"]
    for law in laws:
        if "nokey" in law:
            out.append(f"N\t{law['index']}\t{law['nokey']}")
            continue
        if not ID.match(law["id"]):
            out.append(f"N\t{law['index']}\tthe id is not D<number>")
            continue
        if scope == "tree" or law["unmapped"]:
            own = set(nondoc) | tree.guarded(law["files"])
        else:
            own = tree.guarded(law["files"])
            for m in sorted(law["mods"] or ()):
                d = projects[m][0]
                if d:
                    own.update(tree.under(d))
        obj = {"schema": SCHEMA, "id": law["id"], "check": law["check"], "break": law["break"],
               "own": digest(tree.rows(own)), "global": glob, "toolchain": toolchain, "pack": pack,
               "env": env_part(law["check"], law["break"])}
        key = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        out.append(f"K\t{law['index']}\t{key}\t{'hit' if lookup(cdir, law['id'], key) else 'miss'}")
    return out


def lookup(cdir: str, lid: str, key: str) -> bool:
    p = os.path.join(cdir, f"{lid}.json")
    if os.path.islink(p) or not os.path.isfile(p):
        return False
    try:
        entry = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(entry, dict) or entry.get("schema") != SCHEMA or entry.get("id") != lid:
        return False
    if entry.get("key") != key:
        return False
    return entry.get("verdict") == "GREEN"


def store(root: str, cdir: str, f1: str, rows: list[list[str]]) -> list[str]:
    todo = [(r[1], r[2]) for r in rows if len(r) >= 3 and r[0] == "S" and ID.match(r[1]) and re.fullmatch(r"[0-9a-f]{64}", r[2])]
    if not todo:
        return []
    f2, _ = fingerprint(root)
    if f2 != f1:
        return ["NOSTORE\tthe worktree changed while the laws ran"]
    os.makedirs(cdir, exist_ok=True)
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for lid, key in todo:
        fd, tmp = tempfile.mkstemp(prefix=f".{lid}-", dir=cdir)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"schema": SCHEMA, "id": lid, "key": key, "verdict": "GREEN", "at": at}, fh)
        os.replace(tmp, os.path.join(cdir, f"{lid}.json"))
    return []


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ("keys", "store", "fingerprint"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 64
    rows = [ln.rstrip("\n").split("\t") for ln in sys.stdin] if sys.argv[1] != "fingerprint" else []
    try:
        if sys.argv[1] == "keys" and len(sys.argv) == 5:
            out = keys(sys.argv[2], sys.argv[3], sys.argv[4], rows)
        elif sys.argv[1] == "store" and len(sys.argv) == 5:
            out = store(sys.argv[2], sys.argv[3], sys.argv[4], rows)
        elif sys.argv[1] == "fingerprint" and len(sys.argv) == 3:
            out = [fingerprint(sys.argv[2])[0]]
        else:
            return 64
    except NoKey as exc:
        out = [("OFF" if sys.argv[1] != "store" else "NOSTORE") + f"\t{exc}"]
    except Exception as exc:   # noqa: BLE001 — any doubt is a miss, never a hit
        out = [("OFF" if sys.argv[1] != "store" else "NOSTORE") + f"\tthe cache failed ({exc.__class__.__name__}: {exc})"]
    for line in out:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
