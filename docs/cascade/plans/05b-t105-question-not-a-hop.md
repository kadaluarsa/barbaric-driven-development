# Stage 05b — t105-question-not-a-hop — PLAN

**Spec:** [`../05b-t105-question-not-a-hop.md`](../05b-t105-question-not-a-hop.md). This plan runs only after the
EXECUTE edge is signed.

**Done when:** `bash tests/loop.sh` prints `LOOP n/n`, and the goal holds `bash tests/ac/t105_question_not_a_hop.sh`,
D1's check `bash tests/inv/D1_context_budget.sh --grow 400` (every law in force), `bash tests/lint.sh # standing`,
`bash tests/enforcement.sh # standing` and `bash tests/regress.sh # standing`.

## Tasks

| ID | Depends on | Verifies | Action |
|---|---|---|---|
| T1 | — | all | Run `bash tests/goal.sh reset` (it moves the t107 lines to `docs/cascade/regress.md`). Write the goal for slice `t105-question-not-a-hop` with the lines above. |
| T2 | — | AC3, AC4, AC7 | In `.claude/hooks/_common.py`: `tree_path`, `tree_fingerprint`, `record_tree`, `wrote_this_prompt` (spec items 5–8), in a new section after the nudge count. |
| T3 | T2 | AC7 | In `.claude/hooks/seam.py`: import `record_tree`; call it after the duplicate-event check (item 9). |
| T4 | T2 | AC1, AC2, AC5 | In `.claude/hooks/stop_guard.py`: import `wrote_this_prompt`; the new rule right before the `NOEDGE` verdict (items 10–12). Update the module docstring: the edge is owed by a reply that wrote. |
| T5 | T3, T4 | AC1–AC7 | Run the oracle. Then run `bash tests/inv/D1_context_budget.sh --grow 400`: the prompt context must not change. |
| T6 | — | AC8 | `USAGE.md` B26 (item 13); release 3.5.9 (item 14). |
| T7 | T5, T6 | all | `tests/ac/t63_quiet_stop_guard.sh` AC4, the probe after the `seam.py` prompt (lines 205–209): the fixture writes a file in `$F4` before the stop, so the stop is hop work (human decision 2026-11-16, recorded under the brief). No other line of t63 changes. Then run `bash tests/enforcement.sh`: GENERATE found no other conflict on the prototype (T96 failed there only because the prototype copy has no git history). A new conflict is a STOP for the human. |
| T8 | T7 | all | `bash tests/loop.sh` until `LOOP n/n`, under `caffeinate -dim` in the background. Print `bash tests/scorecard.sh` and `bash tests/switch.sh`. |

## Order and risk

- T2 → T3/T4 → T5 is the build; T6 is independent.
- Risk: accepted tests that run `seam.py` and then `stop_guard.py` in one session with no write and expect a nudge.
  T7 finds them; the answer is the human's, not a softer rule.
- Risk: a slow git on a large repo adds latency to each prompt and stop. Each git call has a 30 s cap and a failure
  falls back to the old verdict; AC7 bounds this repo at 5 s.
- Skills: test-driven-development applies through the frozen oracle (red now, green after T5).
