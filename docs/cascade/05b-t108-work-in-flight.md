# Stage 05b — t108-work-in-flight — SPEC

## Problem and scope

The Stop hook's `NOEDGE` nudge can demand an edge that its own next check refuses. Seen 4 times on 2026-11-16, on
t105 GENERATE and EXECUTE and on t108's opening stop:

- a reply wrote files and started `bash tests/loop.sh` in the background (lesson L2). The hook said `Hop not closed
  (I1)`. Had the agent printed `STITCH NEEDED: accept execute`, `NOEVID` would refuse it: no receipt yet;
- a reply wrote a spec while the spec critic still ran. The hook demanded `STITCH NEEDED: review spec+plan`, which
  `NOSPECGATE` refuses while the gate is red.

The agent learns to ignore a nudge that is wrong, and each such stop is a false `NOEDGE` event for the pattern report
(t104) and for lesson L1 (since 2026-11-17).

1. **Work in flight.** On an EXECUTE loop stage (05b, 06–09), on a host whose finished background job starts the
   agent again (Claude Code; not Codex or a plugin host, critique C2), while a live process holds
   `<git dir>/cascade-loop.lock`: a stop with no edge line gets no nudge, no `NOEDGE`, and a `stop_guard PASS` line
   (`work in flight`), which `tests/patterns.sh` does not count. Not on GENERATE and not on 01–04, 10, 11: the loop
   does not run there, so a lock there is another loop's (critique C4).
2. **Unfinished step.** With no work in flight: on GENERATE 05b with a red spec gate; on an EXECUTE loop stage with no
   loop receipt for this tree; or on an EXECUTE loop stage with a fresh receipt but a red switch gate (critique C6).
   The nudge keeps the I1 words and the eventual edge line, but names the step first and never says "Print it now":
   `Hop not closed (I1), and not finished. … Do that step first: the edge line now would be refused by its own check.
   … When the step is done, end with: STITCH NEEDED: …`. Its log verdict is `UNFINISHED`, not `NOEDGE`.
3. **No verdict weaker (I18).** A green spec gate, a fresh receipt with a green switch gate, stage 10, EXECUTE 01–04
   and 11, and every other GENERATE stage still get the old "Print it now" nudge and `NOEDGE`. `NOSPECGATE`, `NOEVID`,
   `NOHALTBLOCK`, the switch check at an accept edge, autopilot and t105's answer rule run before the new rules and do
   not change.
4. **Accepted test change.** `tests/ac/t105_question_not_a_hop.sh` AC3, AC4 and AC6 accept either log verdict for a
   reply that wrote (`NOEDGE` or `UNFINISHED`, both with a nudge). Human decision 2026-11-16, recorded under the
   brief. The change is made in GENERATE and pinned in this slice's oracle, so EXECUTE cannot widen it further
   (critique C5). A reply that wrote still never passes there. t105's own manifest is history: `tests/oracle.sh` reads
   only the current slice's.

Out of scope: background subagents and other work with no lock a script can check (the spec critic: its stop gets the
step-naming nudge of item 2, which is correct but repeats up to the nudge cap); stage 10 (its check runs
`tests/audit.sh`, up to 900 s, too slow for a stop: a DIRTY audit still gets the old nudge, then `NOEVID`); any change
to when an edge is legal; the cost of the gates; a session id on the loop lock (one repo, one loop at a time).

## Approaches considered

| Approach | Decision | Reason |
|---|---|---|
| A. Read the reply: "waiting for the loop" or "in the background" means work in flight | rejected | Words are not evidence (t105). AC6 is this approach as the red twin. |
| B. Check the host's background-task list | rejected | Not visible to a hook; differs per host. |
| C. The loop lock for work in flight, and the edge's own check for the unfinished step | **chosen** | Both exist and are cheap: the lock (`tests/loop.sh:207-219`), `spec_gate_red` (about 0.3 s), `hop_evidence_ok` outside stage 10 (about 0.1 s), `switch_gate_red`. The hook asks for an edge only when it would pass. |
| D. Drop the `NOEDGE` nudge on every red gate, with no new nudge | rejected | Weaker: a hop that stops half done would end silently. |

## Before vs after

Before:

```mermaid
flowchart LR
  R[reply wrote files, hop open, no edge line] --> N[NOEDGE: print the edge]
  N --> X[agent prints the edge]
  X --> G{its check}
  G -- loop still running --> V[NOEVID refuses it]
  G -- spec gate red --> S[NOSPECGATE refuses it]
```

