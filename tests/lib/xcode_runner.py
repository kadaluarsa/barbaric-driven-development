#!/usr/bin/env python3
"""Prove passes for this hop's plain `xcodebuild test` VALIDATOR lines from one build per build key (t75).

    { printf 'V\\t<i>\\t<line>\\n' ...; } | xcode_runner.py <root> <envelope> <logdir> <from>

The t62 contract, unchanged: it considers only the SEGMENT that starts at line <from> (the longest run of
consecutive lines it takes), prints `<i>\\tPASS\\t<summary>` for each line it can PROVE passes, then
`S\\t<builds>\\t<seconds>\\txcode` and `E\\t<last index of the segment>`. It never prints FAIL: a line it does not prove
runs alone in tests/loop.sh by the code path every line took before, so every FAIL is that path's verdict.
docs/cascade/05b-t75-xcode-runner.md is the contract; E0/E0b there are the measurements every rule below rests on.

  * Taken (§1): `xcodebuild` with exactly one action, `test`; one -scheme; at most one of -workspace/-project; one
    -destination naming one device (id=…, or platform=…,name=…; never generic/…); otherwise only -configuration,
    -testPlan, -sdk, -quiet, -only-testing:X, -skip-testing:X and KEY=VALUE build settings; no shell syntax. On an
    Xcode version in VERIFIED only.
  * The build key is the line minus `test` and its selectors. Lines of one key share one `build-for-testing` into
    .cascade/xcode/<key hash>/dd; a key with one line in the segment saves nothing, so that line runs alone.
  * The build is reused while the worktree fingerprint (cascade_worktree_sha, which leaves .cascade/ out) is the one it
    was built from — across segments and runs (E0: test-without-building runs a stale binary after an edit). A build
    that itself moves the fingerprint marks its key self-modifying: its lines run alone, and it is not rebuilt (C4).
  * Each line runs as its own `test-without-building` with its own selectors and result bundle — its own test
    process (E0: one call with two classes shares one process). Bounded by BDD_XCODE_TIMEOUT (default 600s); on a
    timeout the process group is killed and the simulator's test host is terminated (E0b: it outlives xcodebuild).
  * PASS only when: exit 0 within the bound; the .xcresult parses; at least one test case ran; every test case is
    Passed, Skipped or Expected Failure; every case is one the line's own selectors select; and the fingerprint did
    not move while it ran.
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import plistlib
import re
import shlex
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# The Xcode versions tests/stress/xcode_runner.sh passed on: >= VERIFIED[0] and < VERIFIED[1]. Lines on any other
# version run alone, as before t75.
VERIFIED = ("27.0", "27.1")
ONE = {"-workspace", "-project", "-scheme", "-destination", "-configuration", "-testPlan", "-sdk"}
SETTING = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SELECTOR = re.compile(r"^-(only|skip)-testing:([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+){0,2})$")
OK_RESULTS = ("Passed", "Skipped", "Expected Failure")
TIMEOUT = 600


# --- which lines -------------------------------------------------------------------------------------------

def parse(line: str) -> dict | None:
    """{key: tuple, only: [sel], skip: [sel], dest: str, quiet: bool} for a line the runner may take, else None."""
    if any(c in line for c in "$`\\{}#!;|&<>()~"):
        return None
    try:
        toks = shlex.split(line)
    except ValueError:
        return None
    if not toks or toks[0] != "xcodebuild":
        return None
    opts: dict = {}
    settings: list[str] = []
    only: list[str] = []
    skip: list[str] = []
    actions: list[str] = []
    quiet = False
    i = 1
    while i < len(toks):
        t = toks[i]
        m = SELECTOR.match(t)
        if m:
            (only if m.group(1) == "only" else skip).append(m.group(2))
            i += 1
        elif t in ONE:
            if i + 1 >= len(toks) or t in opts:
                return None                               # a value missing, or an option twice
            opts[t] = toks[i + 1]
            i += 2
        elif t == "-quiet":
            quiet = True
            i += 1
        elif t.startswith("-"):
            return None                                   # -derivedDataPath, -resultBundlePath and all else: alone
        elif SETTING.match(t):
            settings.append(t)
            i += 1
        else:
            actions.append(t)
            i += 1
    if actions != ["test"] or "-scheme" not in opts or "-destination" not in opts:
        return None
    if "-workspace" in opts and "-project" in opts:
        return None
    dest = opts["-destination"]
    fields = dict(f.split("=", 1) for f in dest.split(",") if "=" in f)
    if "generic" in dest or not ("id" in fields or ("platform" in fields and "name" in fields)):
        return None
    key = tuple(sorted((k, v) for k, v in opts.items())) + tuple(settings)
    return {"key": key, "only": only, "skip": skip, "dest": dest, "dest_id": fields.get("id"), "quiet": quiet}


def key_args(key: tuple) -> list[str]:
    out: list[str] = []
    for item in key:
        if isinstance(item, tuple):
            out += [item[0], item[1]]
        else:
            out.append(item)
    return out


def key_hash(key: tuple) -> str:
    return hashlib.sha256(json.dumps(key).encode()).hexdigest()[:16]


_version: list = []


def xcode_version() -> str | None:
    if not _version:
        try:
            out = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, timeout=120).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        m = re.search(r"^Xcode (\d+(?:\.\d+){0,2})", out, re.M)
        _version.append(m.group(1) if m else None)
    return _version[0]


def _vkey(v: str) -> tuple:
    p = [int(x) for x in v.split(".")]
    return tuple(p + [0] * (3 - len(p)))


def verified(v: str | None) -> bool:
    return bool(v) and _vkey(VERIFIED[0]) <= _vkey(v) < _vkey(VERIFIED[1])


# --- the tree and the build --------------------------------------------------------------------------------

def fingerprint(root: str) -> str:
    r = subprocess.run(["bash", "-c", '. "$1/cascade.sh" 2>/dev/null && cascade_worktree_sha "$2"', "_", HERE, root],
                       capture_output=True, text=True)
    return r.stdout.strip()


def _read(path: str) -> str:
    try:
        return open(path, encoding="utf-8").read().strip()
    except OSError:
        return ""


def _write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")


class Key:
    """One build key: where its build lives, whether it is current, and whether it can be trusted at all."""

    def __init__(self, root: str, key: tuple, logdir: str, version: str):
        self.root, self.key, self.logdir = root, key, logdir
        self.dir = os.path.join(root, ".cascade", "xcode", key_hash(key))
        self.dd = os.path.join(self.dir, "dd")
        self.stamp = f"{version}\t{json.dumps(key)}"
        self.unstable = False
        self.why = ""

    def ready(self, fp: str) -> bool:
        """A build from exactly this source fingerprint, this Xcode and this key exists."""
        return bool(fp) and _read(os.path.join(self.dir, "built")) == f"{fp}\t{self.stamp}" and os.path.isdir(
            os.path.join(self.dd, "Build", "Products"))

    def marked_unstable(self, fp: str) -> bool:
        return fp != "" and fp in _read(os.path.join(self.dir, "unstable")).split()

    def build(self, run, fp_before: str) -> tuple[bool, float]:
        t0 = time.time()
        rc, _ = run(["xcodebuild", *key_args(self.key), "build-for-testing", "-derivedDataPath", self.dd],
                    os.path.join(self.logdir, f"xcode-build-{key_hash(self.key)}.log"))
        took = time.time() - t0
        if rc != 0:
            self.why = "build-for-testing failed"
            return False, took
        fp_after = fingerprint(self.root)
        if fp_after != fp_before:
            # C4: the build wrote into the tree. Remember both states so a later segment does not try again.
            self.unstable = True
            self.why = "the build changes the worktree (a build phase writes tracked or unignored files)"
            _write(os.path.join(self.dir, "unstable"), f"{fp_before} {fp_after}")
            return False, took
        _write(os.path.join(self.dir, "built"), f"{fp_before}\t{self.stamp}")
        return True, took

    def host_bundle_ids(self) -> list[str]:
        out = []
        for plist in glob.glob(os.path.join(self.dd, "Build", "Products", "*", "*.app", "Info.plist")):
            try:
                with open(plist, "rb") as fh:
                    bid = plistlib.load(fh).get("CFBundleIdentifier")
            except Exception:
                continue
            if bid:
                out.append(bid)
        return out


# --- what a run proved -------------------------------------------------------------------------------------

def test_cases(bundle: str) -> list[tuple[str, str]] | None:
    """[(Target/Class/method, result)] from a result bundle; None when it cannot be read."""
    try:
        r = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle],
                           capture_output=True, text=True, timeout=120)
        data = json.loads(r.stdout) if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    out: list[tuple[str, str]] = []

    def walk(node: dict, target: str | None) -> None:
        kind = node.get("nodeType")
        if kind == "Unit test bundle" or kind == "UI test bundle":
            target = node.get("name")
        if kind == "Test Case":
            ident = node.get("nodeIdentifier") or ""
            cls, _, meth = ident.partition("/")
            meth = meth.split("(", 1)[0]
            out.append((f"{target}/{cls}/{meth}" if target else f"?/{cls}/{meth}", node.get("result") or ""))
            return
        for child in node.get("children") or []:
            if isinstance(child, dict):
                walk(child, target)
    for n in data.get("testNodes") or []:
        if isinstance(n, dict):
            walk(n, None)
    return out


def selected(case: str, only: list[str], skip: list[str]) -> bool:
    def under(sel: str) -> bool:
        return case == sel or case.startswith(sel + "/")
    if any(under(s) for s in skip):
        return False
    return not only or any(under(s) for s in only)


def proven(rc: int | None, cases: list | None, p: dict) -> tuple[bool, str]:
    if rc != 0:
        return False, "timed out" if rc is None else f"exit {rc}"
    if cases is None:
        return False, "the result bundle could not be read"
    if not cases:
        return False, "no test case ran"
    bad = [c for c, r in cases if r not in OK_RESULTS]
    if bad:
        return False, f"{len(bad)} case(s) not passed"
    foreign = [c for c, _ in cases if not selected(c, p["only"], p["skip"])]
    if foreign:
        return False, "a case outside the line's own selectors ran: " + foreign[0]
    return True, ""


# --- running xcodebuild, bounded ---------------------------------------------------------------------------

def runner(timeout: int):
    def run(cmd: list[str], log: str, env: dict | None = None) -> tuple[int | None, float]:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        t0 = time.time()
        with open(log, "w") as fh:
            try:
                proc = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                        env=env, start_new_session=True)
            except OSError:
                return 127, 0.0
            try:
                rc = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
                proc.wait()
                rc = None
        return rc, time.time() - t0
    return run


def terminate_hosts(k: Key, dest_id: str | None) -> None:
    """E0b: a killed xcodebuild leaves the test host running in the simulator."""
    if not dest_id:
        return
    for bid in k.host_bundle_ids():
        subprocess.run(["xcrun", "simctl", "terminate", dest_id, bid], capture_output=True, timeout=60)


def test_line(k: Key, p: dict, i: int, run, timeout: int, env: dict | None = None,
              tag: str = "") -> tuple[int | None, list | None, str, float]:
    bundle = os.path.join(k.dir, f"line-{i}{tag}.xcresult")
    subprocess.run(["rm", "-rf", bundle])
    sel = [f"-only-testing:{s}" for s in p["only"]] + [f"-skip-testing:{s}" for s in p["skip"]]
    # A failed run proves nothing and its line runs alone anyway, with the user's own flags; so the runner's own run
    # skips the sysdiagnose-like collection Xcode does on a failure (E0c: 62s → 26s for one failing test).
    cmd = ["xcodebuild", *key_args(k.key), "test-without-building", *sel, "-derivedDataPath", k.dd,
           "-resultBundlePath", bundle, "-collect-test-diagnostics", "never"]
    log = os.path.join(k.logdir, f"xcode-{i}{tag}.log")
    rc, took = run(cmd, log, env)
    if rc is None:
        terminate_hosts(k, p["dest_id"])
    return rc, (test_cases(bundle) if rc is not None else None), log, took


# --- main --------------------------------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) != 5 or not sys.argv[4].isdigit():
        return 64
    root, _envelope, logdir, start = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    lines: dict[int, str] = {}
    for raw in sys.stdin.read().split("\n"):
        f = raw.split("\t", 2)
        if f[0] == "V" and len(f) == 3 and f[1].isdigit():
            lines[int(f[1])] = f[2]
    segment: list[tuple[int, dict]] = []
    i = start
    while i in lines:
        p = parse(lines[i])
        if p is None:
            break
        segment.append((i, p))
        i += 1
    version = xcode_version() if len(segment) >= 2 else None
    if len(segment) < 2 or not verified(version):
        print("S\t0\t0\txcode")
        print(f"E\t{segment[-1][0] if segment else start}")
        return 0
    try:
        timeout = max(1, int(os.environ.get("BDD_XCODE_TIMEOUT") or TIMEOUT))
    except ValueError:
        timeout = TIMEOUT
    run = runner(timeout)
    counts: dict = {}
    for _, p in segment:
        counts[p["key"]] = counts.get(p["key"], 0) + 1
    keys: dict = {}
    passes: list[tuple[int, str]] = []
    builds, spent = 0, 0.0
    notes: list[str] = []
    for i, p in segment:                                  # goal order: a line still runs after the lines before it
        if counts[p["key"]] < 2:
            continue                                      # one line for this key: no build to share, it runs alone
        k = keys.setdefault(p["key"], Key(root, p["key"], logdir, version))
        if k.unstable:
            continue
        fp = fingerprint(root)
        if not fp:
            notes.append(f"{i}: no worktree fingerprint, so no build can be trusted")
            continue
        if k.marked_unstable(fp):
            k.unstable = True
            notes.append(f"key {key_hash(p['key'])}: its build changes the worktree; its lines run alone")
            continue
        if not k.ready(fp):
            ok, took = k.build(run, fp)
            builds += 1
            spent += took
            if not ok:
                notes.append(f"key {key_hash(p['key'])}: {k.why}")
                continue
        rc, cases, log, took = test_line(k, p, i, run, timeout)
        spent += took
        ok, why = proven(rc, cases, p)
        if ok and fingerprint(root) != fp:
            ok, why = False, "the worktree changed while the line ran"
        if ok:
            passes.append((i, f"xcode build ({took:.0f}s, {os.path.relpath(log, root)})"))
        else:
            notes.append(f"{i}: not proven ({why}); it runs alone")
    for i, summary in passes:
        print(f"{i}\tPASS\t{summary}")
    print(f"S\t{builds}\t{spent:.0f}\txcode")
    print(f"E\t{segment[-1][0]}")
    if notes:
        try:
            with open(os.path.join(logdir, "xcode-runner.log"), "a", encoding="utf-8") as fh:
                fh.write("".join(n + "\n" for n in notes))
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
