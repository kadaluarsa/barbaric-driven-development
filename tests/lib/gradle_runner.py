#!/usr/bin/env python3
"""Prove passes for this hop's plain Gradle VALIDATOR lines from as few builds as possible (t62).

    { printf 'V\\t<i>\\t<line>\\n' ...; printf 'D\\t<in-force D# check>\\n' ...; } \\
        | gradle_runner.py <root> <envelope> <logdir>

Prints `<i>\\tPASS\\t<summary>` for each line it can PROVE passes, then `S\\t<builds>\\t<seconds>` once.
It never prints FAIL. A line it does not prove runs alone in tests/loop.sh by the code path every line took
before t62, so every FAIL, and every case this file does not understand, is that path's verdict.

How a pass is proven (docs/cascade/05b-t62-loop-runners.md §2):
  * Only lines that are plain `./gradlew` / `gradle` calls with allowlisted options are taken. Lines are grouped
    by entry command + global options; a build that would hold a single line is not run (that line runs alone).
  * Exact (default, any Gradle with the init script's API): a group is split into waves so that every test task
    runs with the line's OWN `--tests` filter. Merged (only with `- LOOP_GRADLE_MERGE: on` signed inside an
    <EDIT> block of the envelope, and only on a verified Gradle version read from the wrapper): filters on one
    task are unioned, except for lines equal to an in-force D# check, which keep exact waves.
  * Each build runs with `--continue -I gradle_runner.init.gradle`; the init script records every task's
    outcome and the task graph. A line passes when every task its own run would include succeeded, the
    build's failure count equals its task failures, no task in its graph ran with someone else's filter,
    and — for a merged test task — the JUnit XML shows the line's own patterns surely selected a test and
    could not have selected any failing one.
The assumption a batched pass rests on (A1): a task's outcome depends on its declared inputs and the tasks it
depends on, not on which other tasks share the build — the premise of Gradle's own up-to-date checks.
"""
from __future__ import annotations

import glob
import hashlib
import os
import re
import shlex
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from signed import BLOCK   # noqa: E402  (sibling: tests/lib ships as one directory)

INIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gradle_runner.init.gradle")
# Exact mode needs only stable public API (task outcome events, the task graph), present since FLOOR; on any
# version where the init script loads it proves passes or proves nothing, so a newer Gradle fails toward slow,
# never toward wrong. Merged mode also reads Gradle's --tests matching and JUnit XML, so it is limited to the
# versions tests/stress/gradle_runner.sh passed on (AC7, 2026-10-19: 8.5, 8.14.3, 9.1.0; CI re-checks both ends):
# >= VERIFIED[0] and < VERIFIED[1]; elsewhere it plans exact waves instead.
FLOOR = "6.1"
VERIFIED = ("8.5", "9.2")

ZERO = {"-q", "-w", "-i", "-d", "-s", "-S", "--quiet", "--warn", "--info", "--debug", "--stacktrace",
        "--full-stacktrace", "--offline", "--refresh-dependencies", "--rerun-tasks", "--build-cache",
        "--no-build-cache", "--configuration-cache", "--no-configuration-cache", "--parallel", "--no-parallel",
        "--daemon", "--no-daemon", "--continue", "--scan", "--no-scan", "--watch-fs", "--no-watch-fs"}
ONE = {"-x", "--exclude-task", "--console", "--warning-mode", "--max-workers", "-D", "-P", "--system-prop",
       "--project-prop"}
EQ = ("--console=", "--warning-mode=", "--max-workers=")
SELECTOR = re.compile(r"^:?[A-Za-z0-9_.\-]+(:[A-Za-z0-9_.\-]+)*$")
OK = ("SUCCESS", "UP-TO-DATE", "FROM-CACHE", "SKIPPED")
METHOD = re.compile(r"^([A-Za-z_$][\w$]*)(?:\(.*\)|\[.*\])?$")
MERGE = re.compile(r"^\s*-\s*LOOP_GRADLE_MERGE:\s*on\b")


# --- which lines -------------------------------------------------------------------------------------------

