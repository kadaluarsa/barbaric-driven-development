#!/usr/bin/env python3
"""PreToolUse(Write|Edit) — deny product writes on a GENERATE hop, and any edit
that would change human-authored <EDIT> tag contents.

Enforces I4 and I15 at the tool call, before the write happens.
"""
from __future__ import annotations

NAME = "hop_guard.py"

import json
import os
import re
import subprocess
import sys

EDIT_BLOCK = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)
DEFAULT_WRITABLE = ("docs/", "evals/", "tests/", ".githooks/", ".claude/", ".github/", ".cursor/", ".windsurf/", ".continue/")


def sign_or_deny(reason: str, ev: dict, root: str, rel: str, after: str | None) -> None:
    """A human-signable change (hop edge, AUTOPILOT/D# line, <EDIT> content, a law's test).

    Interactive session: answer `ask` — the human's approval of the dialog IS the signature (the agent cannot
    click it) — and record the intended content hash so sign_ok.py can turn the approved write into a
    one-shot token that pre-commit honors. Permissions bypassed / headless: no human is present, so deny.
    """
    if ev.get("permission_mode") == "bypassPermissions" or after is None:
        deny(reason + " (no human present to sign: permissions are bypassed — a human signs with CASCADE_HUMAN=1)")
    import hashlib
    try:
        gitdir = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
        with open(os.path.join(gitdir, "cascade-sign-pending"), "a") as fh:
            fh.write(f"{hashlib.sha256(after.encode()).hexdigest()} {rel}\n")
    except Exception:
        deny(reason + " (could not record the signature request)")
    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "HUMAN SIGNATURE NEEDED — approving this edit signs it as the human "
                                        "(the agent cannot). Deny to send it back. " + reason,
        }},
        sys.stdout,
    )
    sys.exit(0)


def deny(reason: str) -> None:
    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }},
        sys.stdout,
    )
    sys.exit(0)


def repo_root(cwd: str) -> str | None:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=cwd,
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return None


def envelope_field(root: str, key: str) -> str:
    path = os.path.join(root, "docs", "cascade", "envelope.md")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith(key + ":"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""


def writable_globs(root: str) -> tuple[str, ...]:
    override = os.path.join(root, "docs", "cascade", "generate-writable.txt")
    try:
        with open(override, encoding="utf-8") as fh:
            pats = [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]
        if pats:
            return tuple(pats)
    except OSError:
        pass
    return DEFAULT_WRITABLE


PROTECTED = re.compile(r"^(CURRENT_(HOP|STAGE|SLICE):|AUTOPILOT:|D[0-9]+\s*\|)", re.M)


def protected_lines(text: str) -> list[str]:
    return sorted(ln.rstrip() for ln in text.splitlines() if PROTECTED.match(ln))


def autopilot_ok(root: str, before: str, after: str) -> bool:
    """A protected change is fine if tests/lib/autopilot.py says it is a pre-signed edge (one source of truth)."""
    import tempfile
    try:
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".before") as b, \
             tempfile.NamedTemporaryFile("w", delete=False, suffix=".after") as a:
            b.write(before); a.write(after)
        rc = subprocess.run([sys.executable, "-B", os.path.join(root, "tests", "lib", "autopilot.py"), b.name, a.name, root],
                            capture_output=True, text=True, timeout=1300).returncode
        os.unlink(b.name); os.unlink(a.name)
        return rc == 0
    except Exception:
        return False


def projected(tool: str, ti: dict, current: str) -> str | None:
    """Text the file would have after this tool call, or None if unknowable."""
    if tool == "Write":
        return ti.get("content", "")
    edits = ti.get("edits") or [ti]
    text = current
    for e in edits:
        old, new = e.get("old_string"), e.get("new_string", "")
        if old is None:
            return None
        if e.get("replace_all"):
            text = text.replace(old, new)
        elif old in text:
            text = text.replace(old, new, 1)
    return text


def is_product(rel: str, root: str) -> bool:
    if rel.endswith(".md") and "/" not in rel:
        return False
    for pat in writable_globs(root):
        if pat.endswith("/") and rel.startswith(pat):
            return False
        if pat == rel or (pat.startswith("*") and rel.endswith(pat[1:])):
            return False
    return True


