#!/usr/bin/env python3
"""UserPromptSubmit — the seam between the cascade and craft skills (I14), as mechanism.

While a cascade is running, every prompt gets the current hop class and the skills that are
legal on it, from docs/cascade/skill-binding.md. Cascade precedence is stated each time.
Silent when CURRENT_HOP is NONE, so it costs nothing outside a cascade.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_event, clear_nudges, repo_root
except Exception:
    raise SystemExit(0)   # a prompt must go through even if this module is missing; it binds nothing

NAME = "seam.py"

DESIGN = {"01", "02", "03", "04"}
AUDIT = {"10"}
PRR = {"11"}


def ap_status(root: str) -> str:
    """t87: autopilot's own answer (one source of truth), or '' when it cannot run — then the raw line is used."""
    try:
        return subprocess.run([sys.executable, "-B", os.path.join(root, "tests", "lib", "autopilot.py"), "--status", root],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:  # noqa: BLE001
        return ""


def autopilot_sentence(root: str, autopilot: str) -> str:
    """The seam's AUTOPILOT line, from autopilot.py's status (t87): an off-list hop is not told it may advance."""
    on = (f"AUTOPILOT is ON: signed list = {autopilot}. You may advance CURRENT_HOP yourself ONLY to the next "
          f"signed edge (GENERATE->EXECUTE needs the slice's spec doc; EXECUTE->next needs `bash tests/loop.sh` n/n). "
          f"Still print the edge line at every hop. Stages 10/11 and merge remain human.")
    if not autopilot:
        return "AUTOPILOT is off: every hop edge is the human's."
    st = ap_status(root)
    if st.startswith("off-list"):
        return (f"AUTOPILOT is signed ({autopilot}) but this hop is not on it: every edge of this hop is the human's. "
                f"Do not advance toward the list; finish this hop and print its edge line.")
    if st == "done":
        return on + " This is the list's last entry: after its accept, propose emptying the AUTOPILOT: line."
    return on


ROUTE_STEPS = {   # t91: bdd-work's evidence chain per route, as steps to copy into the todo list verbatim (pstack's trick)
    "investigation": ("cite paths or commands, change nothing",
                      "1) find the code that answers it 2) read it, do not guess 3) answer with path:line or a command's output"),
    "bug-fix": ("reproduce → cause → regression check → observed result",
                "1) reproduce the failure and show it 2) name the cause in the code 3) add or use a check that fails now "
                "4) fix 5) run the check and show it passing"),
    "feature": ("tie the behavior to the accepted slice and its acceptance checks; do not widen it",
                "1) name the acceptance check it must pass 2) build the smallest change that passes it 3) run the check"),
    "refactor": ("say what stays constant, run its existing checks before and after",
                 "1) name the behavior that must not change 2) run its checks 3) restructure 4) run the same checks"),
    "verification": ("run the real artifact and report the command and its output",
                     "1) pick the command that proves it 2) run it 3) report the exact result, not a proxy"),
}


def route_lines(root: str, hop: str, prompt: str, idle: bool) -> str:
    """t91: the deterministic route of this prompt (tests/lib/route.py) — advice, never a refusal."""
    if not (prompt or "").strip():
        return ""   # no prompt text, nothing to route: the context stays exactly as before t91
    try:
        sys.path.insert(0, os.path.join(root, "tests", "lib"))
        import route   # noqa: PLC0415
        name, words = route.classify(prompt or "")
    except Exception:  # noqa: BLE001
        return ""
    if idle and name not in ("bug-fix", "feature", "refactor"):
        return ""   # a plain question at NONE gets nothing
    if name == "ambiguous":
        return "\nROUTE ambiguous — pick a route with bdd-work (investigation, bug-fix, feature, refactor, verification)."
    chain, steps = ROUTE_STEPS[name]
    out = f"\nROUTE {name} (matched: {', '.join(words)}) — {chain}\nSTEPS (copy into your todo list verbatim): {steps}"
    if hop == "GENERATE" and name == "bug-fix":
        out += "\nHINT: the failing regression test goes in the frozen oracle; it must fail on this tree (tag the brief [bug-fix], t91)."
    elif hop == "EXECUTE" and name == "feature":
        out += "\nHINT: out of slice unless the spec names it — brief it instead of building it."
    return out


def hop_class(hop: str, stage: str) -> str | None:
    hop = hop.upper()
    if hop == "GENERATE":
        return "GENERATE"
    if hop == "EXECUTE":
        st = stage.split()[0] if stage else ""
        if st in DESIGN:
            return "EXECUTE-DESIGN"
        if st in AUDIT:
            return "EXECUTE-AUDIT"
        if st in PRR:
            return "EXECUTE-PRR"
        return "EXECUTE-BUILD"
    return None


def shard_reads(root: str, env_path: str, shards: str, stage: str, slice_: str, hop: str) -> str:
    """The law shards this hop reads (t67). Before the slice's spec exists: every shard with its count and id range,
    and read those the brief's modules touch. Once it exists: the shards it names. EXECUTE adds the affected ones.
    No Gradle here — a prompt hook must stay fast; affected.sh is the agent's to run."""
    rows = subprocess.run([sys.executable, "-B", os.path.join(root, "tests", "lib", "laws.py"), env_path, "--summary",
                           "--shards", shards], capture_output=True, text=True, timeout=30).stdout.splitlines()
    summ = {os.path.relpath(r.split("|")[0], root): r.split("|")[1:] for r in rows if r.count("|") == 3}
    spec = os.path.join(root, "docs", "cascade", f"{stage}-{slice_}.md")
    if slice_ and os.path.isfile(spec):
        text = open(spec, encoding="utf-8", errors="replace").read()
        named = sorted({f"docs/cascade/laws/{m}" for m in re.findall(r"docs/cascade/laws/([\w.-]+\.md)", text)
                        if m != "README.md"})
        line = ("LAW SHARDS THIS HOP: " + (", ".join(named) if named else "none named by the spec")
                + f" (from docs/cascade/{stage}-{slice_}.md).")
    else:
        listing = "; ".join(f"{f}: {c} law{'' if c == '1' else 's'}, {a}" + (f"–{b}" if b != a else "")
                            for f, (c, a, b) in sorted(summ.items()))
        line = ("LAW SHARDS THIS HOP: no spec yet — read the shards the brief's modules touch, and STOP if the brief "
                f"conflicts with any law (AGENTS rule 5). Shards: {listing or 'none declare a law'}.")
    if hop.upper() == "EXECUTE":
        line += " Also run `bash tests/affected.sh --shards` for the shards this diff reaches."
    return line


def main() -> int:
    try:
        ev = json.load(sys.stdin)
        root = repo_root(ev.get("cwd") or os.getcwd())
        if not root:
            return 0
        clear_nudges(root, ev.get("session_id", ""))   # a human prompt: the Stop hook's nudge count starts over (t63)
        if already_event(ev, root, NAME, "prompt_id"):
            return 0
        env_path = os.path.join(root, "docs", "cascade", "envelope.md")   # laws
        hop_path = os.path.join(root, "docs", "cascade", "hop-state.md")
        if not os.path.exists(hop_path):
            hop_path = env_path
        shards = os.path.join(root, "docs", "cascade", "laws")   # law shards (t67)
        has_shards = os.path.isdir(shards) and any(
            f.endswith(".md") and f != "README.md" for f in os.listdir(shards))
        if not os.path.exists(env_path) and not has_shards:
            plug = os.environ.get("BDD_PLUGIN_ROOT", "")
            if plug and not os.path.exists(os.path.join(root, "tests", "barbar.sh")):
                ctx0 = ("BDD PLUGIN ACTIVE, NOT INSTALLED IN THIS REPO. If this prompt asks for a feature, a fix or a change, "
                        f"first offer to install the repo-side layers: run `bash {plug}/install.sh .` (the human's approval "
                        "of that command is their consent), commit the result (`cascade: install`), then treat the prompt "
                        f"as a brief: write docs/cascade/05b-briefs.md and propose the edge in {os.path.relpath(hop_path, root)} "
                        "(the human approves that edit). If it is a question, just answer. Never set CASCADE_HUMAN.")
                json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx0}}, sys.stdout)
            return 0
        hop = stage = slice_ = autopilot = ""
        with open(hop_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("CURRENT_HOP:"):
                    hop = line.split(":", 1)[1].strip()
                elif line.startswith("CURRENT_STAGE:"):
                    stage = line.split(":", 1)[1].strip()
                elif line.startswith("CURRENT_SLICE:"):
                    slice_ = line.split(":", 1)[1].strip()
                elif line.startswith("AUTOPILOT:"):
                    autopilot = line.split(":", 1)[1].strip()
        cls = hop_class(hop, stage)
        if cls is None:
            # No hop running: a feature/bug request is the start of a cascade. Draft, then ask the human to sign.
            if os.path.exists(env_path):
                ctx0 = ("CASCADE IDLE (no hop running). If this prompt asks for a feature, a fix or a change: (1) write a "
                        "one-paragraph brief for it into docs/cascade/05b-briefs.md; (2) propose the edge by editing "
                        f"{os.path.relpath(hop_path, root)} — set AUTOPILOT: 05b <slug> (overnight) or CURRENT_HOP: GENERATE / "
                        "CURRENT_STAGE: 05b / CURRENT_SLICE: <slug> (one hop at a time). The hook will ask the human to "
                        "approve that edit; their approval is the signature — never bypass it, never set CASCADE_HUMAN. "
                        "(3) commit, then continue with /barbar auto or the GENERATE hop. If it is a question, just answer.")
                st = ap_status(root) if autopilot else ""
                if st.startswith("stale"):
                    ctx0 += (f"\nA signed AUTOPILOT list is stale ({st}): propose emptying it, or re-signing only the "
                             f"remaining entries, before starting anything.")
                ctx0 += route_lines(root, "NONE", ev.get("prompt", ""), idle=True)
                json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx0}}, sys.stdout)
            return 0
        allow = deny = "(binding table missing: docs/cascade/skill-binding.md)"
        try:
            with open(os.path.join(root, "docs", "cascade", "skill-binding.md"), encoding="utf-8") as fh:
                for line in fh:
                    m = re.match(r"^\s*([A-Z-]+)\s*\|\s*allow:\s*(.*?)\s*\|\s*deny:\s*(.*?)\s*$", line)
                    if m and m.group(1) == cls:
                        allow, deny = m.group(2) or "(none)", m.group(3) or "(none)"
        except OSError:
            pass
        loop_ok = cls == "EXECUTE-BUILD"
        # A forgotten disable must not masquerade as a live seam (AC4). Layer 0 still holds.
        disabled = os.path.isfile(os.path.join(root, ".cascade", "disabled", "state.json"))
        ctx = (
            ("BDD DISABLED — no hop seam in force. Layers 1 and 2 are stood down in this repo; Layer 0 "
             "(CI + branch protection) still is, so this work cannot merge. Re-enable with `bdd enable`.\n"
             if disabled else "")
            + f"CASCADE SEAM (I14): Current hop {hop} stage {stage}{' slice ' + slice_ if slice_ else ''} — class {cls}.\n"
            f"Skills allowed this hop: {allow}.\n"
            f"Skills denied this hop: {deny}.\n"
            f"`bash tests/loop.sh` is {'legal' if loop_ok else 'ILLEGAL'} on this hop. "
            f"Cascade outranks every skill: a skill that says 'do not pause' loses to I1 — stop at STITCH NEEDED. "
            f"Name any skipped skill in the hop report.\n"
            f"Laws (D#) apply to every account, tier, flag, mode and currency. A slice never carves an exception "
            f"into a law and never adds a test under an existing D#; if the slice needs the law to change, STOP "
            f"and say so at the edge (I6/I13).\n"
            + autopilot_sentence(root, autopilot)
        )
        try:
            _laws = [sys.executable, "-B", os.path.join(root, "tests", "lib", "laws.py"), env_path]
            _r = subprocess.run(_laws + ["--in-force", "--shards", shards], capture_output=True, text=True, timeout=30)
            if _r.returncode != 0:
                # No rows from a FATAL read is not "no law in force" (t67).
                ctx += ("\nLAWS UNREADABLE: " + ((_r.stderr.strip().splitlines() or ["tests/lib/laws.py failed"])[0])
                        + " — every gate refuses until a human gives one of them a new id. STOP and say so.")
            elif not _r.stdout.strip():
                ctx += "\nNO LAW IN FORCE: propose with `/barbar init` (writes docs/cascade/proposals.md for the human to sign); never write D# lines yourself."
            if has_shards and _r.returncode == 0:
                ctx += "\n" + shard_reads(root, env_path, shards, stage, slice_, hop)
        except (OSError, subprocess.SubprocessError):
            pass
        ctx += route_lines(root, hop.upper(), ev.get("prompt", ""), idle=False)
        json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx}}, sys.stdout)
        return 0
    except Exception as exc:  # never block a prompt; say why the seam is missing
        print(f"cascade seam hook error: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
