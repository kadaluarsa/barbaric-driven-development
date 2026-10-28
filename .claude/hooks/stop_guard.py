#!/usr/bin/env python3
"""Stop — a hop does not end without a hop edge (I1).

The last assistant message must end at STITCH NEEDED. Silent unless the repo is actually running a cascade.

How it talks (t63). Nothing here exits 2 or writes stderr: Claude Code shows both to the human as a "Stop hook
error", for a hook that is working as designed. A nudge for the agent goes in `additionalContext`, which the
agent reads and acts on and the human does not see. A message for the human goes in `systemMessage`, shown as a
notice. Measured on Claude Code 2.1.280 (05b t63 EXECUTE, E0): `decision: block` also continues the turn, but
the human sees a "Stop hook error occurred" notice, so it is not used.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_event, clear_nudges, git_dir, hopstate, log, nudges_path, repo_root
except Exception:
    raise SystemExit(0)   # a Stop hook that always blocks traps the session; degrade to silent

NAME = "stop_guard.py"
ACTOR = NAME[:-3]

EDGES = ("STITCH NEEDED:", "BARBAR ", "LOOP REFUSED", "BLOCKED", "AUTOPILOT HALT")   # an actionable halt is an ending
HALT = "AUTOPILOT HALT"

CHANNEL = "additionalContext"   # E0, t63: the one Stop output the agent reads and the human is not shown
NUDGE_CAP = 2                   # identical nudges in a row before the human is told instead (t63 §4)
FENCE = re.compile(r"^(`{3,}|~{3,})")


def nudgecap_msg(text: str) -> str:
    """What the human is told when one nudge repeats: which one, and that the hop is still open (t63 §4)."""
    first = (text.strip().splitlines() or [""])[0].strip()
    return (f"the stop guard sent the agent the same reminder {NUDGE_CAP + 1} times in a row and it did not act "
            f"on it: \"{first}\" The hop is still open — read the agent's last reply before you decide.")


def emit(to_agent: str = "", to_human: str = "") -> int:
    """End the stop: at most one JSON object on stdout, always exit 0. Nothing at all when both are empty."""
    out: dict = {}
    if to_agent and (os.environ.get("BDD_HOOK_HOST") == "codex" or os.environ.get("PLUGIN_ROOT")):
        # Codex requires decision=block to create a continuation; additionalContext alone is only context.
        out["decision"] = "block"
        out["reason"] = to_agent
    elif to_agent:
        out["hookSpecificOutput"] = {"hookEventName": "Stop", CHANNEL: to_agent}
    if to_human:
        out["systemMessage"] = to_human
    if out:
        print(json.dumps(out))
    return 0


def nudge_allowed(root: str, session: str, text: str) -> bool:
    """t63 §4: count identical nudge texts in a row for this session; the (NUDGE_CAP+1)th is not sent.

    A different text starts the count again, so I10 punch rounds (a new round and score each time) never add
    up. A clean stop clears it here, and seam.py clears it on every human prompt.
    """
    path = nudges_path(root, session)
    key = hashlib.sha256(text.encode("utf-8")).hexdigest()
    prev, n = "", 0
    try:
        parts = open(path, encoding="utf-8").read().split()
        if len(parts) == 2:
            prev, n = parts[0], int(parts[1])
    except (OSError, ValueError):
        pass
    n = n + 1 if prev == key else 1
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"{key} {n}\n")
    except OSError:
        pass
    return n <= NUDGE_CAP


def check_timeout(var: str, default: float) -> float:
    """Seconds one Stop-hook check may take. A check that does not finish sends the agent back (t59), so the
    variable cannot make anything pass: a smaller value refuses sooner, a larger one only waits longer."""
    try:
        v = float(os.environ.get(var, "") or default)
    except ValueError:
        return default
    return v if v > 0 else default


def cause(exc: BaseException, timeout: float) -> str:
    if isinstance(exc, subprocess.TimeoutExpired):
        return f"timed out after {timeout:g}s"
    return f"{type(exc).__name__}: {exc}"


def unquoted(text: str) -> str:
    """The text with fenced blocks and inline code spans removed: what the agent *says*, not what it quotes.

    Prose that shows an edge or halt format — documentation, an explanation, a changelog entry — is text.
    Treating it as an edge started a signed autopilot run from an explanation (t63), and treating it as a halt
    stopped a session that never started a hop (bash_guard made the same mistake with commit messages that
    named a guarded command). Code fences and inline code spans are quotation; everything else counts,
    wherever on the line it appears.

    A fence closes only on the same character, at least as long, with nothing else on the line, so a ````
    block can hold a ``` line. An unclosed fence quotes nothing: the rest of the reply is still text.
    """
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i].strip())
        if m:
            ch, n = m.group(1)[0], len(m.group(1))
            j = i + 1
            while j < len(lines):
                c = lines[j].strip()
                if len(c) >= n and set(c) == {ch}:
                    break
                j += 1
            if j < len(lines):
                i = j + 1
                continue
        out.append(re.sub(r"`[^`]*`", "", lines[i]))
        i += 1
    return "\n".join(out)


def halting(text: str) -> bool:
    """A halt is one the agent is *issuing*, not one it quotes."""
    return HALT in unquoted(text)


def autopilot_status(root: str) -> str:
    try:
        return subprocess.run([sys.executable, "-B", os.path.join(root, "tests", "lib", "autopilot.py"), "--status", root],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return "off"


def continue_autopilot(root: str, session: str, status: str, last: str) -> tuple[bool, str]:
    """Keep the run going while signed edges remain — bounded, and never past an explicit HALT.

    Returns (continue, to_human): when a budget or cap ends the run, the reason is for the human (t63), and the
    caller puts it in `systemMessage`. Printed to stderr on exit 0, as before, nobody saw it.
    """
    if not status.startswith("next"):
        return False, ""
    if halting(last):
        return False, ""
    plan_len = 1
    try:
        env = open(hopstate(root), encoding="utf-8", errors="replace").read()
        m = re.search(r"^AUTOPILOT:[ \t]*(.*?)[ \t]*$", env, re.M)
        plan_len = max(1, len([x for x in (m.group(1) if m else "").split(",") if x.strip()]))
    except OSError:
        pass
    cap = 4 * plan_len + 4
    counter = os.path.join(git_dir(root) or os.path.join(root, ".git"), f"cascade-autopilot-{session or 'session'}")
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
            log(root, ACTOR, "BUDGET", f"wall-clock budget {limit:g} min reached after {n} hops — stopped for a human")
            return False, (f"autopilot: {limit:g}-minute budget reached after {n} hops — stopping so a human can look. "
                           f"Committed work is safe; resume with /barbar auto.")
    if n >= cap:
        log(root, ACTOR, "CAP", f"continuation cap {cap} reached after {n} hops — stopped for a human")
        return False, f"autopilot: continuation cap reached ({cap}) — stopping so a human can look."
    with open(counter, "w") as fh:
        fh.write(str(n + 1))
    return True, ""


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


def spec_gate_red(root: str, last: str) -> str:
    """t57/t58: '' when the spec edge may be asked for, else the failing lines of whichever gate is red.

    Only a GENERATE 05b hop asking for `review spec+plan` is checked; everything else passes untouched.
    Both gates print `n/a` and exit 0 when they do not apply (an untagged brief, for divergence). A gate that
    does not finish counts as red and says why (t59; same rule as the I10 evidence check): a skipped gate
    used to pass silently. The hook fires once per stop, so this sends the agent back once — it is not a wall.
    """
    if "review spec+plan" not in last:
        return ""
    hop = stage = ""
    try:
        for line in open(hopstate(root), encoding="utf-8", errors="replace"):
            if line.startswith("CURRENT_HOP:"):
                hop = line.split(":", 1)[1].strip().upper()
            elif line.startswith("CURRENT_STAGE:"):
                stage = line.split(":", 1)[1].strip()
    except OSError:
        return ""
    if hop != "GENERATE" or stage != "05b":
        return ""
    red = []
    t = check_timeout("CASCADE_STOP_GATE_TIMEOUT", 120)
    for name in ("critique.sh", "diverge.sh"):
        script = os.path.join(root, "tests", name)
        if not os.path.exists(script):
            continue
        try:
            r = subprocess.run(["bash", script], cwd=root, capture_output=True, text=True, timeout=t)
        except Exception as exc:  # noqa: BLE001
            red.append(f"FAIL    tests/{name} did not finish ({cause(exc, t)}) — run `bash tests/{name}` by hand")
            continue
        if r.returncode != 0:
            red.append("\n".join(l for l in r.stdout.splitlines() if l.startswith(("FAIL", "CRITIQUE", "DIVERGE")))
                       or r.stdout[-800:])
    return "\n".join(red)


PUNCH_CAP = 3


def punch_round(root: str, slice_: str, dirty: bool) -> int:
    """Count consecutive DIRTY stage-10 audits for this slice, and return the round number.

    The cap was prose: "At most **3** punch rounds" in the command file, with nothing counting. An agent
    grinding at DIRTY rows all night looks like progress every round and is the specific hazard autopilot
    was given a bar to avoid. A CLEAN audit or a change of slice resets it.
    """
    path = os.path.join(root, ".cascade", "punch-rounds")
    try:
        if not dirty:
            if os.path.exists(path):
                os.unlink(path)
            return 0
        prev_slice, n = "", 0
        if os.path.exists(path):
            parts = open(path, encoding="utf-8").read().split()
            if len(parts) == 2:
                prev_slice, n = parts[0], int(parts[1])
        n = n + 1 if prev_slice == slice_ else 1
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"{slice_ or '-'} {n}\n")
        return n
    except Exception:
        return 0


def hop_evidence_ok(root: str, hop: str, stage: str, slice_: str = "") -> tuple[bool, str, str]:  # (good, why for the agent, note for the human)
    """I10: an EXECUTE hop may not ask for accept without having run this hop's own review command.

    Which command that is depends on the stage — stage 10 is judged by tests/audit.sh, every other stage
    by tests/loop.sh (autopilot.py draws the same line). Asking a stage-10 punch hop for a loop receipt
    demands evidence that stage does not produce, and blocks a hop that is in fact finished.

    loop.sh writes a receipt naming the hop and fingerprinting the working tree when it reaches n/n. A
    missing receipt means it never passed; a stale fingerprint means the code changed afterwards, so the
    evidence no longer describes what the human is being asked to accept. Stage 10 is scored live instead:
    audit.sh reads the tree and has no state to go stale — cheap in a small repo, bounded by its tests in a
    large one.

    A check that cannot finish (timeout, crash, empty fingerprint) refuses and says why (t59). It used to
    pass — "cannot verify: do not invent a failure" — and in a large repo that meant the check was simply
    off. The hook fires once per stop, so this sends the agent back once with the cause; it is not a wall.
    """
    if stage == "10":
        t = check_timeout("CASCADE_STOP_AUDIT_TIMEOUT", 900)
        try:
            r = subprocess.run(["bash", os.path.join(root, "tests", "audit.sh")], cwd=root,
                               capture_output=True, text=True, timeout=t)
        except Exception as exc:  # noqa: BLE001
            # Not a punch round: a round that never scored is not a round.
            return False, (f"tests/audit.sh did not finish ({cause(exc, t)}) — run `bash tests/audit.sh` by hand; "
                           f"the stage-10 edge needs CLEAN"), ""
        if r.returncode == 0:
            punch_round(root, slice_, dirty=False)
            return True, "", ""
        score = next((l for l in r.stdout.splitlines() if l.startswith("AUDIT ")), "").strip()
        n = punch_round(root, slice_, dirty=True)
        if n > PUNCH_CAP:
            log(root, ACTOR, "CAP", f"punch round {n} on stage 10 {slice_} — capped at {PUNCH_CAP}")
            return (False,
                    (f"the stage-10 punch list has run {n} rounds and the audit is still DIRTY "
                     f"({score}). The cap is {PUNCH_CAP}: past that, rounds stop being progress. "
                     f"Halt with the remaining rows and let a human decide whether they are bugs "
                     f"or belong out of scope"),
                    (f"stage-10 punch cap reached for {slice_ or 'this slice'}: the audit is still DIRTY after "
                     f"{PUNCH_CAP} rounds"))
        return False, f"tests/audit.sh does not say CLEAN{' (' + score + ')' if score else ''}", ""

    path = os.path.join(root, ".cascade", "loop-receipt")
    try:
        rhop, rstage, rsha = open(path, encoding="utf-8").read().split()
    except (OSError, ValueError):
        return False, "tests/loop.sh has not reported LOOP n/n for this hop", ""
    if (rhop.upper(), rstage) != (hop.upper(), stage):
        return False, f"the only loop receipt is for {rhop} {rstage}, not {hop} {stage}", ""
    # The repo's own cascade.sh, the same file its loop.sh used for the receipt: in plugin mode this hook is
    # newer than the repo's tests/ until install.sh runs again, and both sides must use one scheme.
    t = check_timeout("CASCADE_STOP_FINGERPRINT_TIMEOUT", 120)
    retry = ("run `bash tests/loop.sh` again; if it keeps failing, check `git status` "
             "(in a plugin-mode repo, re-run install.sh first)")
    try:
        now = subprocess.run(["bash", "-c", f'. "{root}/tests/lib/cascade.sh"; cascade_worktree_sha "{root}"'],
                             capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception as exc:  # noqa: BLE001
        return False, f"could not fingerprint the tree ({cause(exc, t)}) — {retry}", ""
    if not now:
        return False, f"could not fingerprint the tree (the fingerprint came back empty) — {retry}", ""
    if scheme(now) != scheme(rsha):
        return False, ("the loop receipt and this repo's fingerprint come from different pack versions — run "
                       "`bash tests/loop.sh` once; if this repeats, re-run install.sh so the repo's tests/ match the plugin"), ""
    if now != rsha:
        return False, "the tree changed after tests/loop.sh passed — that run does not describe this code", ""
    return True, "", ""


def scheme(fingerprint: str) -> str:
    """`t2` for `t2:<tree>` (t59); '' for the bare sha older packs wrote."""
    return fingerprint.split(":", 1)[0] if ":" in fingerprint else ""


def main() -> int:
    """A Stop hook that cannot run must not trap the session, and must not show the human a traceback (t63)."""
    try:
        return judge()
    except Exception as exc:  # noqa: BLE001
        try:
            root = repo_root(os.getcwd())
            if root:
                log(root, ACTOR, "CRASH", f"{type(exc).__name__}: {exc}")
        except Exception:  # noqa: BLE001
            pass
        return 0


def judge() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    root0 = None
    try:
        root0 = repo_root(ev.get("cwd") or os.getcwd())
    except Exception:
        root0 = None
    if root0 and already_event(ev, root0, NAME, "prompt_id"):
        return 0
    session = ev.get("session_id", "")
    human: list[str] = []   # every note for the human this stop raised, sent with whatever ends it (t63 §2)

    def told() -> str:
        return "\n".join(human)

    def nudge(root: str, text: str, counted: bool = True) -> int:
        """Send the agent back, unless it is the same nudge for the third time in a row (t63 §4).

        `counted=False` for a nudge another cap already bounds: stage-10 punch rounds repeat the same words
        while the score stands still, and PUNCH_CAP, not this count, decides when they stop.
        """
        if counted and not nudge_allowed(root, session, text):
            log(root, ACTOR, "NUDGECAP", f"the same nudge {NUDGE_CAP + 1} times in a row — told the human instead")
            human.append(nudgecap_msg(text))
            return emit(to_human=told())
        return emit(text, told())

    def passed(root: str | None) -> int:
        """A judged stop that sends nothing back: the nudge count starts over."""
        if root:
            clear_nudges(root, session)
        return emit(to_human=told())

    # Autopilot: a signed list means "keep going" — even across repeated stops — until done, HALT, or the cap.
    # The Stop event carries the final text directly; the transcript is only a fallback (its format varies).
    last_msg = (ev.get("last_assistant_message") or "").strip() or last_assistant_text(ev.get("transcript_path", ""))
    said = unquoted(last_msg)   # an edge or halt quoted in code is not one the agent is issuing (t63)
    # t57: a 05b spec reaches the human only with a green critique beside it. Checked before the autopilot
    # branch, which would otherwise wave a signed run straight past the edge.
    if root0 and not ev.get("stop_hook_active"):
        why = spec_gate_red(root0, said)
        if why:
            log(root0, ACTOR, "NOSPECGATE", "review spec+plan asked for on GENERATE 05b with a red spec gate")
            return nudge(root0, "Asking for spec review while a spec gate is red (t57/t58):\n" + why + "\n"
                         "Critique red: dispatch the critic (docs/cascade/product-e2e-gre-pipeline.md, 'Spec critic'), "
                         "commit its rows verbatim, answer every row, then print the edge again. Divergence red before the "
                         "pick: end the reply with the decision-needed halt instead — the human names the option.")
    if root0:
        status = autopilot_status(root0)
        if status.startswith("next") and said and any(e in said for e in EDGES):
            go, note = continue_autopilot(root0, session, status, last_msg)
            if note:
                human.append(note)
            if go:
                log(root0, ACTOR, "CONTINUE", f"signed edges remain — {status}")
                # Not a nudge: autopilot has its own cap, so this neither counts nor resets (t63 §4).
                return emit(f"AUTOPILOT: signed edges remain — {status}. Advance {os.path.relpath(hopstate(root0), root0)} to exactly that edge "
                            f"(the hooks verify), do the hop, end with its edge line. To stop early, end with "
                            f"'{HALT}: <reason>'.", told())
    # The halt's header must be issued, not quoted (halting); its instruction block may sit in a fence, as the
    # template in barbar.md does, so WHAT TO DO is read from the whole reply (code review of t63).
    if root0 and halting(last_msg) and "WHAT TO DO" in last_msg:
        first = next((l.strip() for l in last_msg.splitlines() if l.strip().lstrip("#*-> ").startswith(HALT)), HALT)
        log(root0, ACTOR, "HALT", first)
    # A HALT that does not tell the human what to do leaves the product stalled. Send it back once.
    if root0 and halting(last_msg) and "WHAT TO DO" not in last_msg and not ev.get("stop_hook_active"):
        log(root0, ACTOR, "NOHALTBLOCK", "AUTOPILOT HALT without its WHAT TO DO block")
        return nudge(root0, "AUTOPILOT HALT is missing its instruction block. A halt with no next step stalls the product.\n"
                     "Re-print the halt with these lines filled in:\n"
                     "  BOTTLENECK:  <what is blocking, naming the file/law/command>\n"
                     "  WHAT TO DO:  <exact copy-pasteable commands or edits for the human>\n"
                     "  IF YOU DISAGREE: <the alternative>\n"
                     "  RESUME WITH: /barbar auto\n"
                     "  DONE SO FAR: <slices completed, what is safe to merge>")

    if ev.get("stop_hook_active"):
        return emit(to_human=told())

    try:
        root = repo_root(ev.get("cwd") or os.getcwd())
        if not root:
            return emit(to_human=told())
    except Exception:
        return emit(to_human=told())

    env_path = hopstate(root)
    hop = stage = slice_ = ""
    try:
        with open(env_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("CURRENT_HOP:"):
                    hop = line.split(":", 1)[1].strip().upper()
                elif line.startswith("CURRENT_STAGE:"):
                    stage = line.split(":", 1)[1].strip()
                elif line.startswith("CURRENT_SLICE:"):
                    slice_ = line.split(":", 1)[1].strip()
    except OSError:
        return passed(root)
    if hop not in ("GENERATE", "EXECUTE"):
        return passed(root)

    # I10: do not let the human be asked to accept an EXECUTE hop with no loop behind it.
    if root and hop == "EXECUTE" and "STITCH NEEDED: accept execute" in said and not halting(last_msg) \
            and not ev.get("stop_hook_active"):
        good, why, note = hop_evidence_ok(root, hop, stage, slice_)
        if not good:
            log(root, ACTOR, "NOEVID", f"accept asked for on EXECUTE {stage} — {why}")
            if note:
                human.append(note)
            cmd = "tests/audit.sh" if stage == "10" else "tests/loop.sh"
            return nudge(root, f"Asking for accept without evidence (I10): {why}.\n"
                         f"Run `bash {cmd}` and print the score it emits. If it is not clean, fix the hop — "
                         f"do not ask for accept. If the work is genuinely blocked, end with an AUTOPILOT HALT block "
                         f"or say plainly what is unfinished.", counted=stage != "10")

    if not last_msg:
        return emit(to_human=told())
    # A complete halt ends the hop even when fenced: barbar.md's halt template is, and agents copy the fence with
    # it (code review of t63). halting() still reads a fenced halt as quotation (T40), so this is I1's rule only,
    # and it is the pre-t63 verdict for this reply.
    if any(e in said for e in EDGES) or (HALT in last_msg and "WHAT TO DO" in last_msg):
        return passed(root)

    edge = ("review spec+plan" if hop == "GENERATE" else "accept execute")
    log(root, ACTOR, "NOEDGE", f"{hop} {stage} ended without its edge line")
    return nudge(root,
        f"Hop not closed (I1). This is {hop} stage {stage or 'N'}. End the reply with exactly one "
        f"edge line, as plain text, not in a code span or block:\n"
        f"  STITCH NEEDED: {edge} for stage {stage or 'N'}"
        + (", or send back." if hop == "EXECUTE" else ".") + "\n"
        "Print it now and stop. Do not start the next hop.")


if __name__ == "__main__":
    raise SystemExit(main())