def already_handled(ev: dict, root: str) -> bool:
    """Project-level and plugin-level hooks may both be wired; the same tool call must be judged once."""
    tid = ev.get("tool_use_id")
    if not tid or not root:
        return False
    try:
        gitdir = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
        d = os.path.join(gitdir, "cascade-seen"); os.makedirs(d, exist_ok=True)
        marker = os.path.join(d, f"{NAME}-{tid}")
        if os.path.exists(marker):
            return True
        open(marker, "w").close()
        for f in os.listdir(d):   # keep the marker dir small
            fp = os.path.join(d, f)
            if os.path.getmtime(fp) < __import__("time").time() - 3600:
                os.unlink(fp)
        return False
    except Exception:
        return False


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return 0

    ti = ev.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    root = repo_root(ev.get("cwd") or os.getcwd())
    if not path or not root:
        return 0

    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(root))
    if rel.startswith("..") or already_handled(ev, root):
        return 0

    hop = envelope_field(root, "CURRENT_HOP").upper()
    stage = envelope_field(root, "CURRENT_STAGE")
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            current = fh.read()
    except OSError:
        current = ""

    # A law's test is the law (I13): an existing tests/inv/* file is human-owned. New ones are welcome.
    if rel.startswith("tests/inv/") and not os.path.exists(os.path.join(root, rel)):
        m = re.match(r"test_(D\d+)", os.path.basename(rel))
        env_path = os.path.join(root, "docs", "cascade", "envelope.md")
        env_text = open(env_path, encoding="utf-8", errors="replace").read() if os.path.exists(env_path) else ""
        law = re.search(rf"^{m.group(1)}\s*\|.*$", env_text, re.M) if m else None
        # The file the law's own validator/twin names is the expected work for an UNPROVEN D# (I13).
        if law and os.path.basename(rel) not in law.group(0):
            sign_or_deny(
                f"'{rel}' adds a test under an existing law {m.group(1)} (I13). "
                "A law's test surface is human-owned — a slice cannot carve an exception or a tier into a law. "
                "If the slice needs the law to change, STOP and put it in the hop report. A new D# id is fine.",
                ev, root, rel, ti.get("content", "") if ev["tool_name"] == "Write" else None,
            )
    if rel.startswith("tests/inv/") and os.path.exists(os.path.join(root, rel)):
        sign_or_deny(
            f"'{rel}' is an existing D# test — human-owned (I13). "
            "Do not change or weaken a law's test; keep the product compatible with it, or STOP and "
            "propose the test change in the hop report. Adding a new tests/inv/ file is allowed.",
            ev, root, rel, projected(ev["tool_name"], ti, current),
        )

    if hop == "GENERATE" and is_product(rel, root):
        deny(
            f"BLOCKED by cascade hop guard (I4/I15): GENERATE stage {stage} may not write "
            f"product code. '{rel}' is product path.\n"
            "GENERATE produces spec + plan only, then stops at STITCH NEEDED. "
            "Ask the human for 'approved, execute stage {}' first.".format(stage or "N")
        )

    # Hop state and D# laws are human-owned, tags or not. Compute the post-edit text and compare.
    if rel == "docs/cascade/envelope.md" and current:
        after = projected(ev["tool_name"], ti, current)
        if after is not None and protected_lines(current) != protected_lines(after):
            if autopilot_ok(root, current, after):
                return 0   # an accepted signed edge — the hop lines may live inside <EDIT>; do not re-block it below
            changed = [l for l in protected_lines(after) if l not in protected_lines(current)]
            sign_or_deny(
                "Hop state, AUTOPILOT and D# lines in docs/cascade/envelope.md are human-owned (I15). "
                "This edit proposes: " + "; ".join(changed)[:300],
                ev, root, rel, after,
            )
    # <EDIT> tags are a cascade-document convention (docs/ and *.md). Source files that merely mention the
    # literal — hooks, tests — are not human-authored documents (this guard once blocked edits to itself).
    if not (rel.startswith("docs/") or rel.endswith(".md")):
        return 0
    if not current or "<EDIT>" not in current:
        return 0

    spans = [m.span(1) for m in EDIT_BLOCK.finditer(current)]
    msg = (f"'{rel}' has human-authored <EDIT> tags (I15). "
           "The agent must not fill, guess, or delete them on its own; a human may accept this edit as theirs.")

    if ev["tool_name"] == "Write":
        before = EDIT_BLOCK.findall(current)
        after_blocks = EDIT_BLOCK.findall(ti.get("content", ""))
        if any(b not in after_blocks for b in before):
            sign_or_deny(msg, ev, root, rel, ti.get("content", ""))
        return 0

    edits = ti.get("edits") or [ti]
    for e in edits:
        old = e.get("old_string") or ""
        if not old:
            continue
        idx = current.find(old)
        lo, hi = (idx, idx + len(old)) if idx >= 0 else (-1, -1)
        touches = "<EDIT>" in old or "</EDIT>" in old or (idx >= 0 and any(lo < s_hi and s_lo < hi for s_lo, s_hi in spans))
        if touches:
            sign_or_deny(msg, ev, root, rel, projected(ev["tool_name"], ti, current))
    return 0


def _guarded() -> int:
    """A guard that crashes must not fail open. Surface it as 'ask' so a human sees it (I18)."""
    try:
        if os.environ.get("CASCADE_HOOK_SELFTEST_RAISE"):
            raise RuntimeError("selftest")
        return main()
    except Exception as exc:
        json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                   "permissionDecisionReason": f"cascade guard {NAME} failed ({exc!r}); refusing to fail open — a human must decide."}}, sys.stdout)
        return 0


if __name__ == "__main__":
    raise SystemExit(_guarded())
