#!/usr/bin/env python3
"""Which settings the pack adds to the Gradle builds it builds itself (t69).

Only two kinds of build ever get them: the loop runner's batched builds (`runner`, tests/lib/gradle_runner.py) and
the law harness's law builds (`harness`, tests/lib/law_harness.py). A line run alone, a law's own `check:`/`break:`,
affected.py's module-map build and the user's own builds are never changed. docs/cascade/05b-t69-gradle-tuning.md is
the contract.

    flags(root, entry, globals_, kind) -> (args, env, notes)

  * BDD_GRADLE_TUNING=off: nothing at all — no flag, no env, no note — so every output is what it was before t69.
  * `--configuration-cache` (runner only): only when the user said nothing about it anywhere Gradle reads (the line,
    GRADLE_OPTS, the project's, the user home's and the install's gradle.properties) and no live drop row exists.
  * `--offline` (both): only when `- GRADLE_OFFLINE: on` is signed inside <EDIT> in the envelope, at HEAD and in the
    working tree alike.
  * BDD_LAW_FORKS=<n> (harness only): only when `- DSHARP_GRADLE_FORKS: on` is signed the same way.

A drop row (.cascade/gradle/tuning.tsv) only ever REMOVES a flag, so a forged or stale file can make a run slower,
never more lenient. It holds while the build-logic fingerprint is unchanged.

The messages read below were measured in E0 (2026-10-22) on Gradle 8.5 and 9.1.0; see REJECT and DAEMON.
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from signed import BLOCK   # noqa: E402  (sibling: tests/lib ships as one directory)

CC = "--configuration-cache"
OFFLINE = "--offline"
# Any key under these names is the user's decision about the configuration cache (problems=warn included: E0 showed
# a warn-mode build stores an entry WITH problems, which a pack-added flag must not start reusing).
CC_PROP = re.compile(r"^-D(org\.gradle\.(?:unsafe\.)?configuration-cache(?:\.[\w.-]+)?)(?:=|$)")
OFFLINE_SWITCH = re.compile(r"^\s*-\s*GRADLE_OFFLINE:\s*(on|off)(?=\s|$)")
FORKS_SWITCH = re.compile(r"^\s*-\s*DSHARP_GRADLE_FORKS:\s*(on|off)(?=\s|$)")
# E0, Gradle 8.5: `* What went wrong:` / `Configuration cache problems found in this build.`
#     Gradle 9.1.0: `* What went wrong:` / `> Invocation of 'Task.project' … is unsupported with the configuration cache.`
#     Both, when not quiet: `Configuration cache entry discarded with N problem(s).`
#     Both, offline: `> No cached version of <module> available for offline mode.` inside `* What went wrong:`.
REJECT = {
    # Only "discarded with N problem(s)" is a rejection: Gradle also prints "discarded because incompatible task was
    # found" for a build that works, and a failing test there must not cost the flag (review finding).
    CC: (re.compile(r"configuration cache", re.I), re.compile(r"^Configuration cache entry discarded with \d+ problems?", re.M)),
    OFFLINE: (re.compile(r"available for offline mode"), None),
}
DAEMON = re.compile(r"^Starting a Gradle Daemon(.*)$", re.M)
QUIET = ("-q", "--quiet", "-w", "--warn")
TSV = os.path.join(".cascade", "gradle", "tuning.tsv")


def tuning_off() -> bool:
    return os.environ.get("BDD_GRADLE_TUNING", "") == "off"


# --- what the user already decided ---------------------------------------------------------------------------

def _props_files(root: str) -> list[tuple[str, str]]:
    home = os.environ.get("GRADLE_USER_HOME") or os.path.join(os.path.expanduser("~"), ".gradle")
    out = [("the project's gradle.properties", os.path.join(root, "gradle.properties")),
           ("GRADLE_USER_HOME/gradle.properties", os.path.join(home, "gradle.properties"))]
    if os.environ.get("GRADLE_HOME"):
        out.append(("GRADLE_HOME/gradle.properties", os.path.join(os.environ["GRADLE_HOME"], "gradle.properties")))
    return out


def user_cc_setting(root: str, globals_: tuple) -> str | None:
    """Where the user set anything about the configuration cache, or None when they said nothing anywhere."""
    for i, g in enumerate(globals_):
        if g in (CC, "--no-configuration-cache"):
            return f"{g} on the line"
        if CC_PROP.match(g):
            return f"{g} on the line"
        if g in ("-D", "--system-prop") and i + 1 < len(globals_) and CC_PROP.match("-D" + globals_[i + 1]):
            return f"{g} {globals_[i + 1]} on the line"   # the two-token form: gradle_runner takes -D's value apart
    if re.search(r"org\.gradle\.(?:unsafe\.)?configuration-cache", os.environ.get("GRADLE_OPTS", "")):
        return "GRADLE_OPTS"
    for where, path in _props_files(root):
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for line in text.splitlines():
            s = line.strip()
            if s.startswith(("#", "!")):
                continue
            if "configuration-cache" in s:      # a key we cannot parse counts as set
                return where
    return None


# --- what the human signed ------------------------------------------------------------------------------------

def _decision(text: str, pat: re.Pattern) -> bool:
    last = None
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = pat.match(line)
            if m and "{{" not in line:
                last = m.group(1)
    return last == "on"


def signed(root: str, pat: re.Pattern) -> bool:
    """The last such line inside <EDIT> of the envelope says `on`, as committed at HEAD and in the working tree."""
    from gradle_runner import _envelopes   # noqa: E402  (lazy: gradle_runner imports this module)
    texts = _envelopes(root)
    return bool(texts) and all(_decision(t, pat) for t in texts)


# --- drop rows ------------------------------------------------------------------------------------------------

_fp_cache: dict = {}


def _gradle_identity(root: str, entry: str) -> str:
    if entry == "./gradlew":
        from gradle_runner import wrapper_version   # noqa: E402
        return "wrapper " + (wrapper_version(root) or "?")
    exe = shutil.which("gradle")
    if not exe:
        return "gradle ?"
    real = os.path.realpath(exe)
    try:
        return f"gradle {real} {os.stat(real).st_mtime_ns}"
    except OSError:
        return f"gradle {real}"


def fingerprint(root: str, entry: str) -> str:
    """The Gradle identity plus the working-tree contents of every tracked build-logic path."""
    if (root, entry) in _fp_cache:
        return _fp_cache[(root, entry)]
    from affected import is_build_logic   # noqa: E402
    h = hashlib.sha256(_gradle_identity(root, entry).encode())
    r = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True)
    for rel in sorted(p for p in r.stdout.decode("utf-8", "replace").split("\0") if p and is_build_logic(p)):
        h.update(b"\0" + rel.encode())
        try:
            with open(os.path.join(root, rel), "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
        except OSError:
            h.update(b"-")
    _fp_cache[(root, entry)] = h.hexdigest()[:16]
    return _fp_cache[(root, entry)]


def _rows(root: str) -> list[list[str]]:
    try:
        with open(os.path.join(root, TSV), encoding="utf-8", errors="replace") as fh:
            return [ln.rstrip("\n").split("\t") for ln in fh if ln.strip()]
    except OSError:
        return []


def dropped(root: str, flag: str, entry: str) -> str | None:
    fp = fingerprint(root, entry)
    for r in _rows(root):
        if len(r) >= 5 and r[0] == flag and r[1] == entry and r[2] == fp:
            return r[4]
    return None


def drop(root: str, flag: str, entry: str, reason: str) -> None:
    path = os.path.join(root, TSV)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\t".join([flag, entry, fingerprint(root, entry),
                                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                                re.sub(r"[\t\r\n]+", " ", reason)]) + "\n")
    except OSError:
        pass                                  # not remembered: the flag is tried, and rejected, again next run


# --- the decision ---------------------------------------------------------------------------------------------

def flags(root: str, entry: str, globals_: tuple, kind: str) -> tuple[list[str], dict, list[str]]:
    if tuning_off():
        return [], {}, []
    args: list[str] = []
    env: dict = {}
    notes: list[str] = []
    if kind == "runner":
        where = user_cc_setting(root, globals_)
        why = dropped(root, CC, entry)
        if where:
            notes.append(f"configuration cache: set in {where}")
        elif why:
            notes.append(f"configuration cache: dropped — {why}")
        else:
            args.append(CC)
    if signed(root, OFFLINE_SWITCH):
        why = dropped(root, OFFLINE, entry)
        if OFFLINE in globals_ or "--refresh-dependencies" in globals_:
            pass
        elif why:
            notes.append(f"offline: dropped — {why}")
        else:
            args.append(OFFLINE)
    if kind == "harness" and signed(root, FORKS_SWITCH):
        env["BDD_LAW_FORKS"] = str(max(1, (os.cpu_count() or 1) // 2))
    return args, env, notes


def rejected(log: str, added: list[str]) -> tuple[str, str] | None:
    """(flag, reason) when the build's own failure names a flag the pack added, else None."""
    m = re.search(r"^\* What went wrong:\n(.*?)(?=^\* (?:Try|Exception|Get more help)|\Z)", log, re.M | re.S)
    wrong = m.group(1) if m else ""
    for flag in added:
        pats = REJECT.get(flag)
        if not pats:
            continue
        in_wrong, anywhere = pats
        hit = in_wrong.search(wrong) or (anywhere.search(log) if anywhere else None)
        if hit:
            line = next((ln.strip(" >") for ln in wrong.splitlines() if in_wrong.search(ln)), "") or hit.group(0)
            return flag, line[:200]
    return None


def daemon(log: str, globals_: tuple) -> tuple[int | None, str]:
    """Daemons this build started, from Gradle's own line; None when a quiet log may have hidden it."""
    found = DAEMON.findall(log)
    if found:
        last = found[-1].strip(" ,()")
        why = "none was running" if not last or last.startswith("subsequent builds") else last
        return len(found), why
    if any(g in QUIET for g in globals_):
        return None, "quiet log"
    return 0, ""
