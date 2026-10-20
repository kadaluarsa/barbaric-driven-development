#!/usr/bin/env python3
"""Prove Gradle laws GREEN from one build instead of two per law (t64).

    { printf 'L\\t<index>\\t<id>\\t<check>\\t<break>\\n' ...; } | law_harness.py <root> <envelope file> <logdir>

Prints `<index>\\tGREEN` for each law it can PROVE is GREEN, then `S\\t<builds>\\t<seconds>`, and writes why every
other law was left alone to <logdir>/law-harness.tsv. It never prints RED, THEATER or UNPROVEN: a law it does not
prove is scored by tests/dsharp_strength.sh with its own two commands, exactly as before t64, so every
non-GREEN verdict is that path's. docs/cascade/05b-t64-law-harness-jvm.md is the contract.

On only when (§1): `- DSHARP_GRADLE_HARNESS: on` is the last such line inside an <EDIT> block of
docs/cascade/envelope.md, both at HEAD and in the working tree; the laws came from that file; and DSHARP_HARNESS
is not `off` (the merge gate always sets it).

A law is eligible when (§2): its `check:` is a plain Gradle line t62's parser takes, with one selector and no
-D/-P; its `break:` is exactly `INV_MUTANT=<id> <check> --rerun`; the Gradle version is verified; and the init
script finds its one Test task and a faithful copy of it (§3, tests/lib/law_harness.init.gradle).

GREEN is proven when (§4): the law is eligible; its check copy SUCCEEDED and ran at least one test; its mutant
copy FAILED on failing tests only, ran the same test cases, and every case that failed passed in the check; no
other task in the build failed; and the build's own failure count is its count of FAILED tasks.
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gradle_runner import VERIFIED, _envelopes, failure_count, parse, verified, wrapper_version   # noqa: E402
from signed import BLOCK   # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INIT = os.path.join(HERE, "law_harness.init.gradle")
SWITCH = re.compile(r"^\s*-\s*DSHARP_GRADLE_HARNESS:\s*(on|off)(?=\s|$)")
REMOTE = re.compile(r"^\s*-\s*DSHARP_GRADLE_BUILD_CACHE_URL:\s*(\S+)")
CHUNK = 100     # laws per build (Risks U3 in the spec; E1 measures memory)
OK = ("SUCCESS", "UP-TO-DATE", "FROM-CACHE")
REL = "docs/cascade/envelope.md"


def _decision(text: str) -> bool:
    """The last DSHARP_GRADLE_HARNESS line inside <EDIT> decides; a {{template}} line is no decision."""
    last = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = SWITCH.match(line)
            if m and "{{" not in line:
                last = m.group(1)
    return last == "on"


def build_cache(root: str) -> tuple[list[str], dict, str]:
    """t65: the law build uses Gradle's build cache unless DSHARP_CACHE is off (only `on` or unset turn it on). It
    serves compilation; the law copies stay cacheIf { false }. A remote cache is read-only (push = false) and only
    from a URL signed inside <EDIT> at HEAD and in the working tree alike, and only over https."""
    if (os.environ.get("DSHARP_CACHE") or "on") != "on":   # empty is unset, as in dsharp_strength.sh's ${DSHARP_CACHE:-on}
        return [], {}, "DSHARP_CACHE is off"
    urls = []
    for text in _envelopes(root):
        last = None
        for block in BLOCK.findall(text):
            for line in block.splitlines():
                m = REMOTE.match(line)
                if m and "{{" not in line:
                    last = m.group(1)
        urls.append(last)
    url = urls[0] if urls and all(u == urls[0] for u in urls) else None
    if url and url.startswith("https://"):
        return ["--build-cache"], {"BDD_BUILD_CACHE_URL": url}, ""
    why = ("" if not any(urls) else "the remote build cache URL is not https" if url
           else "the remote build cache URL is not signed and committed")
    return ["--build-cache"], {}, why


def switched_on(root: str, envelope: str) -> tuple[bool, str]:
    if os.environ.get("DSHARP_HARNESS", "") == "off":
        return False, "DSHARP_HARNESS=off"
    try:
        same = os.path.realpath(envelope) == os.path.realpath(os.path.join(root, REL))
    except OSError:
        same = False
    if not same:
        return False, f"the laws came from {envelope}, not {REL}"
    texts = _envelopes(root)
    if not (texts and all(_decision(t) for t in texts)):
        return False, "DSHARP_GRADLE_HARNESS: on is not signed and committed"
    return True, ""


def _gradle_on_path_version() -> str | None:
    try:
        out = subprocess.run(["gradle", "--version"], capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"^Gradle (\d+\.\d+(?:\.\d+)?)", out, re.M)
    return m.group(1) if m else None


def eligible(root: str, lid: str, check: str, brk: str, versions: dict) -> tuple[dict | None, str]:
    """(plan row, "") for a law the harness may take, else (None, why)."""
    p = parse(check, root)
    if p is None:
        return None, "check: is not a plain Gradle line"
    if len(p["sels"]) != 1:
        return None, "check: names more than one task"
    if not p["sels"][0][0].startswith(":"):
        return None, "check: names its task without a project path (`:module:test`), so it may mean several"
    if any(g.startswith(("-D", "-P")) or g in ("--system-prop", "--project-prop") for g in p["globals"]):
        return None, "check: sets -D/-P, which changes the build"
    if brk != f"INV_MUTANT={lid} {check} --rerun":
        return None, f"break: is not `INV_MUTANT={lid} <check> --rerun`"
    entry = p["entry"]
    if entry not in versions:
        if entry == "./gradlew":
            ok = verified(wrapper_version(root)) and os.access(os.path.join(root, "gradlew"), os.X_OK)
        else:
            ok = verified(_gradle_on_path_version())
        versions[entry] = ok
    if not versions[entry]:
        return None, f"{entry} is not a verified Gradle version ({VERIFIED[0]} to below {VERIFIED[1]})"
    sel, pats = p["sels"][0]
    return {"id": lid, "entry": entry, "globals": p["globals"], "sel": sel, "pats": list(pats or ())}, ""


def junit(d: str) -> dict | None:
    """{(classname, name): failed} for the JUnit XML in d; None when it cannot be read."""
    if not os.path.isdir(d):
        return None
    out: dict = {}
    for f in sorted(glob.glob(os.path.join(d, "*.xml"))):
        try:
            r = ET.parse(f).getroot()
        except (ET.ParseError, OSError):
            return None
        for tc in r.iter("testcase"):
            if tc.find("skipped") is not None:
                continue
            out[(tc.get("classname") or "", tc.get("name") or "")] = (
                tc.find("failure") is not None or tc.find("error") is not None)
    return out


def read_tsv(path: str) -> list[list[str]]:
    try:
        return [ln.rstrip("\n").split("\t") for ln in open(path, encoding="utf-8", errors="replace") if ln.strip()]
    except OSError:
        return []


def only_failing_tests(why: str) -> bool:
    parts = [c.strip() for c in why.split(" | ") if c.strip()]
    return (any(c.startswith("There were failing tests") for c in parts)
            and all(c.startswith(("Execution failed for task", "There were failing tests")) for c in parts))


def proven(law: dict, out: str, elig: dict, outcomes: dict) -> tuple[bool, str]:
    lid = law["id"]
    if elig.get(lid, ("no", "the init script did not report it"))[0] != "yes":
        return False, "not eligible: " + elig.get(lid, ("no", "the init script did not report it"))[1]
    check = outcomes.get(f"{law['proj']}bddLawCheck_{lid}")
    mutant = outcomes.get(f"{law['proj']}bddLawMutant_{lid}")
    if not check or check[0] != "SUCCESS":
        return False, f"check copy {check[0] if check else 'did not run'}"
    if not mutant or mutant[0] != "FAILED" or not only_failing_tests(mutant[1]):
        return False, f"mutant copy {mutant[0] if mutant else 'did not run'}{'' if not mutant else ' (' + mutant[1][:80] + ')'}"
    c, m = junit(os.path.join(out, lid, "check")), junit(os.path.join(out, lid, "mutant"))
    if not c:
        return False, "the check copy ran no test"
    if m is None or set(m) != set(c):
        return False, "the mutant ran other test cases than the check"
    if any(c[k] for k in c):
        return False, "a check case failed in a passing task"
    if not any(m.values()):
        return False, "the mutant task failed with no failing case"
    return True, ""


def main() -> int:
    if len(sys.argv) != 4:
        return 64
    root, envelope, logdir = sys.argv[1:4]
    laws: list[tuple[int, str, str, str]] = []
    for raw in sys.stdin.read().split("\n"):
        p = raw.split("\t")
        if len(p) == 5 and p[0] == "L" and p[1].isdigit():
            laws.append((int(p[1]), p[2], p[3], p[4]))
    on, _ = switched_on(root, envelope)
    if not on:
        print("S\t0\t0")    # off: no file written, no process started — the repo is exactly as before t64
        return 0
    os.makedirs(logdir, exist_ok=True)
    notes = open(os.path.join(logdir, "law-harness.tsv"), "w", encoding="utf-8")
    versions: dict = {}
    cache_flags, cache_env, cache_why = build_cache(root)
    if cache_why and cache_why != "DSHARP_CACHE is off":
        notes.write(f"-\t-\tremote build cache ignored: {cache_why}\n")
    groups: OrderedDict = OrderedDict()
    for i, lid, check, brk in laws:
        row, why = eligible(root, lid, check, brk, versions)
        if row is None:
            notes.write(f"{i}\t{lid}\t{why}\n")
            continue
        row["index"] = i
        sel = row["sel"]
        row["proj"] = sel[: sel.rfind(":") + 1] if sel.startswith(":") else ":"
        groups.setdefault((row["entry"], row["globals"]), []).append(row)
    greens: list[int] = []
    builds, spent = 0, 0.0
    base = os.path.join(root, ".cascade", "laws")
    for (entry, globals_), rows in groups.items():
        for start in range(0, len(rows), CHUNK):
            chunk = rows[start:start + CHUNK]
            out = tempfile.mkdtemp(prefix="build-", dir=_mkdir(base))
            plan = os.path.join(out, "plan.tsv")
            with open(plan, "w", encoding="utf-8") as fh:
                for r in chunk:
                    fh.write("\t".join([r["id"], r["sel"], *r["pats"]]) + "\n")
            g = [x for x in globals_ if x not in ("--configuration-cache", "--no-configuration-cache")]
            # A law that says --no-build-cache keeps it: its author kept a non-hermetic build out of the cache.
            own_no = "--no-build-cache" in g
            g = [x for x in g if x != "--build-cache"]
            flags, extra = ([], {}) if own_no else (cache_flags, cache_env)
            cmd = [entry, *g, *flags, "--no-configuration-cache", "--continue", "-I", INIT, "bddLaws"]
            env = dict(os.environ, BDD_LAW_PLAN=plan, BDD_LAW_OUT=out, BDD_GRADLE_RANGE=f"{VERIFIED[0]}:{VERIFIED[1]}",
                       **extra)
            if not extra:
                env.pop("BDD_BUILD_CACHE_URL", None)   # an inherited URL is no signature
            env.pop("INV_MUTANT", None)
            log_path = os.path.join(logdir, f"laws-{builds + 1}.log")
            t0 = time.time()
            try:
                with open(log_path, "w") as fh:
                    rc = subprocess.run(cmd, cwd=root, env=env, stdout=fh, stderr=subprocess.STDOUT,
                                        stdin=subprocess.DEVNULL).returncode
            except OSError as exc:
                for r in chunk:
                    notes.write(f"{r['index']}\t{r['id']}\tthe law build could not start ({exc})\n")
                shutil.rmtree(out, ignore_errors=True)
                continue
            builds += 1
            spent += time.time() - t0
            elig = {p[0]: (p[1], p[2] if len(p) > 2 else "") for p in read_tsv(os.path.join(out, "eligible.tsv")) if len(p) >= 2}
            outcomes = {p[0]: (p[1], p[2] if len(p) > 2 else "") for p in read_tsv(os.path.join(out, "outcomes.tsv")) if len(p) >= 2}
            copies = {f"{r['proj']}bddLaw{k}_{r['id']}" for r in chunk for k in ("Check", "Mutant")}
            others_failed = [t for t, (s, _) in outcomes.items() if s == "FAILED" and t not in copies]
            failed = sum(1 for s, _ in outcomes.values() if s == "FAILED")
            log = open(log_path, encoding="utf-8", errors="replace").read()
            count = failure_count(log) if rc != 0 else 0
            readable = bool(elig) and bool(outcomes) and not others_failed and count == failed
            for r in chunk:
                if not readable:
                    why = ("another task failed: " + ", ".join(others_failed[:3]) if others_failed
                           else "the build could not be read (no eligibility or outcome files, or a failure that is no task's)")
                    notes.write(f"{r['index']}\t{r['id']}\t{why}\n")
                    continue
                ok, why = proven(r, out, elig, outcomes)
                if ok:
                    greens.append(r["index"])
                notes.write(f"{r['index']}\t{r['id']}\t{'GREEN' if ok else why}\n")
            shutil.rmtree(out, ignore_errors=True)
    for i in sorted(greens):
        print(f"{i}\tGREEN")
    print(f"S\t{builds}\t{spent:.0f}")
    return 0


def _mkdir(d: str) -> str:
    os.makedirs(d, exist_ok=True)
    return d


if __name__ == "__main__":
    raise SystemExit(main())