def parse(line: str, root: str) -> dict | None:
    """A line the runner may take, as {entry, globals, sels:[(selector, filter set)]}; None = run it alone.
    A filter set is None (no --tests) or a sorted tuple of patterns, so equal sets compare equal."""
    if any(c in line for c in "$`\\{}#!"):
        return None
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return None
    if not toks or toks[0] not in ("./gradlew", "gradle"):
        return None
    for t in toks:
        if t and all(c in "();<>|&" for c in t):
            return None                                   # a shell operator: eval would run more than Gradle
        if t.startswith("~"):
            return None
        if any(c in t for c in "*?[") and glob.glob(os.path.join(root, t)):
            return None                                   # eval would expand it to a file name; we would not
    glob_opts: list[str] = []
    sels: list[list] = []
    i = 1
    while i < len(toks):
        t = toks[i]
        if t == "--tests":
            if not sels or i + 1 >= len(toks) or toks[i + 1].startswith("-"):
                return None
            sels[-1][1].append(toks[i + 1])
            i += 2
        elif t in ZERO or t.startswith(EQ) or re.match(r"^-[DP].+", t):
            glob_opts.append(t)
            i += 1
        elif t in ONE:
            if i + 1 >= len(toks):
                return None
            glob_opts += [t, toks[i + 1]]
            i += 2
        elif t.startswith("-") or not SELECTOR.match(t):
            return None
        else:
            if any(s == t for s, _ in sels):
                return None                               # the same selector twice in one line
            sels.append([t, []])
            i += 1
    if not sels:
        return None
    return {"entry": toks[0], "globals": tuple(glob_opts),
            "sels": [(s, tuple(sorted(set(p))) if p else None) for s, p in sels]}


def wrapper_version(root: str) -> str | None:
    try:
        text = open(os.path.join(root, "gradle", "wrapper", "gradle-wrapper.properties"), encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"gradle-(\d+\.\d+(?:\.\d+)?)-(?:bin|all)\.zip", text)
    return m.group(1) if m else None


def _version_key(v: str) -> tuple:
    return tuple(int(x) for x in v.split("."))


def verified(version: str | None) -> bool:
    return bool(version) and _version_key(VERIFIED[0]) <= _version_key(version) < _version_key(VERIFIED[1])


def below_floor(version: str | None) -> bool:
    """Known to lack the init script's API. An unknown version is tried: a failed build proves nothing."""
    return bool(version) and _version_key(version) < _version_key(FLOOR)


