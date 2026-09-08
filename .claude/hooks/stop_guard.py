#!/usr/bin/env python3
"""Stop — a hop does not end without a hop edge (I1).

The last assistant message must end at STITCH NEEDED. Exit 2 blocks the stop and
returns stderr to Claude. Silent unless the repo is actually running a cascade.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

EDGES = ("STITCH NEEDED:", "BARBAR ", "LOOP REFUSED", "BLOCKED", "AUTOPILOT HALT")   # an actionable halt is an ending
HALT = "AUTOPILOT HALT"


def halting(text: str) -> bool:
    """A halt is one the agent is *issuing*, not one it quotes.

    Prose that shows the halt format — documentation, an explanation, a changelog entry — is text. Treating
    it as a halt stops a session that never started a hop (bash_guard made the same mistake with commit
    messages that named a guarded command). Code fences and inline code spans are quotation; everything
    else counts, wherever on the line it appears.
    """
    out, fenced = [], False
    for ln in text.splitlines():
        st = ln.strip()
        if st.startswith("```") or st.startswith("~~~"):
            fenced = not fenced
            continue
        if not fenced:
            out.append(re.sub(r"`[^`]*`", "", ln))
    return HALT in "\n".join(out)


def _log(root: str, verdict: str, detail: str) -> None:
    try:
        sys.path.insert(0, os.path.join(root, "tests", "lib"))
        from decisions import record   # noqa: PLC0415
        record(root, "stop_guard", verdict, detail)
    except Exception:
        pass


def autopilot_status(root: str) -> str:
    try:
        return subprocess.run([sys.executable, "-B", os.path.join(root, "tests", "lib", "autopilot.py"), "--status", root],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return "off"


def continue_autopilot(root: str, session: str, status: str, last: str) -> bool:
    """Block the stop while signed edges remain — bounded, and never past an explicit HALT."""
    if not status.startswith("next"):
        return False
    if halting(last):
        return False
    plan_len = 1
    try:
        env = open(os.path.join(root, "docs", "cascade", "envelope.md"), encoding="utf-8", errors="replace").read()
        m = re.search(r"^AUTOPILOT:[ \t]*(.*?)[ \t]*$", env, re.M)
        plan_len = max(1, len([x for x in (m.group(1) if m else "").split(",") if x.strip()]))
    except OSError:
        pass
    cap = 4 * plan_len + 4
    counter = os.path.join(root, ".git", f"cascade-autopilot-{session or 'session'}")
    try:
        n = int(open(counter).read().strip()) if os.path.exists(counter) else 0
    except ValueError:
        n = 0

    # A hop count is a poor proxy for cost: one slice stuck on a build can burn a night inside the cap.
    # BDD_AUTOPILOT_MINUTES puts a wall-clock ceiling on the whole run (0 or unset = no ceiling).
    started = counter + "-started"
    try:
        limit = float(os.environ.get("BDD_AUTOPILOT_MINUTES", "0") or 0)
    except ValueError:
        limit = 0
    now = __import__("time").time()
    if n == 0:
        try:
            open(started, "w").write(str(now))
        except OSError:
            pass
    elif limit > 0:
        try:
            elapsed = (now - float(open(started).read().strip())) / 60
        except (OSError, ValueError):
            elapsed = 0
        if elapsed >= limit:
            _log(root, "BUDGET", f"wall-clock budget {limit:g} min reached after {n} hops — stopped for a human")
            print(f"autopilot: {limit:g}-minute budget reached after {n} hops — stopping so a human can look. "
                  f"Committed work is safe; resume with /barbar auto.", file=sys.stderr)
            return False
    if n >= cap:
        _log(root, "CAP", f"continuation cap {cap} reached after {n} hops — stopped for a human")
        print(f"autopilot: continuation cap reached ({cap}) — stopping so a human can look.", file=sys.stderr)
        return False
    with open(counter, "w") as fh:
        fh.write(str(n + 1))
    return True


def last_assistant_text(path: str) -> str:
    last = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("type") != "assistant":
                    continue
                content = (rec.get("message") or {}).get("content") or []
                text = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
                if text.strip():
                    last = text
    except OSError:
        return ""
    return last


def _already(ev: dict, root: str) -> bool:
    """Plugin and project hooks may both be wired; a prompt/stop is handled once."""
    k = (ev.get("prompt_id") or "") + "-" + str(ev.get("hook_event_name", "")) + "-" + str(ev.get("source", ""))
    if not ev.get("prompt_id") or not root:
        return False
    try:
        gitdir = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
        d = os.path.join(gitdir, "cascade-seen"); os.makedirs(d, exist_ok=True)
        m = os.path.join(d, "stop_guard.py-" + k[:120])
        if os.path.exists(m):
            return True
        open(m, "w").close(); return False
    except Exception:
        return False


def hop_evidence_ok(root: str, hop: str, stage: str) -> tuple[bool, str]:
    """I10: an EXECUTE hop may not ask for accept without having run this hop's own review command.

    Which command that is depends on the stage — stage 10 is judged by tests/audit.sh, every other stage
    by tests/loop.sh (autopilot.py draws the same line). Asking a stage-10 punch hop for a loop receipt
    demands evidence that stage does not produce, and blocks a hop that is in fact finished.

    loop.sh writes a receipt naming the hop and fingerprinting the working tree when it reaches n/n. A
    missing receipt means it never passed; a stale fingerprint means the code changed afterwards, so the
    evidence no longer describes what the human is being asked to accept. Stage 10 is scored live instead:
    audit.sh is cheap, reads the tree, and has no state to go stale.
    """
    if stage == "10":
        try:
            r = subprocess.run(["bash", os.path.join(root, "tests", "audit.sh")], cwd=root,
                               capture_output=True, text=True, timeout=900)
        except Exception:
            return True, ""   # cannot verify: do not invent a failure
        if r.returncode == 0:
            return True, ""
        score = next((l for l in r.stdout.splitlines() if l.startswith("AUDIT ")), "").strip()
        return False, f"tests/audit.sh does not say CLEAN{' (' + score + ')' if score else ''}"

    path = os.path.join(root, ".cascade", "loop-receipt")
    try:
        rhop, rstage, rsha = open(path, encoding="utf-8").read().split()
    except (OSError, ValueError):
        return False, "tests/loop.sh has not reported LOOP n/n for this hop"
    if (rhop.upper(), rstage) != (hop.upper(), stage):
        return False, f"the only loop receipt is for {rhop} {rstage}, not {hop} {stage}"
    try:
        now = subprocess.run(["bash", "-c", f'. "{root}/tests/lib/cascade.sh"; cascade_worktree_sha "{root}"'],
                             capture_output=True, text=True, timeout=120).stdout.strip()
    except Exception:
        return True, ""
    if now and now != rsha:
        return False, "the tree changed after tests/loop.sh passed — that run does not describe this code"
    return True, ""


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    root0 = None
    try:
        root0 = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
                               capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        root0 = None
    if root0 and _already(ev, root0):
        return 0
    # Autopilot: a signed list means "keep going" — even across repeated stops — until done, HALT, or the cap.
    # The Stop event carries the final text directly; the transcript is only a fallback (its format varies).
    last_msg = (ev.get("last_assistant_message") or "").strip() or last_assistant_text(ev.get("transcript_path", ""))
    if root0:
        status = autopilot_status(root0)
        if status.startswith("next"):
            last = last_msg
            if last and any(e in last for e in EDGES) and continue_autopilot(root0, ev.get("session_id", ""), status, last):
                print(f"AUTOPILOT: signed edges remain — {status}. Advance docs/cascade/envelope.md to exactly that edge "
                      f"(the hooks verify), do the hop, end with its edge line. To stop early, end with "
                      f"'{HALT}: <reason>'.", file=sys.stderr)
                return 2
    if root0 and halting(last_msg) and "WHAT TO DO" in last_msg:
        first = next((l.strip() for l in last_msg.splitlines() if l.strip().lstrip("#*-> ").startswith(HALT)), HALT)
        _log(root0, "HALT", first)
    # A HALT that does not tell the human what to do leaves the product stalled. Send it back once.
    if root0 and halting(last_msg) and "WHAT TO DO" not in last_msg and not ev.get("stop_hook_active"):
        print("AUTOPILOT HALT is missing its instruction block. A halt with no next step stalls the product.\n"
              "Re-print the halt with these lines filled in:\n"
              "  BOTTLENECK:  <what is blocking, naming the file/law/command>\n"
              "  WHAT TO DO:  <exact copy-pasteable commands or edits for the human>\n"
              "  IF YOU DISAGREE: <the alternative>\n"
              "  RESUME WITH: /barbar auto\n"
              "  DONE SO FAR: <slices completed, what is safe to merge>",
              file=sys.stderr)
        return 2

    if ev.get("stop_hook_active"):
        return 0

    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return 0

    env_path = os.path.join(root, "docs", "cascade", "envelope.md")
    hop = stage = ""
    try:
        with open(env_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("CURRENT_HOP:"):
                    hop = line.split(":", 1)[1].strip().upper()
                elif line.startswith("CURRENT_STAGE:"):
                    stage = line.split(":", 1)[1].strip()
    except OSError:
        return 0
    if hop not in ("GENERATE", "EXECUTE"):
        return 0

    # I10: do not let the human be asked to accept an EXECUTE hop with no loop behind it.
    if root and hop == "EXECUTE" and "STITCH NEEDED: accept execute" in last_msg and not halting(last_msg) \
            and not ev.get("stop_hook_active"):
        good, why = hop_evidence_ok(root, hop, stage)
        if not good:
            _log(root, "NOEVID", f"accept asked for on EXECUTE {stage} — {why}")
            cmd = "tests/audit.sh" if stage == "10" else "tests/loop.sh"
            print(f"Asking for accept without evidence (I10): {why}.\n"
                  f"Run `bash {cmd}` and print the score it emits. If it is not clean, fix the hop — "
                  f"do not ask for accept. If the work is genuinely blocked, end with an AUTOPILOT HALT block "
                  f"or say plainly what is unfinished.", file=sys.stderr)
            return 2

    last = last_msg
    if not last:
        return 0
    if any(e in last for e in EDGES):
        return 0

    edge = ("review spec+plan" if hop == "GENERATE" else "accept execute")
    print(
        f"Hop not closed (I1). This is {hop} stage {stage or 'N'}. Every hop ends by "
        f"printing the invariant block and then exactly one edge line:\n"
        f"  STITCH NEEDED: {edge} for stage {stage or 'N'}"
        + (", or send back." if hop == "EXECUTE" else ".") + "\n"
        "Print it now and stop. Do not start the next hop.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
