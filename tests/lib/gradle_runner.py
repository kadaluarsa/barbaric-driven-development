#!/usr/bin/env python3
"""Prove passes for this hop's plain Gradle VALIDATOR lines from as few builds as possible (t62).

    { printf 'V\\t<i>\\t<line>\\n' ...; printf 'D\\t<in-force D# check>\\n' ...; } \\
        | gradle_runner.py <root> <envelope> <logdir> <from>

Considers only the SEGMENT that starts at line <from>: the longest run of consecutive lines it can batch. Lines
in a goal run in order, and a line may depend on what an earlier one did (a shell line that generates sources);
batching a Gradle line ahead of a shell line listed before it would change what it sees, so a segment never
reaches past a line this file does not take. Prints `<i>\\tPASS\\t<summary>` for each line of the segment it can
PROVE passes, then `S\\t<builds>\\t<seconds>` and `E\\t<last index of the segment>`.

It never prints FAIL. A line it does not prove runs alone in tests/loop.sh by the code path every line took
before t62, so every FAIL, and every case this file does not understand, is that path's verdict.

How a pass is proven (docs/cascade/05b-t62-loop-runners.md §2):
  * Only lines that are plain `./gradlew` / `gradle` calls with allowlisted options are taken, on a Gradle
    version tests/stress/gradle_runner.sh verified (AC7). Lines are grouped by entry command + global options;
    a build that would hold a single line is not run (that line runs alone).
  * Exact (default): a group is split into waves so that every test task runs with the line's OWN `--tests`
    filter. Merged (only when `- LOOP_GRADLE_MERGE: on` is the last such line inside an <EDIT> block of
    docs/cascade/envelope.md, both as committed at HEAD and in the working tree): filters on one task are
    unioned, except for lines equal to an in-force D# check, which keep exact waves.
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
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from signed import BLOCK   # noqa: E402  (sibling: tests/lib ships as one directory)

HERE = os.path.dirname(os.path.abspath(__file__))
INIT = os.path.join(HERE, "gradle_runner.init.gradle")
# The Gradle versions tests/stress/gradle_runner.sh passed on (AC7, 2026-10-19: 8.5, 8.14.3, 9.1.0; CI re-checks
# both ends): >= VERIFIED[0] and < VERIFIED[1]. Lines for any other version run alone, as before t62.
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
MERGE = re.compile(r"^\s*-\s*LOOP_GRADLE_MERGE:\s*(on|off)(?=\s|$)")
SUMMARY = re.compile(r"FAILURE: Build completed with (\d+) failures?|FAILURE: Build failed with an exception")


# --- which lines -------------------------------------------------------------------------------------------

def parse(line: str, root: str) -> dict | None:
    """A line the runner may take, as {entry, globals, sels:[(selector, filter set)]}; None = run it alone.
    A filter set is None (no --tests) or a sorted tuple of patterns, so equal sets compare equal. A qualified
    selector is normalized to start with ':' so `app:test` and `:app:test` are one task, not two."""
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
            sel = ":" + t if ":" in t and not t.startswith(":") else t
            if any(s == sel for s, _ in sels):
                return None                               # the same selector twice in one line
            sels.append([sel, []])
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


# --- what the human signed -------------------------------------------------------------------------------

def _envelopes(root: str) -> list[str]:
    """docs/cascade/envelope.md as committed at HEAD, and as it is in the working tree."""
    rel = "docs/cascade/envelope.md"
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=root, capture_output=True, text=True)
    try:
        work = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
    except OSError:
        work = ""
    return [head.stdout if head.returncode == 0 else "", work]


def _merge_decision(text: str) -> bool:
    """The last LOOP_GRADLE_MERGE line inside <EDIT> decides; a {{template}} line is no decision."""
    last = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = MERGE.match(line)
            if m and "{{" not in line:
                last = m.group(1)
    return last == "on"


def merge_signed(texts: list[str]) -> bool:
    # Signed (inside <EDIT>, which only a human can change) AND committed: if it is not in git it was not decided.
    return bool(texts) and all(_merge_decision(t) for t in texts)


def _shards_at_head(root: str, tmp: str) -> str:
    """docs/cascade/laws/*.md as committed at HEAD, copied into tmp/laws (t67). An empty dir when there are none."""
    d = os.path.join(tmp, "laws")
    os.makedirs(d, exist_ok=True)
    r = subprocess.run(["git", "ls-tree", "--name-only", "HEAD", "docs/cascade/laws/"], cwd=root,
                       capture_output=True, text=True)
    for rel in r.stdout.splitlines():
        if not rel.endswith(".md") or os.path.basename(rel) == "README.md":
            continue
        blob = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=root, capture_output=True)
        if blob.returncode == 0:
            with open(os.path.join(d, os.path.basename(rel)), "wb") as fh:
                fh.write(blob.stdout)
    return d


def law_checks(texts: list[str], extra: str, root: str = "") -> set[str] | None:
    """Every in-force D# check in any version of the laws we can see — the envelope and every shard (t67), as
    committed at HEAD and in the working tree: the exclusion only ever widens. None when the laws cannot be read
    (a duplicate id): the caller then merges nothing at all."""
    out: set[str] = set()
    work_shards = os.path.join(root, "docs", "cascade", "laws") if root else None
    runs: list[tuple[str, str | None]] = []
    if extra and os.path.isfile(extra):
        runs.append((extra, work_shards))
    tmp = tempfile.mkdtemp(prefix="bdd-laws-")
    try:
        head_shards = _shards_at_head(root, tmp) if root else None
        for k, t in enumerate(texts):
            p = os.path.join(tmp, f"envelope-{k}.md")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(t)
            runs.append((p, head_shards if k == 0 else work_shards))   # texts = [HEAD, worktree]
        for p, shards in runs:
            args = [sys.executable, "-B", os.path.join(HERE, "laws.py"), p, "--in-force"]
            if shards:
                args += ["--shards", shards]
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode != 0:
                return None
            for line in r.stdout.splitlines():
                f = line.split("|")
                if len(f) >= 3 and f[2].strip():
                    out.add(f[2].strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return out


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
    """The outer build's own summary, which Gradle prints last; a nested build's (TestKit) can come earlier."""
    found = list(SUMMARY.finditer(log))
    if not found:
        return None
    m = found[-1]
    return int(m.group(1)) if m.group(1) else 1


def resolve(sel: str, graph: dict) -> list[str]:
    if sel.startswith(":"):
        return [sel] if sel in graph else []
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


class Build:
    """One finished build's evidence, read once and shared by every line it might prove."""

    def __init__(self, sels: OrderedDict, outcomes: dict, graph: dict):
        self.outcomes, self.graph, self._xml = outcomes, graph, {}
        self.ran: dict = {}          # task -> the filter set it ran with in this build
        self.clash: set = set()      # tasks two selectors asked for with different filter sets
        for s, fs in sels.items():
            for t in resolve(s, graph):
                if self.ran.get(t, fs) != fs:
                    self.clash.add(t)
                self.ran[t] = fs

    def cases(self, d: str):
        if d not in self._xml:
            self._xml[d] = junit(d)
        return self._xml[d]

    def attributed(self, own: tuple | None, row: dict, outcome: tuple | None) -> bool:
        """A test task ran with a merged filter: would it have passed with only the line's own patterns?"""
        if own is None or outcome is None or not row["test"]:
            return False
        status, why = outcome
        if status == "FAILED":
            parts = [c.strip() for c in why.split(" | ") if c.strip()]
            if row["ignore"] or not any(c.startswith("There were failing tests") for c in parts):
                return False
            if not all(c.startswith(("Execution failed for task", "There were failing tests")) for c in parts):
                return False                              # e.g. a test JVM that crashed
        elif status not in OK:
            return False
        cases = self.cases(row["xml"])
        if cases is None:
            return False
        if row["fail_none"] and not any(surely(p, c, n) for p in own for c, n, _ in cases):
            return False                                  # alone: "No tests found for given includes"
        if not row["ignore"]:
            if status in OK and any(f for _, _, f in cases):
                return False                              # failing tests in a task that passed: not understood
            if any(f and could(p, c, n) for p in own for c, n, f in cases):
                return False                              # might be the line's own failure: run it alone
        return True

    def proven(self, p: dict) -> bool:
        own: dict = {}
        for s, fs in p["sels"]:
            tasks = resolve(s, self.graph)
            if not tasks:
                return False                              # unknown or abbreviated: Gradle resolves it, we do not
            for t in tasks:
                if own.get(t, fs) != fs:
                    return False
                own[t] = fs
        todo, seen = list(own), set()
        while todo:
            t = todo.pop()
            if t in seen:
                continue
            seen.add(t)
            row = self.graph.get(t)
            if row is None or t in self.clash:
                return False                              # two selectors, one task, two filters: not this line's run
            todo += row["deps"] + row["fin"]
            status = self.outcomes.get(t, ("",))[0]
            if t not in own:
                if row["test"] and self.ran.get(t) is not None:
                    return False                          # its own run would not have filtered this task
                if status not in OK:
                    return False
            elif self.ran.get(t) == own[t]:
                if status not in OK:
                    return False
            elif not self.attributed(own[t], row, self.outcomes.get(t)):
                return False
        return True


# --- main --------------------------------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) != 5 or not sys.argv[4].isdigit():
        return 64
    root, envelope, logdir, start = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    lines: dict[int, str] = {}
    given: set[str] = set()
    # One record per '\n', as loop.sh writes them: str.splitlines() would also break inside a line on \x0b,
    # \x1c, U+2028 and friends, and prove a shortened command under the full line's index.
    for raw in sys.stdin.read().split("\n"):
        p = raw.split("\t", 2)
        if p[0] == "V" and len(p) == 3 and p[1].isdigit():
            lines[int(p[1])] = p[2]
        elif p[0] == "D" and len(p) >= 2:
            given.add("\t".join(p[1:]).strip())

    gradlew_ok = verified(wrapper_version(root)) and os.access(os.path.join(root, "gradlew"), os.X_OK)
    segment: list[tuple[int, dict]] = []
    i = start
    while i in lines:
        p = parse(lines[i], root)
        if p is None or (p["entry"] == "./gradlew" and not gradlew_ok):
            break
        segment.append((i, p))
        i += 1
    if len(segment) < 2:
        print("S\t0\t0")
        print(f"E\t{start}")
        return 0
    end = segment[-1][0]

    groups: OrderedDict = OrderedDict()
    for i, p in segment:
        groups.setdefault((p["entry"], p["globals"]), []).append((i, p))
    texts = _envelopes(root)
    checks = law_checks(texts, envelope, root)
    # Laws that cannot be read (t67: a duplicate id) leave no exclusion to trust: merge nothing.
    signed = merge_signed(texts) and checks is not None
    checks = (checks or set()) | given
    out = os.path.join(root, ".cascade", "gradle")
    os.makedirs(out, exist_ok=True)
    parsed = dict(segment)
    passes: list[tuple[int, str]] = []
    builds, spent = 0, 0.0
    for g, ((entry, globals_), items) in enumerate(groups.items(), start=1):
        if signed:
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
            log_path = os.path.join(logdir, f"gradle-{start}-{g}-{w}.log")
            # Stable values only: these env vars are configuration-cache inputs of the user's build.
            env = dict(os.environ, BDD_GRADLE_OUT=out, BDD_GRADLE_GRAPH=graph_path,
                       BDD_GRADLE_RANGE=f"{VERIFIED[0]}:{VERIFIED[1]}")
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
            evidence = Build(build["sels"], outcomes, graph)
            rel = os.path.relpath(log_path, root)
            for i in build["lines"]:
                if evidence.proven(parsed[i]):
                    passes.append((i, f"gradle build ({took:.0f}s, {rel})"))
    for i, summary in sorted(passes):
        print(f"{i}\tPASS\t{summary}")
    print(f"S\t{builds}\t{spent:.0f}")
    print(f"E\t{end}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
