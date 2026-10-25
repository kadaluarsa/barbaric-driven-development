#!/usr/bin/env python3
"""Did a test command that exited 0 execute a test? (t79) — one reader for the loop, the suite and the laws.

usage: test_count.py ROOT START LOG COMMAND
  START    the run's start, seconds since the epoch, taken before the command ran
  LOG      the command's own output (or /dev/null)
Prints one line:
  ran <n>              n tests executed (skipped ones are not executed)
  none <why>           a recognised runner executed nothing — or a filter / target matched no executed test
  uninspected <why>    not a recognised runner, or nothing this run left can be read: never a FAIL

Gradle (measured in E0 on 8.14.3): a test task that executed rewrites build/test-results/<task>/ — XML for each class
it ran and binary/ always, so a lenient misspelled filter leaves fresh binary/ and no XML (zero executed). An
UP-TO-DATE, FROM-CACHE or SKIPPED task rewrites nothing, so its old files are no evidence either way. Filters are
matched with t62's wide matcher (`could`): it may over-match, never under-match, so a run that executed tests is never
read as zero. Xcode (measured on 27): a misspelled -only-testing exits 0 and its result bundle reports
totalTestCount 0; -quiet on macOS prints no `Executed` line, so the bundle comes first and the log second.
"""
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gradle_runner import ONE, could   # noqa: E402  (sibling: tests/lib ships as one directory)

TEST_TASK = re.compile(r"(^test$|Test$|^check$)")
XCTEST = re.compile(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?\d+ failures?")
SWIFT_TESTING = re.compile(r"Test run with (\d+) tests?\b")
EXECUTED = ("Passed", "Failed", "Expected Failure")


def fresh(path: str, start: float) -> bool:
    try:
        return os.path.getmtime(path) >= start
    except OSError:
        return False


# --- Gradle --------------------------------------------------------------------------------------------------

def gradle_tasks(toks: list[str]) -> list[tuple[str, list[str]]]:
    """(task selector, its --tests filters) for each test task the command names; --tests binds to the task before."""
    tasks: list[tuple[str, list[str]]] = []
    i = 1
    while i < len(toks):
        t = toks[i]
        if t == "--tests" and i + 1 < len(toks):
            if tasks:
                tasks[-1][1].append(toks[i + 1])
            i += 2
            continue
        if t.startswith("--tests="):
            if tasks:
                tasks[-1][1].append(t.split("=", 1)[1])
        elif t in ONE:
            i += 2
            continue
        elif not t.startswith("-") and TEST_TASK.search(t.rsplit(":", 1)[-1]):
            tasks.append((t, []))
        i += 1
    return tasks


def result_dirs(root: str, sel: str) -> list[str]:
    name = sel.rsplit(":", 1)[-1]
    name = "test" if name == "check" else name
    if sel.startswith(":") and sel.count(":") > 1:
        mod = sel.strip(":").rsplit(":", 1)[0].replace(":", os.sep)
        return [os.path.join(root, mod, "build", "test-results", name)]
    if sel.startswith(":"):
        return [os.path.join(root, "build", "test-results", name)]
    found = []   # a bare name runs in every project that has the task
    for depth in ("", "*", os.path.join("*", "*"), os.path.join("*", "*", "*")):
        found += glob.glob(os.path.join(root, depth, "build", "test-results", name))
    return sorted(set(found))


def cases(d: str, start: float) -> list[tuple[str, str, bool]]:
    """(class, name, skipped) for every testcase in this run's XML of one results directory."""
    out = []
    for f in sorted(glob.glob(os.path.join(d, "*.xml"))):
        if not fresh(f, start):
            continue
        try:
            for tc in ET.parse(f).getroot().iter("testcase"):
                out.append((tc.get("classname") or "", tc.get("name") or "", tc.find("skipped") is not None))
        except (ET.ParseError, OSError):
            continue
    return out


def ran_this_run(d: str, start: float) -> bool:
    for base, _dirs, files in os.walk(d):
        if any(fresh(os.path.join(base, f), start) for f in files):
            return True
    return False


def gradle_verdict(root: str, start: float, cmd: str, toks: list[str]) -> str:
    tasks = gradle_tasks(toks)
    if not tasks:
        return "uninspected no test task named"
    total, seen_run = 0, False
    for sel, filters in tasks:
        dirs = [d for d in result_dirs(root, sel) if os.path.isdir(d)]
        live = [d for d in dirs if ran_this_run(d, start)]
        if not live:
            continue
        seen_run = True
        executed = [(c, n) for d in live for c, n, skipped in cases(d, start) if not skipped]
        total += len(executed)
        for f in filters:
            if not any(could(f, c, n) for c, n in executed):
                return f"none filter matched no executed test: {f}"
    if not seen_run:
        return "uninspected results predate the run (up-to-date, cached or skipped) or no results directory"
    return f"ran {total}" if total else "none ran no tests"


# --- Xcode ---------------------------------------------------------------------------------------------------

def opt(toks: list[str], name: str) -> str:
    for i, t in enumerate(toks):
        if t == name and i + 1 < len(toks):
            return toks[i + 1]
    return ""


def bundle_for(root: str, start: float, toks: list[str]) -> str:
    named = opt(toks, "-resultBundlePath")
    if named:
        p = named if os.path.isabs(named) else os.path.join(root, named)
        return p if os.path.isdir(p) and fresh(p, start) else ""
    dd = opt(toks, "-derivedDataPath")
    if dd:
        pattern = os.path.join(dd if os.path.isabs(dd) else os.path.join(root, dd), "Logs", "Test", "*.xcresult")
    else:
        if int(os.environ.get("DSHARP_JOBS", "1") or "1") > 1:
            return ""   # laws run concurrently: the newest bundle may be another law's
        base = os.environ.get("BDD_DERIVED_DATA") or os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
        pattern = os.path.join(base, "*", "Logs", "Test", "*.xcresult")
    found = [p for p in glob.glob(pattern) if fresh(p, start)]
    return max(found, key=os.path.getmtime) if found else ""


def xcresult(bundle: str, kind: str):
    try:
        r = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle],
                           capture_output=True, text=True, timeout=120)
        return json.loads(r.stdout) if r.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def target_ran(nodes: list, target: str) -> bool:
    """Has the -only-testing target (Bundle[/Suite[/method]]) at least one executed test case under it?"""
    parts = target.split("/")

    def cases_under(n):
        if n.get("nodeType") == "Test Case":
            yield n
        for c in n.get("children", []) or []:
            yield from cases_under(c)

    def find(ns, want, depth):
        for n in ns:
            name, kind = n.get("name") or "", n.get("nodeType") or ""
            if depth == 0 and kind.endswith("test bundle") and name == want[0]:
                yield n
            elif depth == 1 and kind == "Test Suite" and name == want[1]:
                yield n
            elif depth == 2 and kind == "Test Case" and name.split("(")[0] == want[2].split("(")[0]:
                yield n
            else:
                yield from find(n.get("children", []) or [], want, depth)

    level = list(nodes)
    for depth in range(len(parts)):
        level = list(find(level, parts, depth))
        if not level:
            return False
    return any(c.get("result") in EXECUTED for n in level for c in cases_under(n))


