#!/usr/bin/env python3
"""Stand BDD's local layers down, reversibly — and never Layer 0.

`bdd disable` is for debugging something unrelated inside a BDD repo. It stands down
Layer 1 (git hooks) and Layer 2 (agent hooks) and records *exactly* what it replaced
under `.cascade/disabled/`, so `enable` restores bytes rather than re-asserting the
pack's defaults. Re-asserting is what loses a repo's local settings.

Layer 0 — the CI workflow and branch protection — is never touched. Work done while
disabled still goes red in CI and still cannot merge. Without that, this is a merge
bypass, which is the I18 violation the pack exists to catch (T53 proves it).

  python3 tests/lib/disable.py <repo> --disable
  python3 tests/lib/disable.py <repo> --enable
  python3 tests/lib/disable.py <repo> --status     # prints "disabled" or "enabled"
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

STATE_DIR = ".cascade/disabled"
HOOKS_SNAPSHOT = "settings.hooks.json"
ORIGINAL = "settings.json.orig"
STATE = "state.json"
SETTINGS = ".claude/settings.json"


def _git(repo: Path, *args: str) -> tuple[int, str]:
    p = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True,
        # A hook-driven parent exports these; inherited, they point git at the wrong tree.
        env={k: v for k, v in __import__("os").environ.items()
             if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
                          "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR")},
    )
    return p.returncode, p.stdout.strip()


def state_dir(repo: Path) -> Path:
    return repo / STATE_DIR


def is_disabled(repo: Path) -> bool:
    """True when this repo has been stood down. Cheap — every status surface calls it."""
    return (state_dir(repo) / STATE).is_file()


def disabled_since(repo: Path) -> str:
    try:
        return json.loads((state_dir(repo) / STATE).read_text()).get("since", "unknown")
    except Exception:
        return "unknown"


def disable(repo: Path) -> int:
    sd = state_dir(repo)
    if is_disabled(repo):
        # Idempotent, and specifically: never overwrite the saved state with the
        # already-stripped state. That would make `enable` restore the disabled form.
        print("BDD already DISABLED — state left as it was")
        print(f"  re-enable with: bdd enable")
        return 0

    sd.mkdir(parents=True, exist_ok=True)
    rc, prior = _git(repo, "config", "--get", "core.hooksPath")
    prior_hookspath = prior if rc == 0 and prior else None

    # Layer 1 — stand down, remembering whatever was there (which may be nothing).
    if prior_hookspath is not None:
        _git(repo, "config", "--unset", "core.hooksPath")

    # Layer 2 — lift the hooks block out verbatim. Restoring these exact bytes is the
    # point: regenerating the block from the pack silently drops hook entries the
    # product added for itself.
    settings = repo / SETTINGS
    hooks_count = 0
    if settings.is_file():
        original = settings.read_text()
        try:
            doc = json.loads(original)
        except Exception:
            doc = None
        if isinstance(doc, dict) and "hooks" in doc:
            hooks = doc.pop("hooks")
            hooks_count = sum(len(v) for v in hooks.values() if isinstance(v, list))
            # The whole original file, verbatim. Restoring a re-serialized document is not
            # byte-for-byte: json.dumps normalizes indentation and moves the reinserted key
            # to the end. Key order in a file a human reads is worth preserving.
            (sd / ORIGINAL).write_text(original)
            (sd / HOOKS_SNAPSHOT).write_text(json.dumps(hooks, indent=2) + "\n")
            settings.write_text(json.dumps(doc, indent=2) + "\n")

    _, head = _git(repo, "rev-parse", "--short", "HEAD")
    (sd / STATE).write_text(json.dumps({
        "since": head or "unknown",
        "hooksPath": prior_hookspath,
        "hooks_stripped": hooks_count,
    }, indent=2) + "\n")

    version = (repo / "VERSION").read_text().strip() if (repo / "VERSION").is_file() else "?"
    print(f"BDD DISABLED — {repo.name} {version}")
    print()
    was = prior_hookspath if prior_hookspath else "(unset)"
    print(f"  L1  hooksPath     core.hooksPath was {was} -> unset")
    print(f"  L1  git hooks     stood down (files untouched)")
    print(f"  L2  agent hooks   {hooks_count} hooks stripped from {SETTINGS}")
    print(f"  L0  CI            UNTOUCHED — CI still runs the farm, merge gate still refuses")
    print()
    print(f"  state saved to {STATE_DIR}/ (gitignored)")
    print(f"  re-enable with: bdd enable")
    return 0


def enable(repo: Path) -> int:
    sd = state_dir(repo)
    if not is_disabled(repo):
        print("BDD is not disabled — nothing to restore")
        return 0

    saved = json.loads((sd / STATE).read_text())

    # Layer 1 — put back exactly what was there, including "there was nothing".
    prior = saved.get("hooksPath")
    if prior:
        _git(repo, "config", "core.hooksPath", prior)
    else:
        _git(repo, "config", "--unset", "core.hooksPath")

    # Layer 2 — the saved bytes, not the pack's idea of them.
    snap = sd / HOOKS_SNAPSHOT
    orig = sd / ORIGINAL
    restored = 0
    edited = False
    settings = repo / SETTINGS
    if snap.is_file() and settings.is_file():
        hooks = json.loads(snap.read_text())
        restored = sum(len(v) for v in hooks.values() if isinstance(v, list))
        current = settings.read_text()
        doc = json.loads(current)
        stripped_form = json.dumps(doc, indent=2) + "\n"
        if orig.is_file() and current == stripped_form:
            # Untouched since disable — put the original bytes back exactly.
            settings.write_text(orig.read_text())
        else:
            # Someone edited settings.json while disabled. Their edits win; merge the
            # hooks block back rather than reverting work they did on purpose.
            doc["hooks"] = hooks
            settings.write_text(json.dumps(doc, indent=2) + "\n")
            edited = True

    for f in (snap, orig, sd / STATE):
        if f.exists():
            f.unlink()
    try:
        sd.rmdir()
    except OSError:
        pass

    print("BDD ENABLED — the pipeline is back")
    print()
    print(f"  L1  hooksPath     core.hooksPath -> {prior if prior else '(unset, as before)'}")
    print(f"  L2  agent hooks   {restored} hooks restored to {SETTINGS}")
    if edited:
        print(f"      (that file was edited while disabled — your edits kept, hooks merged back)")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 64
    repo = Path(argv[0]).resolve()
    mode = argv[1]
    if not (repo / ".git").exists():
        rc, _ = _git(repo, "rev-parse", "--is-inside-work-tree")
        if rc != 0:
            print(f"not a git repo: {repo}", file=sys.stderr)
            return 1
    if mode == "--disable":
        return disable(repo)
    if mode == "--enable":
        return enable(repo)
    if mode == "--status":
        print("disabled" if is_disabled(repo) else "enabled")
        return 0
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
