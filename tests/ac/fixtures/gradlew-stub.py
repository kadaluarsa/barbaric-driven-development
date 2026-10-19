#!/usr/bin/env python3
"""A stand-in for `./gradlew` in t62's AC tests, so CI proves the loop runner's logic without a JVM.

It reads `gradle-stub.json` in the working directory and behaves the way Gradle does for the parts the runner
reads: task selection, `--tests`, `--continue`, dependencies and finalizers, up-to-date test tasks, JUnit XML,
the failure summary line, the exit code — and, under `-I`, the files tests/lib/gradle_runner.init.gradle writes.

Which tests a `--tests` pattern selects is NOT computed here. It is looked up in the scenario's `select` table,
which holds selections recorded from real Gradle (tests/stress/gradle_runner.sh re-checks them on a real build).
Computing them with the runner's own rules would let a matching bug pass on both sides of the comparison.

Scenario:
  tasks:  {path: {deps, fin, fail, test, tests: ["cls#name"], failing: ["cls#name"], ignoreFailures,
                  failOnNoMatchingTests, crash}}
  select: {pattern: ["cls#name", ...]}
  pollution: {failing class: class that must run in the same task for it to pass}
  buildFailureIf: a task path; when it runs, the build also fails with an error that is no task's
Every invocation appends one line to $STUB_COUNT (when set).
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
from xml.sax.saxutils import quoteattr

ZERO = {"-q", "-w", "-i", "-d", "-s", "-S", "--quiet", "--warn", "--info", "--debug", "--stacktrace",
        "--full-stacktrace", "--offline", "--refresh-dependencies", "--rerun-tasks", "--build-cache",
        "--no-build-cache", "--configuration-cache", "--no-configuration-cache", "--parallel", "--no-parallel",
        "--daemon", "--no-daemon", "--continue", "--scan", "--no-scan", "--watch-fs", "--no-watch-fs"}
ONE = {"-x", "--exclude-task", "--console", "--warning-mode", "--max-workers", "-D", "-P", "--system-prop",
       "--project-prop", "-I", "--init-script"}


def fail_build(msg: str) -> int:
    print(f"\nFAILURE: Build failed with an exception.\n\n* What went wrong:\n{msg}\n\nBUILD FAILED")
    return 1


def main() -> int:
    if os.environ.get("STUB_COUNT"):
        with open(os.environ["STUB_COUNT"], "a") as fh:
            fh.write(" ".join(sys.argv[1:]) + "\n")
    scen_text = open("gradle-stub.json", encoding="utf-8").read()
    scen = json.loads(scen_text)
    tasks, select = scen["tasks"], scen.get("select", {})
    args, init, cont, excluded = sys.argv[1:], False, False, set()
    reqs: list[list] = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--tests":
            if not reqs:
                return fail_build("Unknown command-line option '--tests'.")
            reqs[-1][1].append(args[i + 1])
            i += 2
        elif a in ("-I", "--init-script"):
            init = True
            i += 2
        elif a in ("-x", "--exclude-task"):
            excluded.add(args[i + 1])
            i += 2
        elif a in ONE:
            i += 2
        elif a in ZERO or a.startswith(("-D", "-P", "--console=", "--warning-mode=", "--max-workers=")):
            cont = cont or a == "--continue"
            i += 1
        else:
            reqs.append([a, []])
            i += 1

    def resolve(sel: str) -> list[str]:
        if ":" in sel:
            p = sel if sel.startswith(":") else ":" + sel
            return [p] if p in tasks else []
        return [t for t in tasks if t.rsplit(":", 1)[-1] == sel]

    filters: dict = {}
    requested: list[str] = []
    for sel, pats in reqs:
        found = resolve(sel)
        if not found:
            return fail_build(f"Task '{sel}' not found in root project 'stub'.")
        for t in found:
            requested.append(t)
            if pats:
                filters[t] = sorted(set(filters.get(t, []) + pats))
    for pats in filters.values():
        for p in pats:
            if p not in select:
                print(f"stub: no recorded selection for --tests {p}", file=sys.stderr)
                return 3

    # The graph: requested tasks, their dependencies, then finalizers — dependencies first.
    order: list[str] = []

    def visit(t: str, stack: tuple = ()) -> None:
        if t in order or t in stack or t in excluded:
            return
        for d in tasks[t].get("deps", []):
            visit(d, stack + (t,))
        order.append(t)
        for f in tasks[t].get("fin", []):
            visit(f, stack + (t,))
    for t in requested:
        visit(t)

    def xml_dir(t: str) -> str:
        parts = t.strip(":").split(":")
        return os.path.join(os.getcwd(), *parts[:-1], "build", "test-results", parts[-1])

    if init and os.environ.get("BDD_GRADLE_GRAPH"):
        rows = []
        for t in order:
            s = tasks[t]
            test = bool(s.get("test"))
            rows.append("\t".join([t, "test" if test else "task", xml_dir(t) if test else "",
                                   str(bool(s.get("ignoreFailures"))).lower() if test else "",
                                   str(s.get("failOnNoMatchingTests", True)).lower() if test else "",
                                   ",".join(sorted(d for d in s.get("deps", []) if d in order)),
                                   ",".join(sorted(f for f in s.get("fin", []) if f in order))]))
        os.makedirs(os.path.dirname(os.environ["BDD_GRADLE_GRAPH"]), exist_ok=True)
        open(os.environ["BDD_GRADLE_GRAPH"], "w").write("\n".join(rows) + "\n")

    state_path = os.path.join(".gradle", "stub-state.json")
    try:
        state = json.load(open(state_path))
    except (OSError, ValueError):
        state = {}
    scen_hash = hashlib.sha256(scen_text.encode()).hexdigest()
    outcomes: list[tuple[str, str, str]] = []
    failed: set[str] = set()
    ran: set[str] = set()
    for t in order:
        s = tasks[t]
        if any(d in order and d not in ran for d in s.get("deps", [])) or (failed and not cont):
            continue                                       # a dependency failed (or no --continue): not executed
        ran.add(t)
        if not s.get("test"):
            if s.get("fail"):
                print(f"> Task {t} FAILED")
                outcomes.append((t, "FAILED", f"Execution failed for task '{t}'. | Compilation failed; see the compiler error output for details."))
                failed.add(t)
                ran.discard(t)
            else:
                print(f"> Task {t}")
                outcomes.append((t, "SUCCESS", ""))
            continue
        pats = filters.get(t)
        key = f"{scen_hash}|{pats}"
        if state.get(t) == key and os.path.isdir(xml_dir(t)):
            print(f"> Task {t} UP-TO-DATE")
            outcomes.append((t, "UP-TO-DATE", ""))
            continue
        tests = s.get("tests", [])
        chosen = tests if pats is None else [x for x in tests if any(x in select[p] for p in pats)]
        shutil.rmtree(xml_dir(t), ignore_errors=True)
        state.pop(t, None)
        if pats is not None and not chosen and s.get("failOnNoMatchingTests", True):
            print(f"> Task {t} FAILED")
            outcomes.append((t, "FAILED", f"Execution failed for task '{t}'. | No tests found for given includes: {pats}(--tests filter)"))
            failed.add(t)
            ran.discard(t)
            continue
        classes = sorted({x.split("#")[0] for x in chosen})
        if s.get("crash"):
            classes = classes[: len(classes) // 2]
        bad = []
        os.makedirs(xml_dir(t), exist_ok=True)
        for c in classes:
            cases = []
            for x in [x for x in chosen if x.split("#")[0] == c]:
                need = scen.get("pollution", {}).get(c)
                is_bad = x in s.get("failing", []) or (need is not None and need not in {y.split("#")[0] for y in chosen})
                name = x.split("#", 1)[1]
                if is_bad:
                    bad.append(x)
                    print(f"{c} > {name} FAILED")
                cases.append(f'  <testcase name={quoteattr(name)} classname={quoteattr(c)} time="0.001">'
                             + ('<failure message="boom" type="AssertionError">boom</failure>' if is_bad else "")
                             + "</testcase>")
            open(os.path.join(xml_dir(t), f"TEST-{c}.xml"), "w").write(
                f'<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name={quoteattr(c)} tests="{len(cases)}" '
                f'failures="{sum(1 for x in bad if x.startswith(c + "#"))}" errors="0">\n' + "\n".join(cases) + "\n</testsuite>\n")
        if s.get("crash"):
            print(f"> Task {t} FAILED")
            outcomes.append((t, "FAILED", f"Execution failed for task '{t}'. | Process 'Gradle Test Executor 1' finished with non-zero exit value 1"))
            failed.add(t)
            ran.discard(t)
        elif bad and not s.get("ignoreFailures"):
            print(f"> Task {t} FAILED")
            outcomes.append((t, "FAILED", f"Execution failed for task '{t}'. | There were failing tests. See the report at: file://{xml_dir(t)}"))
            failed.add(t)
            ran.discard(t)
        else:
            print(f"> Task {t}")
            outcomes.append((t, "SUCCESS", ""))
            state[t] = key
    os.makedirs(".gradle", exist_ok=True)
    json.dump(state, open(state_path, "w"))
    if init and os.environ.get("BDD_GRADLE_OUT"):
        with open(os.path.join(os.environ["BDD_GRADLE_OUT"], "outcomes.tsv"), "a") as fh:
            for row in outcomes:
                fh.write("\t".join(row) + "\n")
    n = len(failed) + (1 if scen.get("buildFailureIf") in ran else 0)
    if n == 0:
        print("\nBUILD SUCCESSFUL")
        return 0
    print("\nFAILURE: " + ("Build failed with an exception." if n == 1 else f"Build completed with {n} failures."))
    print("\nBUILD FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
