#!/usr/bin/env python3
"""A stand-in for `./gradlew` in t62's AC tests, so CI proves the loop runner's logic without a JVM.

It reads `gradle-stub.json` in the working directory and behaves the way Gradle does for the parts the runner
reads: task selection, `--tests`, `--continue`, dependencies and finalizers, up-to-date test tasks, JUnit XML,
the failure summary line, the exit code — and, under `-I`, the files tests/lib/gradle_runner.init.gradle writes.

Which tests a `--tests` pattern selects is NOT computed here. It is looked up in the scenario's `select` table,
which holds selections recorded from real Gradle (tests/stress/gradle_runner.sh re-checks them on a real build).
Computing them with the runner's own rules would let a matching bug pass on both sides of the comparison.

Scenario:
  tasks:  {path: {deps, fin, fail, failIfFile, test, tests: ["cls#name"], failing: ["cls#name"], ignoreFailures,
                  failOnNoMatchingTests, crash}}  (failIfFile: the task fails while that file exists, so a shell
                  line earlier in a goal can break the build the way a code generator would)
  select: {pattern: ["cls#name", ...]}
  pollution: {failing class: class that must run in the same task for it to pass}
  buildFailureIf: a task path; when it runs, the build also fails with an error that is no task's
Every invocation appends one line to $STUB_COUNT (when set).

t64 (the law harness): a test task may list `mutantFails: {"<law id>": ["cls#name"]}` — those cases fail while
INV_MUTANT is that id. As in real Gradle the environment is not part of a task's up-to-date key, so after a passing
run the same task is UP-TO-DATE under INV_MUTANT unless `--rerun` follows it. `fidelity: "<reason>"` on a test task
stands for something the law build's copy cannot reproduce (a doFirst, an onlyIf, …). Under
`-I …/law_harness.init.gradle` with BDD_LAW_PLAN set, the stub does what that init script does: eligibility, a
check copy and a mutant copy per law in plan order, their JUnit XML, eligible.tsv and outcomes.tsv.
STUB_LAW_LEAK=1 makes the check copy see the mutant too (the leaked-mutant red twin).
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
    init_scripts: list[str] = []
    rerun: set[int] = set()
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
            init_scripts.append(args[i + 1])
            i += 2
        elif a == "--rerun":
            if not reqs:
                return fail_build("Unknown command-line option '--rerun'.")
            rerun.add(len(reqs) - 1)
            i += 1
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

    if any(os.path.basename(x) == "law_harness.init.gradle" for x in init_scripts) and os.environ.get("BDD_LAW_PLAN"):
        return law_build(scen, tasks, select, resolve)
    if any(os.path.basename(x) == "affected.init.gradle" for x in init_scripts):
        # t66: the module map. `projects` is {"<project path>": {"dir": "...", "deps": [...]}}; a bare list is deps.
        if os.environ.get("STUB_AFFECTED_FAIL") or scen.get("affectedFail"):
            return fail_build("stub: module map failure requested")
        if not any(sel.rsplit(":", 1)[-1] == "bddAffectedProjects" for sel, _ in reqs):
            return fail_build("Task 'bddAffectedProjects' not found in root project 'stub'.")
        out = os.environ.get("BDD_AFFECTED_OUT")
        if not out:
            return fail_build("BDD_AFFECTED_OUT is not set.")
        projects = scen.get("projects")
        if not isinstance(projects, dict):
            return fail_build("stub: the scenario has no projects map.")
        rows = []
        for p, spec in projects.items():
            if isinstance(spec, dict):
                d = spec.get("dir", p.strip(":").replace(":", "/"))
                deps = spec.get("deps", [])
            else:
                d = p.strip(":").replace(":", "/")
                deps = spec
            rows.append("\t".join([p, d, ",".join(deps)]))
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        open(out, "w").write("\n".join(rows) + ("\n" if rows else ""))
        return 0
    forced = {t for k, (sel, _) in enumerate(reqs) if k in rerun for t in resolve(sel)}
    mutant = os.environ.get("INV_MUTANT", "")

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
            if s.get("fail") or (s.get("failIfFile") and os.path.exists(s["failIfFile"])):
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
        if state.get(t) == key and os.path.isdir(xml_dir(t)) and t not in forced:
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
                is_bad = (x in s.get("failing", []) or x in s.get("mutantFails", {}).get(mutant, [])
                          or (need is not None and need not in {y.split("#")[0] for y in chosen}))
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


def write_xml(d: str, chosen: list[str], bad: set[str]) -> None:
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    for c in sorted({x.split("#")[0] for x in chosen}):
        cases = [f'  <testcase name={quoteattr(x.split("#", 1)[1])} classname={quoteattr(c)} time="0.001">'
                 + ('<failure message="boom" type="AssertionError">boom</failure>' if x in bad else "") + "</testcase>"
                 for x in chosen if x.split("#")[0] == c]
        open(os.path.join(d, f"TEST-{c}.xml"), "w").write(
            f'<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name={quoteattr(c)} tests="{len(cases)}" '
            f'failures="{sum(1 for x in bad if x.startswith(c + "#"))}" errors="0">\n' + "\n".join(cases) + "\n</testsuite>\n")


def law_build(scen: dict, tasks: dict, select: dict, resolve) -> int:
    """What tests/lib/law_harness.init.gradle does, for the stub's scenario (t64)."""
    out = os.environ["BDD_LAW_OUT"]
    plan = [ln.rstrip("\n").split("\t") for ln in open(os.environ["BDD_LAW_PLAN"], encoding="utf-8") if ln.strip()]
    leak = os.environ.get("STUB_LAW_LEAK") == "1"
    elig, rows, outcomes, failed = [], [], [], 0
    for row in plan:
        lid, sel, pats = row[0], row[1], row[2:]
        found = resolve(sel)
        if len(found) != 1:
            elig.append(f"{lid}\tno\tselector {sel} resolves to {len(found)} tasks, not one")
            continue
        t = found[0]
        s = tasks[t]
        if not s.get("test"):
            elig.append(f"{lid}\tno\t{t} is not a Test task")
        elif s.get("fidelity"):
            elig.append(f"{lid}\tno\t{s['fidelity']}")
        else:
            elig.append(f"{lid}\tyes")
            rows.append((lid, t, pats))
    deps_ok = True
    done: set = set()
    for _, t, _ in rows:
        for d in tasks[t].get("deps", []):
            if d in done:
                continue
            done.add(d)
            if tasks[d].get("fail"):
                outcomes.append((d, "FAILED", f"Execution failed for task '{d}'. | Compilation failed; see the compiler error output for details."))
                failed += 1
                deps_ok = False
            else:
                outcomes.append((d, "SUCCESS", ""))
    for lid, t, pats in rows if deps_ok else []:
        s = tasks[t]
        proj = t[: t.rfind(":") + 1]
        chosen = [x for x in s.get("tests", []) if any(x in select.get(p, []) for p in pats)] if pats else list(s.get("tests", []))
        for kind in ("Check", "Mutant"):
            path = f"{proj}bddLaw{kind}_{lid}"
            if not chosen and s.get("failOnNoMatchingTests", True):
                outcomes.append((path, "FAILED", f"Execution failed for task '{path}'. | No tests found for given includes: {pats}(filter.includeTestsMatching)"))
                failed += 1
                continue
            mut = kind == "Mutant" or leak
            bad = {x for x in chosen if x in s.get("failing", []) or (mut and x in s.get("mutantFails", {}).get(lid, []))}
            write_xml(os.path.join(out, lid, kind.lower()), chosen, bad)
            if bad:
                outcomes.append((path, "FAILED", f"Execution failed for task '{path}'. | There were failing tests. See the report at: file://{out}"))
                failed += 1
            else:
                outcomes.append((path, "SUCCESS", ""))
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "eligible.tsv"), "w").write("\n".join(elig) + ("\n" if elig else ""))
    with open(os.path.join(out, "outcomes.tsv"), "a") as fh:
        for r in outcomes:
            fh.write("\t".join(r) + "\n")
    if failed == 0:
        print("\nBUILD SUCCESSFUL")
        return 0
    print("\nFAILURE: " + ("Build failed with an exception." if failed == 1 else f"Build completed with {failed} failures."))
    print("\nBUILD FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
