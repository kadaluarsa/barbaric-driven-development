# Stage 05b — t108-work-in-flight — PLAN

**Spec:** [`../05b-t108-work-in-flight.md`](../05b-t108-work-in-flight.md). This plan runs only after the EXECUTE edge
is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t108_work_in_flight.sh`, D1's
check `bash tests/inv/D1_context_budget.sh --grow 400` (every law in force), `bash tests/lint.sh # standing`, `bash
tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t105 line to `docs/cascade/regress.md`). Write the goal for slice `t108-work-in-flight` with the lines above. |
| T2 | — | AC1, AC2, AC6 | In `.claude/hooks/stop_guard.py`: `import time`; `loop_in_flight(root)` (spec item 5) before `scheme()`. |
| T3 | T2 | AC3, AC4 | `unfinished_step(root, hop, stage, slice_)` (item 6), then the two rules right before the `NOEDGE` verdict, after t105's rule (item 7). Update the module docstring. |
| T4 | — | AC7 | `tests/ac/t105_question_not_a_hop.sh`: the `sentback`/`sent` helpers and AC3, AC4, AC6 only (item 9; human decision 2026-11-16). The GENERATE prototype applied exactly this change and t105 stayed 8/8. |
| T5 | T3, T4 | AC1–AC7 | Run the oracle, then `bash tests/ac/t105_question_not_a_hop.sh` and `bash tests/ac/t63_quiet_stop_guard.sh`. D1 does not move: the prompt hook does not change. |
| T6 | — | AC7 | `USAGE.md` B27 (item 10); release 3.5.10 (item 11). |
| T7 | T5, T6 | all | `bash tests/enforcement.sh`. GENERATE ran it on the prototype; any conflict it found is listed in the critique dispositions. A new conflict is a STOP for the human. |
| T8 | T7 | all | `bash tests/loop.sh` until `LOOP n/n`, under `caffeinate -dim` in the background. Print `bash tests/scorecard.sh` and `bash tests/switch.sh`. |

## Order and risk

- T2 → T3 → T5 is the build; T4 and T6 are independent.
- Risk: the loop of this very hop holds the lock, so stops during T8 pass as work in flight. That is the feature; the
  accept edge still needs the receipt (`NOEVID` is unchanged, AC5).
- Risk: an accepted test that expects `NOEDGE` text on a red-gate or no-receipt fixture. T7 finds it; the answer is
  the human's.
- Skills: test-driven-development applies through the frozen oracle (red now, green after T5).