def xcode_verdict(root: str, start: float, log: str, toks: list[str]) -> str:
    targets = [t.split(":", 1)[1] for t in toks if t.startswith("-only-testing:")]
    b = bundle_for(root, start, toks)
    summary = xcresult(b, "summary") if b else None
    if summary is not None:
        executed = int(summary.get("totalTestCount") or 0) - int(summary.get("skippedTests") or 0)
        if executed <= 0:
            return "none ran no tests"
        if targets:
            tree = xcresult(b, "tests")
            if tree is not None:
                for t in targets:
                    if not target_ran(tree.get("testNodes", []) or [], t):
                        return f"none -only-testing target matched no executed test: {t}"
        return f"ran {executed}"
    try:
        text = open(log, encoding="utf-8", errors="replace").read() if log else ""
    except OSError:
        text = ""
    xc, st = XCTEST.findall(text), SWIFT_TESTING.findall(text)
    if not xc and not st:
        return "uninspected no result bundle and no test count in the log"
    n = 0
    if xc:
        total, skipped = xc[-1]
        n += int(total) - int(skipped or 0)
    if st:
        n += int(st[-1])
    return f"ran {n}" if n > 0 else "none ran no tests"


def verdict(root: str, start: float, log: str, cmd: str) -> str:
    try:
        toks = shlex.split(cmd, comments=True)
    except ValueError:
        return "uninspected the command could not be read"
    if not toks:
        return "uninspected empty command"
    exe = os.path.basename(toks[0])
    if exe in ("gradlew", "gradle"):
        return gradle_verdict(root, start, cmd, toks)
    if exe == "xcodebuild" and ("test" in toks or "test-without-building" in toks):
        return xcode_verdict(root, start, log, toks)
    return "uninspected not a recognised test runner"


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 64
    root, start, log, cmd = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
    print(verdict(root, start, log, cmd))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