def merge_signed(envelope: str) -> bool:
    try:
        text = open(envelope, encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    return any(MERGE.match(l) and "{{" not in l for b in BLOCK.findall(text) for l in b.splitlines())


# --- which builds ------------------------------------------------------------------------------------------

def waves(items: list) -> list[dict]:
    """Exact: each line joins the first build where none of its selectors already runs another filter set."""
    out: list[dict] = []
    for i, p in items:
        for w in out:
            if all(w["sels"].get(s, fs) == fs for s, fs in p["sels"]):
                break
        else:
            w = {"sels": OrderedDict(), "lines": []}
            out.append(w)
        for s, fs in p["sels"]:
            w["sels"].setdefault(s, fs)
        w["lines"].append(i)
    return out


def merged(items: list) -> dict:
    """Merged: one build; a selector runs unfiltered if any line wants it unfiltered, else the union."""
    want: OrderedDict = OrderedDict()
    for _, p in items:
        for s, fs in p["sels"]:
            want.setdefault(s, []).append(fs)
    sels = OrderedDict((s, None if any(f is None for f in fss) else tuple(sorted({x for f in fss for x in f})))
                       for s, fss in want.items())
    return {"sels": sels, "lines": [i for i, _ in items]}


def command(entry: str, globals_: tuple, sels: OrderedDict) -> list[str]:
    cmd = [entry, *globals_]
    if "--continue" not in globals_:
        cmd.append("--continue")
    cmd += ["-I", INIT]
    for s, fs in sels.items():
        cmd.append(s)
        for p in fs or ():
            cmd += ["--tests", p]
    return cmd


# --- what a build proved -----------------------------------------------------------------------------------

def read_outcomes(path: str) -> dict:
    out = {}
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2:
                out[p[0]] = (p[1], p[2] if len(p) > 2 else "")
    except OSError:
        pass
    return out


def read_graph(path: str) -> dict | None:
    g = {}
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            p = line.rstrip("\n").split("\t")
            if len(p) != 7:
                continue
            g[p[0]] = {"test": p[1] == "test", "xml": p[2], "ignore": p[3] == "true",
                       "fail_none": p[4] != "false", "deps": [d for d in p[5].split(",") if d],
                       "fin": [d for d in p[6].split(",") if d]}
    except OSError:
        return None
    return g or None


def failure_count(log: str) -> int | None:
    m = re.search(r"Build completed with (\d+) failures?", log)
    if m:
        return int(m.group(1))
    return 1 if "Build failed with an exception" in log else None


def resolve(sel: str, graph: dict) -> list[str]:
    if ":" in sel:
        path = sel if sel.startswith(":") else ":" + sel
        return [path] if path in graph else []
    return [t for t in graph if t.rsplit(":", 1)[-1] == sel]


def junit(d: str) -> list | None:
    if not d or not os.path.isdir(d):
        return None
    cases = []
    for f in sorted(glob.glob(os.path.join(d, "*.xml"))):
        try:
            root = ET.parse(f).getroot()
        except (ET.ParseError, OSError):
            return None
        for tc in root.iter("testcase"):
            failed = tc.find("failure") is not None or tc.find("error") is not None
            cases.append((tc.get("classname") or "", tc.get("name") or "", failed))
    return cases


def _rx(p: str):
    return re.compile("^" + ".*".join(re.escape(x) for x in p.split("*")) + "$")


def _subject(p: str, cls: str) -> str:
    # Gradle matches a pattern that starts with an upper-case letter against the simple class name.
    return cls.rsplit(".", 1)[-1] if p[:1].isupper() else cls


def _method(name: str) -> str | None:
    m = METHOD.match(name)
    return m.group(1) if m else None


def surely(p: str, cls: str, name: str) -> bool:
    """Gradle certainly selects this test for pattern p. Used only to prove a line matched something, so it
    may be narrower than Gradle, never wider."""
    r, m = _rx(p), _method(name)
    return bool(r.match(_subject(p, cls)) or (m and r.match(_subject(p, cls) + "." + m)))


def could(p: str, cls: str, name: str) -> bool:
    """Gradle might select this test for pattern p. Used only to ask whether a failing test might be the
    line's, so it may be wider than Gradle, never narrower."""
    if surely(p, cls, name):
        return True
    outer = cls.split("$", 1)[0]
    if _rx(p).match(_subject(p, outer)):
        return True                                       # a class pattern also runs its nested classes
    if _method(name) is None and ("*" in p or "." in p):
        return True                                       # a display name hides the method a pattern may match
    if "." in p:
        q = _rx(p.rsplit(".", 1)[0])
        if q.match(_subject(p, cls)) or q.match(_subject(p, outer)):
            return True
    return False


def attributed(own: tuple | None, row: dict, outcome: tuple | None) -> bool:
    """A test task ran with a merged filter: would it have passed with only the line's own patterns?"""
    if own is None or outcome is None or not row["test"]:
        return False
    status, why = outcome
    if status == "FAILED":
        parts = [c.strip() for c in why.split(" | ") if c.strip()]
        if row["ignore"] or not any(c.startswith("There were failing tests") for c in parts):
            return False
        if not all(c.startswith(("Execution failed for task", "There were failing tests")) for c in parts):
            return False                                  # e.g. a test JVM that crashed
    elif status not in OK:
        return False
    cases = junit(row["xml"])
    if cases is None:
        return False
    if row["fail_none"] and not any(surely(p, c, n) for p in own for c, n, _ in cases):
        return False                                      # alone: "No tests found for given includes"
    if not row["ignore"]:
        if status in OK and any(f for _, _, f in cases):
            return False                                  # failing tests in a task that passed: not understood
        if any(f and could(p, c, n) for p in own for c, n, f in cases):
            return False                                  # might be the line's own failure: run it alone
    return True


def proven(p: dict, build: dict, outcomes: dict, graph: dict) -> bool:
    own: dict = {}
    for s, fs in p["sels"]:
        tasks = resolve(s, graph)
        if not tasks:
            return False                                  # unknown or abbreviated: Gradle resolves it, we do not
        for t in tasks:
            if own.get(t, fs) != fs:
                return False
            own[t] = fs
    ran: dict = {}
    for s, fs in build["sels"].items():
        for t in resolve(s, graph):
            if ran.get(t, fs) != fs:
                return False                              # two selectors, one task, two filters
            ran[t] = fs
    todo, seen = list(own), set()
    while todo:
        t = todo.pop()
        if t in seen:
            continue
        seen.add(t)
        row = graph.get(t)
        if row is None:
            return False
        todo += row["deps"] + row["fin"]
        status = outcomes.get(t, ("",))[0]
        if t not in own:
            if row["test"] and ran.get(t) is not None:
                return False                              # its own run would not have filtered this task
            if status not in OK:
                return False
        elif ran.get(t) == own[t]:
            if status not in OK:
                return False
        elif not attributed(own[t], row, outcomes.get(t)):
            return False
    return True


# --- main --------------------------------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) != 4:
        return 64
    root, envelope, logdir = sys.argv[1:4]
    lines: dict[int, str] = {}
    checks: set[str] = set()
    for raw in sys.stdin.read().splitlines():
        p = raw.split("\t", 2)
        if p[0] == "V" and len(p) == 3 and p[1].isdigit():
            lines[int(p[1])] = p[2]
        elif p[0] == "D" and len(p) >= 2:
            checks.add("\t".join(p[1:]).strip())

    wrapper = wrapper_version(root)
    gradlew_ok = not below_floor(wrapper) and os.access(os.path.join(root, "gradlew"), os.X_OK)
    groups: OrderedDict = OrderedDict()
    for i, line in sorted(lines.items()):
        p = parse(line, root)
        if p is None or (p["entry"] == "./gradlew" and not gradlew_ok):
            continue
        groups.setdefault((p["entry"], p["globals"]), []).append((i, p))
    if not groups:
        print("S\t0\t0")
        return 0

    signed = merge_signed(envelope)
    out = os.path.join(root, ".cascade", "gradle")
    os.makedirs(out, exist_ok=True)
    parsed = {i: p for items in groups.values() for i, p in items}
    passes: list[tuple[int, str]] = []
    builds, spent = 0, 0.0
    for g, ((entry, globals_), items) in enumerate(groups.items(), 1):
        merge = signed and entry == "./gradlew" and verified(wrapper)
        if merge:
            laws = [(i, p) for i, p in items if lines[i].strip() in checks]
            rest = [(i, p) for i, p in items if lines[i].strip() not in checks]
            plan = ([merged(rest)] if rest else []) + waves(laws)
        else:
            plan = waves(items)
        # A build holding one line saves nothing: that line runs alone, and a failure is not paid for twice.
        plan = [b for b in plan if len(b["lines"]) > 1]
        for w, build in enumerate(plan, 1):
            cmd = command(entry, globals_, build["sels"])
            key = hashlib.sha256("\0".join(cmd).encode()).hexdigest()[:16]
            graph_path = os.path.join(out, f"graph-{key}.tsv")
            outcomes_path = os.path.join(out, "outcomes.tsv")
            try:
                os.unlink(outcomes_path)
            except OSError:
                pass
            log_path = os.path.join(logdir, f"gradle-{g}-{w}.log")
            env = dict(os.environ, BDD_GRADLE_OUT=out, BDD_GRADLE_GRAPH=graph_path)
            env.pop("BDD_GRADLE_RANGE", None)
            if merge:
                env["BDD_GRADLE_RANGE"] = f"{VERIFIED[0]}:{VERIFIED[1]}"
            t0 = time.time()
            try:
                with open(log_path, "w") as fh:
                    rc = subprocess.run(cmd, cwd=root, env=env, stdout=fh, stderr=subprocess.STDOUT,
                                        stdin=subprocess.DEVNULL).returncode
            except OSError:
                continue                                  # no such executable: its lines run alone, and say so there
            took = time.time() - t0
            builds += 1
            spent += took
            outcomes = read_outcomes(outcomes_path)
            graph = read_graph(graph_path)
            if graph is None or not outcomes:
                continue
            if rc != 0:
                log = open(log_path, encoding="utf-8", errors="replace").read()
                if failure_count(log) != sum(1 for s, _ in outcomes.values() if s == "FAILED"):
                    continue                              # a failure that is not a task's: prove nothing here
            rel = os.path.relpath(log_path, root)
            for i in build["lines"]:
                if proven(parsed[i], build, outcomes, graph):
                    passes.append((i, f"gradle build {g}.{w} ({took:.0f}s, {rel})"))
    for i, summary in sorted(passes):
        print(f"{i}\tPASS\t{summary}")
    print(f"S\t{builds}\t{spent:.0f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
