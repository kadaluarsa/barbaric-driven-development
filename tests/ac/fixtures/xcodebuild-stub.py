#!/usr/bin/env python3
"""A stand-in for `xcodebuild` and `xcrun` in t75's AC tests, so CI proves the Xcode runner's logic without Xcode.

Invoked as `xcodebuild …` or `xcrun …` (STUB_AS, set by the wrapper). It reads `xcode-stub.json` in the working
directory and plays the behaviour E0/E0b measured on Xcode 27.0 (docs/cascade/05b-t75-xcode-runner.md):

  * `-version` prints `Xcode <version>`.
  * `build-for-testing -derivedDataPath DD` snapshots the watched source files into DD (the binary IS that snapshot)
    and writes a host app's Info.plist; `test-without-building` then runs against the snapshot, not the tree — a stale
    binary after an edit, exactly as E0 measured. `test` builds and runs against the tree.
  * Tests a call selects run in ONE process: a case listed in `pollutedBy` fails when its polluter ran in the same call.
  * Only `TEST_RUNNER_INV_MUTANT` reaches a test (E0); a plain `INV_MUTANT` is ignored.
  * `-resultBundlePath R` writes R/tests.json in the shape `xcresulttool get test-results tests` prints.
  * `xcrun xcresulttool get test-results tests --path R` prints it; `xcrun simctl terminate D B` is logged.

Scenario keys: version, cases ["Target/Class/method"], fail [case], failIfSource {case: "path:substring"},
mutantFails {id: [case]}, crash [case], hang [case] (sleeps STUB_HANG_S, default 30, after its tests), pollutedBy
{case: polluting case}, compileError (bool), buildWrites (a path the build appends to). Every call appends its argv
to $STUB_COUNT.
"""
from __future__ import annotations

import json
import os
import plistlib
import sys
import time


def log(args: list[str]) -> None:
    if os.environ.get("STUB_COUNT"):
        with open(os.environ["STUB_COUNT"], "a") as fh:
            fh.write(" ".join(args) + "\n")


def scen() -> dict:
    try:
        return json.load(open("xcode-stub.json", encoding="utf-8"))
    except OSError:
        return {}


def sources(s: dict) -> dict:
    out = {}
    for rule in s.get("failIfSource", {}).values():
        path = rule.split(":", 1)[0]
        try:
            out[path] = open(path, encoding="utf-8").read()
        except OSError:
            out[path] = ""
    return out


def run_tests(s: dict, only: list[str], skip: list[str], src: dict, bundle: str | None) -> int:
    def under(c: str, sel: str) -> bool:
        return c == sel or c.startswith(sel + "/")
    chosen = [c for c in s.get("cases", []) if (not only or any(under(c, o) for o in only))
              and not any(under(c, k) for k in skip)]
    mutant = os.environ.get("TEST_RUNNER_INV_MUTANT", "")
    results = {}
    for c in chosen:
        bad = c in s.get("fail", []) or c in s.get("mutantFails", {}).get(mutant, [])
        rule = s.get("failIfSource", {}).get(c)
        if rule:
            path, needle = rule.split(":", 1)
            bad = bad or needle in src.get(path, "")
        polluter = s.get("pollutedBy", {}).get(c)
        if polluter and polluter in chosen:
            bad = True
        results[c] = "Crash" if c in s.get("crash", []) else ("Failed" if bad else "Passed")
    for c, r in results.items():
        print(f"Test Case '{c}' {'passed' if r == 'Passed' else 'failed'}")
    if bundle:
        os.makedirs(bundle, exist_ok=True)
        targets: dict = {}
        for c, r in results.items():
            t, cls, meth = c.split("/")
            node = {"nodeType": "Test Case", "name": f"{meth}()", "nodeIdentifier": f"{cls}/{meth}()",
                    "result": "Failed" if r == "Crash" else r}
            if r == "Crash":
                node["children"] = [{"nodeType": "Failure Message", "name": f"Crash: Host at {meth}"}]
            targets.setdefault(t, {}).setdefault(cls, []).append(node)
        tree = {"testNodes": [{"nodeType": "Test Plan", "name": "Plan", "children": [
            {"nodeType": "Unit test bundle", "name": t, "children": [
                {"nodeType": "Test Suite", "name": cls, "children": nodes} for cls, nodes in classes.items()]}
            for t, classes in targets.items()]}]}
        json.dump(tree, open(os.path.join(bundle, "tests.json"), "w"))
    if any(c in s.get("hang", []) for c in chosen):
        time.sleep(float(os.environ.get("STUB_HANG_S", "30")))
    return 65 if any(r != "Passed" for r in results.values()) else 0


def xcodebuild(args: list[str]) -> int:
    s = scen()
    if args == ["-version"]:
        print(f"Xcode {s.get('version', '27.0')}\nBuild version 27A266a")
        return 0
    only, skip, dd, bundle, action = [], [], None, None, None
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("-only-testing:"):
            only.append(a.split(":", 1)[1])
        elif a.startswith("-skip-testing:"):
            skip.append(a.split(":", 1)[1])
        elif a in ("-derivedDataPath", "-resultBundlePath", "-scheme", "-project", "-workspace", "-destination",
                   "-configuration", "-testPlan", "-sdk", "-collect-test-diagnostics"):
            if a == "-derivedDataPath":
                dd = args[i + 1]
            elif a == "-resultBundlePath":
                bundle = args[i + 1]
            i += 1
        elif a in ("test", "build-for-testing", "test-without-building", "build", "clean"):
            action = a
        i += 1
    if action in ("test", "build-for-testing"):
        if s.get("compileError"):
            print("error: cannot convert value\n** TEST BUILD FAILED **")
            return 65
        if s.get("buildWrites"):
            with open(s["buildWrites"], "a") as fh:
                fh.write("generated\n")
    if action == "build-for-testing":
        dd = dd or "DerivedData"
        app = os.path.join(dd, "Build", "Products", "Debug-iphonesimulator", "Host.app")
        os.makedirs(app, exist_ok=True)
        with open(os.path.join(app, "Info.plist"), "wb") as fh:
            plistlib.dump({"CFBundleIdentifier": "dev.stub.Host"}, fh)
        json.dump(sources(s), open(os.path.join(dd, "stub-snapshot.json"), "w"))
        print("** TEST BUILD SUCCEEDED **")
        return 0
    if action == "test":
        return run_tests(s, only, skip, sources(s), bundle)
    if action == "test-without-building":
        try:
            snap = json.load(open(os.path.join(dd or "DerivedData", "stub-snapshot.json")))
        except OSError:
            print("error: no build products")
            return 65
        return run_tests(s, only, skip, snap, bundle)
    print(f"stub: unsupported action {action}")
    return 64


def xcrun(args: list[str]) -> int:
    if args[:4] == ["xcresulttool", "get", "test-results", "tests"] and "--path" in args:
        p = os.path.join(args[args.index("--path") + 1], "tests.json")
        try:
            sys.stdout.write(open(p).read())
            return 0
        except OSError:
            print("error: no result bundle", file=sys.stderr)
            return 1
    if args[:2] == ["simctl", "terminate"]:
        return 0
    return 64


def main() -> int:
    args = sys.argv[1:]
    tool = os.environ.get("STUB_AS", "xcodebuild")
    log([tool] + args)
    return xcrun(args) if tool == "xcrun" else xcodebuild(args)


if __name__ == "__main__":
    raise SystemExit(main())
