#!/usr/bin/env python3
"""Prove Xcode laws GREEN from one build per build key instead of two builds per law (t75 §4).

    { printf 'L\\t<index>\\t<id>\\t<check>\\t<break>\\n' ...; } | xcode_harness.py <root> <envelope file> <logdir>

Prints `<index>\\tGREEN` for each law it can PROVE is GREEN, then `S\\t<builds>\\t<seconds>`, and writes why every other
law was left alone to <logdir>/xcode-harness.tsv. It never prints RED, THEATER or UNPROVEN: a law it does not prove is
scored by tests/dsharp_strength.sh with its own two commands, exactly as before t75.

On only when `- DSHARP_XCODE_HARNESS: on` is the last such line inside <EDIT> of docs/cascade/envelope.md, at HEAD and
in the working tree; the laws came from that file; and DSHARP_HARNESS is not `off` (the merge gate always sets it).

Eligible: the `check:` is a line tests/lib/xcode_runner.py takes, with at least one -only-testing selector; the
`break:` is exactly `TEST_RUNNER_INV_MUTANT=<id> <check>` (Xcode passes only TEST_RUNNER_* variables to tests, E0); the
Xcode version is verified. A `break:` that patches code is not eligible.

GREEN when: the check run is a proven pass (xcode_runner.proven); the mutant run failed, its result bundle reads, and
every non-passing case is a plain `Failed` test case with no crash node; both runs ran the same test cases; every case
that failed in the mutant passed in the check; and the worktree fingerprint did not move across the two runs.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xcode_runner as xr   # noqa: E402  (sibling: tests/lib ships as one directory)

SWITCH = re.compile(r"^\s*-\s*DSHARP_XCODE_HARNESS:\s*(on|off)(?=\s|$)")
REL = "docs/cascade/envelope.md"


def switched_on(root: str, envelope: str) -> tuple[bool, str]:
    if os.environ.get("DSHARP_HARNESS", "") == "off":
        return False, "DSHARP_HARNESS=off"
    try:
        same = os.path.realpath(envelope) == os.path.realpath(os.path.join(root, REL))
    except OSError:
        same = False
    if not same:
        return False, f"the laws came from {envelope}, not {REL}"
    import gradle_tuning   # noqa: E402  (its signed() reads HEAD and the working tree, t69)
    if not gradle_tuning.signed(root, SWITCH):
        return False, "DSHARP_XCODE_HARNESS: on is not signed and committed"
    return True, ""


def eligible(lid: str, check: str, brk: str) -> tuple[dict | None, str]:
    p = xr.parse(check)
    if p is None:
        return None, "check: is not a plain `xcodebuild … test` line the runner takes"
    if not p["only"]:
        return None, "check: has no -only-testing selector"
    if brk != f"TEST_RUNNER_INV_MUTANT={lid} {check}":
        return None, f"break: is not `TEST_RUNNER_INV_MUTANT={lid} <check>`"
    return p, ""


def failures_only_tests(bundle: str) -> bool:
    """The mutant's non-passing results are test-case failures, not a crash or a launch failure."""
    try:
        r = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle],
                           capture_output=True, text=True, timeout=120)
        data = json.loads(r.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return False
    crash = []

    def walk(n: dict) -> None:
        if str(n.get("name") or "").startswith("Crash:"):
            crash.append(n)
        for c in n.get("children") or []:
            if isinstance(c, dict):
                walk(c)
    for n in data.get("testNodes") or []:
        if isinstance(n, dict):
            walk(n)
    return not crash


def main() -> int:
    if len(sys.argv) != 4:
        return 64
    root, envelope, logdir = sys.argv[1:4]
    laws = []
    for raw in sys.stdin.read().split("\n"):
        f = raw.split("\t")
        if len(f) == 5 and f[0] == "L" and f[1].isdigit():
            laws.append((int(f[1]), f[2], f[3], f[4]))
    on, _ = switched_on(root, envelope)
    if not on or not laws:
        print("S\t0\t0")
        return 0
    os.makedirs(logdir, exist_ok=True)
    notes = open(os.path.join(logdir, "xcode-harness.tsv"), "w", encoding="utf-8")
    version = xr.xcode_version()
    if not xr.verified(version):
        for i, lid, _, _ in laws:
            notes.write(f"{i}\t{lid}\tXcode {version or '?'} is not verified ({xr.VERIFIED[0]} to below {xr.VERIFIED[1]})\n")
        print("S\t0\t0")
        return 0
    try:
        timeout = max(1, int(os.environ.get("BDD_XCODE_TIMEOUT") or xr.TIMEOUT))
    except ValueError:
        timeout = xr.TIMEOUT
    run = xr.runner(timeout)
    keys: dict = {}
    greens: list[int] = []
    builds, spent = 0, 0.0
    env_plain = {k: v for k, v in os.environ.items() if k not in ("INV_MUTANT", "TEST_RUNNER_INV_MUTANT")}
    for i, lid, check, brk in laws:                       # one at a time: laws never run concurrently
        p, why = eligible(lid, check, brk)
        if p is None:
            notes.write(f"{i}\t{lid}\t{why}\n")
            continue
        k = keys.setdefault(p["key"], xr.Key(root, p["key"], logdir, version))
        fp = xr.fingerprint(root)
        if not fp or k.unstable or k.marked_unstable(fp):
            notes.write(f"{i}\t{lid}\tno trustworthy build (no fingerprint, or the build changes the worktree)\n")
            continue
        if not k.ready(fp):
            ok, took = k.build(run, fp)
            builds += 1
            spent += took
            if not ok:
                notes.write(f"{i}\t{lid}\t{k.why}\n")
                continue
        t0 = time.time()
        rc_c, cases_c, _, _ = xr.test_line(k, p, i, run, timeout, env_plain, "-check")
        rc_m, cases_m, _, _ = xr.test_line(k, p, i, run, timeout, dict(env_plain, TEST_RUNNER_INV_MUTANT=lid), "-mutant")
        spent += time.time() - t0
        ok, why = xr.proven(rc_c, cases_c, p)
        if ok and xr.fingerprint(root) != fp:
            ok, why = False, "the worktree changed across the two runs"
        if ok and (rc_m in (0, None) or cases_m is None):
            ok, why = False, f"mutant run {'timed out' if rc_m is None else 'passed' if rc_m == 0 else 'unreadable'}"
        if ok and sorted(c for c, _ in cases_m) != sorted(c for c, _ in cases_c):
            ok, why = False, "the mutant ran other test cases than the check"
        if ok:
            failed = [c for c, r in cases_m if r == "Failed"]
            odd = [c for c, r in cases_m if r != "Failed" and r not in xr.OK_RESULTS]
            if not failed or odd:
                ok, why = False, "the mutant failed with no failing test case" if not failed else "a mutant case is neither passed nor failed"
            elif not failures_only_tests(os.path.join(k.dir, f"line-{i}-mutant.xcresult")):
                ok, why = False, "the mutant crashed the test host"
        if ok:
            greens.append(i)
        notes.write(f"{i}\t{lid}\t{'GREEN' if ok else why}\n")
    for i in sorted(greens):
        print(f"{i}\tGREEN")
    print(f"S\t{builds}\t{spent:.0f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