After (every earlier check, and t105's answer rule, runs first and is unchanged):

```mermaid
flowchart LR
  R[reply wrote files, hop open, no edge line] --> L{EXECUTE loop stage, Claude host, live loop lock?}
  L -- yes --> P[PASS: work in flight, no nudge]
  L -- no --> U{edge's own check would refuse?}
  U -- GENERATE 05b, gate red --> A[UNFINISHED: finish the spec gate first]
  U -- EXECUTE loop stage, no receipt --> B[UNFINISHED: run the loop first]
  U -- EXECUTE loop stage, switch red --> C[UNFINISHED: do the switch review first]
  U -- no, or stage 10 / 01-04 / 11 / other GENERATE --> N[NOEDGE: print it now, unchanged]
```

| Case (hop open, the reply wrote, no edge line) | Before | After |
|---|---|---|
| EXECUTE 05b/06–09, Claude host, a live process holds the loop lock | `NOEDGE` nudge | no nudge, `PASS` |
| A lock with a dead or EPERM pid, or no pid and over 1 minute old; or GENERATE, 01–04/10/11, Codex | `NOEDGE` nudge | as if no lock |
| GENERATE 05b, spec gate red | `NOEDGE`: print the edge now | `UNFINISHED`: finish the gate first |
| EXECUTE 05b/06–09, no receipt for this tree | `NOEDGE`: print the edge now | `UNFINISHED`: run the loop first |
| EXECUTE 05b/06–09, fresh receipt, switch gate red | `NOEDGE`: print the edge now | `UNFINISHED`: do the switch review first |
| Green gates, stage 10, EXECUTE 01–04/11, other GENERATE | `NOEDGE` | `NOEDGE` |

## Benefits and trade-offs

| Item | Effect | Kind |
|---|---|---|
| No false demand | The hook never asks for an edge that its next check refuses | benefit |
| True `NOEDGE` | `NOEDGE` means "the edge would pass, and it was not printed". L1 (key `NOEDGE`) counts only that | benefit |
| `UNFINISHED` is an event | It is counted by `tests/patterns.sh` under its own key: a reply that stopped mid-hop is worth seeing, and it does not mix with L1 | trade-off |
| Cost | Per stop with no edge line: one `stat` of the lock; on GENERATE 05b the spec gate (about 0.3 s); on EXECUTE the receipt fingerprint (about 0.1 s) | trade-off |
| Background critic | No lock: its stops get the `UNFINISHED` nudge, up to the nudge cap (t63), then the human is told | trade-off |
| Lock abuse | Holding the lock needs a live process; the lock is under the git dir and is the loop's own. Another terminal's loop on the same repo also counts as work in flight (no session id) | trade-off |
| Lesson rates | `UNFINISHED` takes stops that `NOEDGE` (L1) and, through fewer false edges, `NOSPECGATE` (L3) used to count. L3's `since:` needs a new day (critique C1, a human row) | trade-off |

## Decision contract

### The Stop hook (`.claude/hooks/stop_guard.py`)

5. `loop_in_flight(root)`: `True` when `<git dir>/cascade-loop.lock` is a directory and either its `pid` file names
   a live process (`os.kill(pid, 0)` succeeds; `PermissionError` is not live, as bash's `kill -0` fails on EPERM,
   critique C7) or it has no `pid` and its modification time is under 60 s old. Otherwise `False`. Same rule as
   `tests/loop.sh:207-219`. `loop_stage(hop, stage)`: EXECUTE and stage not in 01–04, 10, 11. `wakes_on_finish()`:
   not the Codex/plugin host that `emit()` serves with `decision: block`.
6. `unfinished_step(root, hop, stage, slice_)`: on GENERATE 05b, `spec_gate_red(root, "review spec+plan")`; when
   red, a step that names the gate and its failing lines. On a loop stage, `hop_evidence_ok(root, hop, stage,
   slice_)`; when not good, a step that names the reason and `bash tests/loop.sh`; then `switch_gate_red(root)`; when
   red, a step that names the Switch review. Otherwise `''`.
7. Order, right before the `NOEDGE` verdict and after t105's rule: `loop_stage and wakes_on_finish and
   loop_in_flight` → log `PASS` with `<HOP> <stage> work in flight — tests/loop.sh holds the loop lock` and return as
   a passed stop; else `unfinished_step` → log `UNFINISHED` with the step's first line (at most 160 characters) and
   send the nudge of item 2. The nudge counts toward the nudge cap.
8. No other branch changes.

### Tests and docs

9. `tests/ac/t105_question_not_a_hop.sh`: `sentback` and `sent` helpers; AC3, AC4 and AC6 use them (item 4). No
   other line changes. Done in GENERATE and pinned in `docs/cascade/05b-t108-work-in-flight.oracle`.
10. `USAGE.md` gets `### B27. Work in flight (t108)`, naming `cascade-loop.lock` and the two unfinished steps.
11. Release 3.5.10: `VERSION`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
    `.claude-plugin/marketplace.json`, `## 3.5.10` in `CHANGELOG.md`, and `README.md`.

## Acceptance criteria

The frozen oracle is `tests/ac/t108_work_in_flight.sh` (pinned in `docs/cascade/05b-t108-work-in-flight.oracle`).
Each AC runs the real hooks on a copy of this tree with its own git repository, real lock directories and a real
receipt fingerprint.

| AC | Checks | Items |
|---|---|---|
| AC1 | A live lock (live pid, or no pid and fresh) on EXECUTE 05b: no nudge, no `NOEDGE`/`UNFINISHED`, a `work in flight` PASS line; GENERATE, EXECUTE 03 and a Codex host with a live lock are not passed | 1, 5, 7 |
| AC2 | A dead-pid, an EPERM-pid, and a no-pid lock over a minute old are no lock: the reply is sent back | 5 |
| AC3 | GENERATE 05b with a red gate, EXECUTE with no receipt, EXECUTE with a red switch gate: a "not finished" nudge naming the step, never "Print it now", `UNFINISHED` not `NOEDGE` | 2, 6, 7 |
| AC4 | A green gate, a fresh receipt with a green switch gate, stage 10, EXECUTE 03 and 11, GENERATE 06: the old "Print it now" nudge and `NOEDGE` | 3 |
| AC5 | During a live lock: accept with no receipt is `NOEVID`, a halt with no `WHAT TO DO` is `NOHALTBLOCK`, an edge with a red gate is logged `NOSPECGATE` (not `UNFINISHED`) | 3, 8 |
| AC6 | Red twin: a hook that reads "waiting for the loop" lets an unfinished hop with no lock pass; the real hook does not | 1, 5 |
| AC7 | A GENERATE 05b and an EXECUTE 05b stop each under 5 s; t105 (widened, pinned) and t63 pass; USAGE.md B27; release 3.5.10 or later | 4, 9–11 |
